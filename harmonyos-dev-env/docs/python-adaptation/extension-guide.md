# Python Extension Module Adaptation Guide for HarmonyOS

This guide provides a step-by-step, general-purpose methodology for adapting Python packages that contain C, C++, or Rust extensions (`.so` dynamic libraries) on HarmonyOS.

Pure Python packages (requests, flask, jinja2, etc.) work without any adaptation — just `pip install`. This guide only covers packages with native extensions.

## Phase 1: Determine Package Type

| Type | Detection | Example | Adaptation Difficulty |
|------|-----------|---------|---------------------|
| Pure Python | No `.so` in wheel, no `setup.py` compile step | requests, flask | None — pip install directly |
| C/C++ extension | `setup.py` has `ext_modules`, or wheel contains `.so` | numpy, greenlet, cffi | Medium — set CC/CXX, sign .so |
| Mixed (C lib + Python binding) | Requires external C library | pillow (libjpeg), lxml (libxml2) | High — compile C deps first |
| Rust extension (PyO3) | `Cargo.toml` present, uses maturin | pydantic-core, cryptography, rpds-py, tiktoken | Medium-High — Rust toolchain + CC + build script signing |
| Meson-based | `meson.build` present, uses meson-python | pandas, matplotlib | High — auto-sign wrapper + mesonpy API |

**Quick check**: Look at the package's PyPI page or GitHub repo. If it has `setup.py` with `Extension()` calls, `Cargo.toml`, or `.so` files in the wheel, it needs adaptation.

## Phase 2: Prepare Build Environment

All extension builds require these environment variables:

```bash
# Required for ALL C/C++ extension builds
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++

# Required on HarmonyOS (read-only /tmp)
export TMPDIR=$HOME/Claude/tmpdir

# Required for C++ builds (SDK lld is broken, must use ld.bfd wrapper)
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

**Rust extensions additionally need**:
```bash
# Cargo linker config (no 'cc' on HarmonyOS)
export RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"
```

Or add to `.cargo/config.toml`:
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
```

**Build system constraints**:
- Use **Ninja** for parallel builds (`make -j` fails because `mkfifo` returns EPERM)
- Do NOT combine `CMAKE_TOOLCHAIN_FILE` with `CMAKE_SYSTEM_NAME` — triggers cross-compile mode breaking `try_run()`

## Phase 3: Compile & Install

### Strategy A: Direct pip install (simple C/C++ extensions)

For packages like numpy, bcrypt, greenlet where the extension is self-contained:

```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
TMPDIR=$HOME/Claude/tmpdir \
pip install <package>
```

If pip can't find a compatible wheel, it will build from source. The CC/CXX env vars ensure clang is used instead of the missing gcc.

### Strategy B: Wheel platform tag rename (numpy pattern)

Some packages provide wheels but with incompatible platform tags. Rename the wheel:

```bash
# Download wheel
pip download numpy

# Rename platform tag
mv numpy-2.x-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl \
   numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl

# Install renamed wheel
pip install numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl
```

### Strategy C: Compile C dependencies first (pillow/lxml pattern)

For packages that depend on external C libraries not available on HarmonyOS:

```bash
# Step 1: Compile C dependency (example: libjpeg-turbo for pillow)
mkdir -p $HOME/Claude/tmpdir
cd libjpeg-turbo-3.0.4
cmake -GNinja \
  -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
  -DCMAKE_C_FLAGS="-B$HOME/Claude/lib/linker_wrapper" \
  -DCMAKE_INSTALL_PREFIX=$HOME/.local \
  -DENABLE_SHARED=ON \
  -DWITH_SIMD=ON \
  ..
ninja && ninja install

# Step 2: Sign compiled .so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/libjpeg.so -outFile $HOME/.local/lib/libjpeg.so.signed
mv $HOME/.local/lib/libjpeg.so.signed $HOME/.local/lib/libjpeg.so

# Step 3: pip install the Python package (it finds the C lib via LD_LIBRARY_PATH)
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
pip install pillow
```

### Strategy D: Rust extension (maturin direct build)

**CRITICAL**: On HarmonyOS, pip's build isolation breaks maturin. The maturin build backend uses HNP system Python (`/data/service/hnp/python.org/python_3.12/bin/python3.12`) which doesn't have sitecustomize.py patch, causing maturin platform check failure. Must build directly with maturin.

```bash
# Step 1: Install maturin via cargo
CC=/data/service/hnp/bin/clang \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
CARGO_HOME=$HOME/.rust \
cargo install maturin

# Step 2: Sign maturin binary
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/maturin \
  -outFile $HOME/.local/bin/maturin.signed -signAlg SHA256withECDSA
mv $HOME/.local/bin/maturin.signed $HOME/.local/bin/maturin

# Step 3: Fix platform.system() mismatch (maturin rejects "HarmonyOS" vs Rust "Linux")
# This is handled by sitecustomize.py patch (already installed)

# Step 4: Build directly with maturin (NOT pip install)
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-B$HOME/Claude/lib/linker_wrapper" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# For packages needing OpenSSL:
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L/usr/lib -L$HOME/.local/lib" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# For tokenizers specifically, add fancy-regex feature:
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3 --features fancy-regex
```

**Key issues with Rust extensions on HarmonyOS**:
1. **maturin platform check**: maturin compares `platform.system()` (returns "HarmonyOS") with Rust target OS ("Linux") and rejects mismatches. Fix with sitecustomize.py patch.
2. **pip build isolation**: pip's isolated build environment doesn't inherit RUSTFLAGS, CC, LD_LIBRARY_PATH. Must build directly with maturin.
3. **cargo linker**: No `cc` command on HarmonyOS; must set `RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"`.
4. **OpenSSL dev files**: System has libssl.so.3/libcrypto.so.3 but no headers/pkg-config. Need to download headers and create pkg-config files manually.
5. **Build script signing loop**: Packages with Cargo build scripts (orjson, tokenizers, safetensors) need rustc auto-sign wrapper — see [rustc-wrapper.md](rustc-wrapper.md).
6. **abi3 wheel**: Some Rust/PyO3 packages (tokenizers, safetensors) produce abi3 wheels with `.abi3.so` suffix, which doesn't need renaming to `.cpython-312-aarch64-linux-gnu.so`.
7. **fancy-regex feature**: tokenizers requires one of `onig` or `fancy-regex`. onig (C oniguruma library) doesn't compile on HarmonyOS. Use `fancy-regex` instead: `maturin build --features fancy-regex`.

### .so suffix fix

After pip install, extension modules may have wrong suffix. Our Python expects `.cpython-312-aarch64-linux-gnu.so`:

```bash
cd $HOME/.local/lib/python3.12/site-packages/<package>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

**Note**: abi3 wheels use `.abi3.so` suffix which is compatible with all Python 3.x versions — no rename needed.

## Phase 4: Code Signing & Patchelf Repair (Most Critical)

This is the phase where most adaptations fail. ALL `.so` files must be signed AND may need patchelf repairs.

### Step 4.1: Batch code signing

```bash
SIGN_DIR=$HOME/.local/lib/python3.12/site-packages/<package>

# Remove stale .codesign sections first (prevents sign failures)
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
  done
' sh {} +

# Sign all .so files
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +
```

### Step 4.2: Patchelf NEEDED path prefix fix

If the package was built with Ninja/CMake, its `.so` files may have NEEDED entries with `lib/` prefix:

**Diagnosis**:
```bash
/data/service/hnp/bin/llvm-readelf -d <package>.so | grep NEEDED
# If you see "lib/libtorch_cpu.so" instead of "libtorch_cpu.so", fix them
```

**Fix**:
```bash
/data/service/hnp/bin/patchelf --replace-needed lib/libfoo.so libfoo.so "$f"
/data/service/hnp/bin/patchelf --set-rpath '$ORIGIN:$HOME/.local/lib' "$f"
```

### Step 4.3: Patchelf --add-needed for hidden symbols

If the package was compiled with `-fvisibility=hidden`, some symbols may be missing:

**Diagnosis**:
```bash
/data/service/hnp/bin/llvm-nm -D <main_lib>.so | grep "<missing_symbol>"
```

**Fix** (supplement.so pattern from PyTorch adaptation):
```bash
# 1. Create stub implementations
cat > supplement.c << 'EOF'
void missing_symbol_1() {}
void missing_symbol_2() {}
EOF

# 2. Compile supplement .so
/data/service/hnp/bin/clang -B$HOME/Claude/lib/linker_wrapper -shared \
  -o lib<package>_supplement.so supplement.c

# 3. Add as NEEDED dependency
/data/service/hnp/bin/patchelf --add-needed lib<package>_supplement.so <main_lib>.so

# 4. Sign both
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile lib<package>_supplement.so -outFile signed && mv signed lib<package>_supplement.so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <main_lib>.so -outFile signed && mv signed <main_lib>.so
```

### Step 4.4: Rust/PyO3 Build Script Signing Loop

See dedicated guide: [rustc-wrapper.md](rustc-wrapper.md)

### Step 4.5: C++ Extension Patchelf-Sign Workflow (libc++_shared.so)

C++ extension packages need `libc++_shared.so` for C++ runtime symbols. However, `patchelf` cannot modify signed .so files.

**Workflow**: strip codesign → patchelf → re-sign → rename suffix

```bash
SIGN_DIR=$HOME/.local/lib/python3.12/site-packages/<package>

# Step 1: Strip .codesign section (patchelf needs un-signed ELF)
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
  done
' sh {} +

# Step 2: Add libc++_shared.so as NEEDED dependency
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
  done
' sh {} +

# Step 3: Re-sign all .so files
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
    mv "${f}.signed" "$f"
  done
' sh {} +

# Step 4: Rename suffix
cd "$SIGN_DIR"
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

**Key insight**: Order matters — `llvm-objcopy --remove-section .codesign` must come before `patchelf`, and `binary-sign-tool sign` must come after patchelf.

### Step 4.6: cffi Rebuild with LDFLAGS for libffi Path

cffi 2.0.0 needs `libffi.so.8` during build. On HarmonyOS, libffi is at `$HOME/.local/lib/libffi.so.8` (compiled from source).

```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
LDFLAGS="-L$HOME/.local/lib -L/usr/lib -B$HOME/Claude/lib/linker_wrapper" \
TMPDIR=$HOME/Claude/tmpdir \
pip install cffi --no-binary :all:

# After install: sign _cffi_backend.so and rename suffix
cd $HOME/.local/lib/python3.12/site-packages/_cffi_backend*
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile _cffi_backend.cpython-312.so \
  -outFile _cffi_backend.cpython-312.so.signed -signAlg SHA256withECDSA
mv _cffi_backend.cpython-312.so.signed _cffi_backend.cpython-312-aarch64-linux-gnu.so
```

### Step 4.7: asyncio.current_task Segfault Fix

`asyncio.current_task()` segfaults on HarmonyOS when called outside an async context. This affects any package that uses Python's logging module with asyncio task tracking (structlog, etc.).

**Diagnosis**: Import crashes with segfault (no Python traceback). Crash occurs in `logging/__init__.py` line ~375 where `self.taskName = asyncio.current_task().get_name()` is called.

**Fix**:
```bash
# Patch logging/__init__.py: change logAsyncioTasks from True to False
sed -i 's/logAsyncioTasks = True/logAsyncioTasks = False/' \
  $HOME/.local/lib/python3.12/logging/__init__.py

# Also add sys._logAsyncioTasks = False in sitecustomize.py
echo '' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
echo '# Disable asyncio task tracking in logging to avoid crash on HarmonyOS' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
echo 'sys._logAsyncioTasks = False' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
```

**When to apply**: If any package segfaults on import with no Python traceback, check if it uses `logging` + `asyncio`. This is a system-wide fix.

## Phase 5: Verify & Run

### Step 5.1: Add dependency libraries to LD_LIBRARY_PATH

```bash
# For packages with compiled C dependencies
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# For packages with .so in non-standard locations (e.g., PyTorch)
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/<package>/lib:$LD_LIBRARY_PATH
```

### Step 5.2: Import test

```bash
python3 -c "import <package>; print('<package> imported successfully')"
```

### Common Error Diagnosis

| Error | Cause | Fix |
|-------|-------|-----|
| `ImportError: dynamic module does not define module export function` | .so suffix mismatch | Rename to `.cpython-312-aarch64-linux-gnu.so` |
| `OSError: <package>.so: cannot open shared object file` | Missing NEEDED library / wrong RPATH | Add lib to LD_LIBRARY_PATH or `patchelf --set-rpath` |
| `Symbol not found: decref/incref/invoke_parallel` | `-fvisibility=hidden` hides symbols | Create supplement.so, `patchelf --add-needed` |
| `Error loading shared library lib/libfoo.so` | NEEDED has `lib/` prefix | `patchelf --replace-needed lib/libfoo.so libfoo.so` |
| `cc: command not found` / `c++: command not found` | No gcc on system | Set `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` |
| `Operation not permitted` (mkfifo) | make -j fails on HarmonyOS | Use Ninja instead |
| `unittest.SkipTest: cannot load extension module` | .so not signed | `binary-sign-tool sign -selfSign 1` |
| `undefined symbol: PyFloat_FromDouble` | System Python is statically linked | Use our `-rdynamic` Python at `$HOME/.local/bin/python3` |
| `don't match ಠ_ಠ` (maturin) | platform.system() returns "HarmonyOS" | sitecustomize.py patch or maturin direct build |
| `Package openssl was not found` (pkg-config) | No openssl.pc on system | Create pkg-config files in $HOME/.local/lib/pkgconfig |
| `ld.lld: error: unable to find library -lssl` | Linker can't find libssl.so | Add `-C link-args=-L/usr/lib` to RUSTFLAGS + create unversioned symlinks |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so suffix mismatch or not signed | Rename + sign |
| `platform harmonyosHongMengKernel1 is not supported` | sys.platform not recognized | Patch platform detection to treat as Linux |
| `redefinition of 'sockaddr_storage'` | Duplicate struct in linux/socket.h and sys/socket.h | `#define sockaddr_storage __guard` before `#include <linux/if.h>`, then `#undef` |
| `Could not invoke sanity check executable: Permission denied` | Meson build intermediate not signed | Create auto-sign clang wrapper |
| `.whl is not a supported wheel on this platform` | Wheel filename has spaces in platform tag | Manual install to site-packages |
| `gfortran: command not found` | No Fortran compiler on HarmonyOS | Cannot build scipy or other Fortran packages |
| `.so crashes with no error / ImportError after signing` | C++ extension needs libc++_shared.so | `patchelf --add-needed libc++_shared.so` |
| `Segfault on import (no Python traceback)` | asyncio.current_task() crashes outside async context | Patch logging/__init__.py + sitecustomize.py |
| `-lffi: No such file or directory` | Linker can't find libffi.so.8 | Add `LDFLAGS="-L$HOME/.local/lib"` when building cffi |
| `patchelf: Operation not permitted` on .so | patchelf can't modify signed .so | Strip codesign first: `llvm-objcopy --remove-section=.codesign` → patchelf → re-sign |
| `_ZdlPv: symbol not found` / `operator delete` | C++ extension missing libc++_shared.so | `patchelf --add-needed libc++_shared.so` (use Step 4.5 workflow) |
| `pybind11 pkg-config not found` | matplotlib build needs pybind11 pkgconfig | Add pybind11 share/pkgconfig to PKG_CONFIG_PATH |

## Adaptation Examples by Difficulty

### Easy: Simple C extension (bcrypt, greenlet)

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export TMPDIR=$HOME/Claude/tmpdir
pip install bcrypt
# Find and sign .so
find ~/.local/lib/python3.12/site-packages/bcrypt -name "*.so" | \
  xargs -I{} /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile {} -outFile {}.s && \
  find ~/.local/lib/python3.12/site-packages/bcrypt -name "*.so.s" | \
  while read f; do mv "$f" "${f%.s}"; done
python3 -c "import bcrypt; print(bcrypt.hashpw('test', bcrypt.gensalt()))"
```

### Medium: Package with C dependencies (pillow, lxml)

1. Compile C dependency from source (libjpeg-turbo, libxml2, etc.)
2. Sign the compiled .so
3. `pip install` the Python package with CC/CXX set
4. Fix .so suffix if needed
5. Sign all package .so files
6. Add `$HOME/.local/lib` to LD_LIBRARY_PATH

### Medium: Platform detection patch (psutil)

psutil uses `sys.platform.startswith("linux")` to detect Linux. HarmonyOS returns `"harmonyos"` which doesn't match.

1. Download source: `pip download psutil --no-binary :all:`
2. Patch `_common.py`: `LINUX = sys.platform.startswith("linux") or sys.platform.startswith("harmonyos")`
3. Patch `psutil/arch/linux/net.c`: Guard sockaddr_storage redefinition:
   ```c
   #define sockaddr_storage __harmonyos_sockaddr_storage
   #include <linux/if.h>
   #undef sockaddr_storage
   ```
4. Build: `CC=/data/service/hnp/bin/clang CFLAGS="-B$HOME/Claude/lib/linker_wrapper" python3 setup.py build`
5. Install: `python3 setup.py install --skip-build`
6. Sign all .abi3.so files

### Medium: Rust extension via maturin direct build (pydantic v2)

See Strategy D in Phase 3. Key points:
- Build pydantic-core directly with `maturin build --release --interpreter $HOME/.local/bin/python3`
- Sign .so, rename suffix to `.cpython-312-aarch64-linux-gnu.so`
- Fix WHEEL platform tag (spaces → underscores)
- Install manually to site-packages
- Then `pip install pydantic fastapi --no-deps`

### Hard: Rust extension with build script signing loop (orjson)

Use the rustc auto-sign wrapper — see [rustc-wrapper.md](rustc-wrapper.md). Additional orjson-specific steps: pre-compile yyjson.c into `libyyjson.a` and remove `cc` crate dependency from Cargo.toml.

### Medium: Meson build (pandas, matplotlib)

See [meson-wrapper.md](meson-wrapper.md) for the auto-sign clang wrapper technique.

### Hard: Complex C++ framework (PyTorch)

See [pytorch-harmonyos.md](../pytorch-harmonyos.md) for the complete 15-adaptation guide.

## Key Rules Summary

1. **ALL `.so` files must be signed** — unsigned .so crashes Python with no error message
2. **Always set CC/CXX** — HarmonyOS has no gcc, only clang
3. **Always set TMPDIR** — `/tmp` is read-only
4. **Always add `-B$HOME/Claude/lib/linker_wrapper`** for C++ compilation — SDK lld is broken
5. **Check .so suffix** — must be `.cpython-312-aarch64-linux-gnu.so` (abi3 wheels use `.abi3.so`)
6. **Check NEEDED entries** with `llvm-readelf -d` — fix `lib/` prefix with patchelf
7. **Check symbol visibility** with `llvm-nm -D` — fix hidden symbols with supplement.so
8. **Use Ninja, not make -j** — mkfifo returns EPERM on HarmonyOS
9. **Use our `-rdynamic` Python** — system Python is statically linked and cannot load .so extensions