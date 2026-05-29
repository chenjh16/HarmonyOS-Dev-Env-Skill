# Python Extension Module Adaptation Guide for HarmonyOS

This guide provides a step-by-step, general-purpose methodology for adapting Python packages that contain C, C++, or Rust extensions (`.so` dynamic libraries) on HarmonyOS. It distills patterns from our experience adapting numpy, pillow, lxml, bcrypt, greenlet, and PyTorch.

Pure Python packages (requests, flask, jinja2, etc.) work without any adaptation — just `pip install`. This guide only covers packages with native extensions.

## Phase 1: Determine Package Type

Before starting, identify which category the package falls into:

| Type | Detection | Example | Adaptation Difficulty |
|------|-----------|---------|---------------------|
| Pure Python | No `.so` in wheel, no `setup.py` compile step | requests, flask | None — pip install directly |
| C/C++ extension | `setup.py` has `ext_modules`, or wheel contains `.so` | numpy, greenlet, cffi | Medium — set CC/CXX, sign .so |
| Mixed (C lib + Python binding) | Requires external C library | pillow (libjpeg), lxml (libxml2) | High — compile C deps first |
| Rust extension (PyO3) | `Cargo.toml` present, uses maturin | bcrypt, cryptography, orjson | Medium-High — Rust toolchain + CC |
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

### Strategy D: Rust extension (maturin build)

For PyO3-based packages (bcrypt, cryptography, etc.):

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
# Create sitecustomize.py to patch platform.system()
cat > $HOME/.local/lib/python3.12/site-packages/sitecustomize.py << 'EOF'
import platform
_original_system = platform.system
def _patched_system():
    result = _original_system()
    if result == "HarmonyOS":
        return "Linux"
    return result
platform.system = _patched_system
EOF

# Step 4: Install with --no-build-isolation (pip isolation doesn't inherit RUSTFLAGS/CC)
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CXX=/data/service/hnp/bin/clang++ \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/.local/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L$HOME/.local/lib" \
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH" \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" \
pip install <package> --no-build-isolation
```

For packages that also need OpenSSL (e.g., cryptography), add extra linker paths:

```bash
# Additional flags for OpenSSL-dependent Rust packages
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L/usr/lib -L$HOME/.local/lib" \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
```

**Key issues with Rust extensions on HarmonyOS**:
1. **maturin platform check**: maturin compares `platform.system()` (returns "HarmonyOS") with Rust target OS ("Linux") and rejects mismatches. Fix with sitecustomize.py patch.
2. **pip build isolation**: pip's isolated build environment doesn't inherit RUSTFLAGS, CC, LD_LIBRARY_PATH. Must use `--no-build-isolation`.
3. **cargo linker**: No `cc` command on HarmonyOS; must set `RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"`.
4. **OpenSSL dev files**: System has libssl.so.3/libcrypto.so.3 but no headers/pkg-config. Need to download headers and create pkg-config files manually.

See [cryptography-harmonyos.md](cryptography-harmonyos.md) for a complete worked example.

### .so suffix fix

After pip install, extension modules may have wrong suffix. Our Python expects `.cpython-312-aarch64-linux-gnu.so`:

```bash
cd $HOME/.local/lib/python3.12/site-packages/<package>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

## Phase 4: Code Signing & Patchelf Repair (Most Critical)

This is the phase where most adaptations fail. ALL `.so` files must be signed AND may need patchelf repairs.

### Step 4.1: Batch code signing

Find and sign all .so files in the package directory:

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

# Also sign compiled C dependencies in $HOME/.local/lib/
find "$HOME/.local/lib" -name "*.so" -newer "$HOME/.local/lib/libjpeg.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +
```

### Step 4.2: Patchelf NEEDED path prefix fix

If the package was built with Ninja/CMake, its `.so` files may have NEEDED entries with `lib/` prefix (e.g., `lib/libfoo.so` instead of `libfoo.so`). The dynamic linker will fail to find these.

**Diagnosis**:
```bash
/data/service/hnp/bin/llvm-readelf -d <package>.so | grep NEEDED
# If you see entries like "lib/libtorch_cpu.so" instead of "libtorch_cpu.so", fix them
```

**Fix**:
```bash
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    # Strip "lib/" prefix from NEEDED entries
    /data/service/hnp/bin/patchelf --replace-needed lib/libfoo.so libfoo.so "$f"
    # Set RUNPATH so the linker can find dependencies
    /data/service/hnp/bin/patchelf --set-rpath '\''$ORIGIN:$HOME/.local/lib'\'' "$f"
  done
' sh {} +
```

### Step 4.3: Patchelf —add-needed for hidden symbols

If the package was compiled with `-fvisibility=hidden`, some symbols that other `.so` files depend on may be missing from the dynamic symbol table.

**Diagnosis**:
```bash
/data/service/hnp/bin/llvm-nm -D <main_lib>.so | grep "<missing_symbol>"
# If expected symbols are absent, you need a supplement library
```

**Fix** (supplement.so pattern from PyTorch adaptation):
```bash
# 1. Create stub implementations of missing symbols
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
| `undefined symbol: PyFloat_FromDouble` (or other Py symbols) | System Python is statically linked | Use our `-rdynamic` Python at `$HOME/.local/bin/python3` |
| `don't match ಠ_ಠ` (maturin) | platform.system() returns "HarmonyOS" vs Rust target "Linux" | Create sitecustomize.py to patch platform.system() |
| `Package openssl was not found` (pkg-config) | No openssl.pc on system | Create pkg-config files in $HOME/.local/lib/pkgconfig |
| `ld.lld: error: unable to find library -lssl` | Linker can't find libssl.so | Add `-C link-args=-L/usr/lib` to RUSTFLAGS + create unversioned symlinks |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so suffix mismatch or not signed | Rename to `.cpython-312-aarch64-linux-gnu.so` + sign |
| `platform harmonyosHongMengKernel1 is not supported` | sys.platform not recognized | Patch platform detection (e.g., `sys.platform.startswith("harmonyos")` → treat as Linux) |
| `redefinition of 'sockaddr_storage'` | HarmonyOS SDK has duplicate struct in linux/socket.h and sys/socket.h | `#define sockaddr_storage __guard` before `#include <linux/if.h>`, then `#undef` |
| `Could not invoke sanity check executable: Permission denied` | Meson build intermediate not signed | Create auto-sign clang wrapper, sign PIE executables too |
| `maturin: platform.system() don't match ಠ_ಠ` | maturin detects HarmonyOS vs Rust Linux target | sitecustomize.py patch or build directly with `maturin build` |
| `.whl is not a supported wheel on this platform` | Wheel filename has spaces in platform tag | Manual install to site-packages |
| `No module named 'typing_inspection'` | Missing dependency | `pip install typing_inspection --no-deps` |
| `gfortran: command not found` | No Fortran compiler on HarmonyOS | Cannot build scipy or other Fortran-dependent packages |
| `uvloop/libuv configure: cannot guess platform` | libuv autoconf can't detect HarmonyOS | Cannot build uvloop; musl libc lacks cpu_set_t, CPU_SETSIZE, mmsghdr |
| `.so crashes with no error / ImportError after signing` | C++ extension needs libc++_shared.so | `patchelf --add-needed libc++_shared.so` on all .so files |
| `pybind11 pkg-config not found` | matplotlib build needs pybind11 pkgconfig | Add `$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig` to PKG_CONFIG_PATH |

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

### Hard: Rust extension with C dependencies (cryptography)

1. Compile libffi from source without autotools (handle FFI_HIDDEN C/asm split, remove memcpy→bcopy macro)
2. Install cffi (sign + rename .so suffix)
3. cargo install maturin (sign binary)
4. Fix maturin platform.system() check via sitecustomize.py
5. Download OpenSSL headers + create pkg-config files + unversioned symlinks
6. pip install cryptography with --no-build-isolation and full env vars (CC, RUSTFLAGS, PKG_CONFIG_PATH, LDFLAGS with -L/usr/lib)
7. Sign cryptography .so extension

See [cryptography-harmonyos.md](cryptography-harmonyos.md) for complete details.

### Medium: Platform detection patch (psutil)

psutil uses `sys.platform.startswith("linux")` to detect Linux. HarmonyOS returns `"harmonyos"` which doesn't match.

1. Download source: `pip download psutil --no-binary :all:`
2. Patch `_common.py`: Change `LINUX = sys.platform.startswith("linux")` to `LINUX = sys.platform.startswith("linux") or sys.platform.startswith("harmonyos")`
3. Patch `psutil/arch/linux/net.c`: Wrap `#include <linux/if.h>` to prevent `sockaddr_storage` redefinition conflict:
   ```c
   #define sockaddr_storage __harmonyos_sockaddr_storage
   #include <linux/if.h>
   #undef sockaddr_storage
   ```
   (HarmonyOS SDK has `struct sockaddr_storage` defined in both `sys/socket.h` and `linux/socket.h`, causing redefinition error when `linux/if.h` includes `linux/socket.h`)
4. Build: `CC=/data/service/hnp/bin/clang CFLAGS="-B$HOME/Claude/lib/linker_wrapper" python3 setup.py build`
5. Install: `python3 setup.py install --skip-build`
6. Copy Python files manually if needed: `cp -r psutil/*.py $HOME/.local/lib/python3.12/site-packages/psutil/`
7. Sign all .abi3.so files in the package directory

### Medium: Rust extension via maturin direct build (pydantic v2)

pip's build isolation breaks maturin on HarmonyOS (doesn't inherit CC/RUSTFLAGS). Build pydantic-core directly with maturin instead.

1. Download source and extract
2. Build with maturin directly: `maturin build --release --interpreter $HOME/.local/bin/python3`
3. Extract wheel, sign .so, rename suffix: `.cpython-312.so` → `.cpython-312-aarch64-linux-gnu.so`
4. Fix WHEEL file platform tag (replace spaces with underscores)
5. Install to site-packages manually (pip can't install HarmonyOS-tagged wheels)
6. Install pydantic and fastapi: `pip install pydantic fastapi --no-deps`

**Key insight**: maturin generates `.cpython-312.so` suffix, but HarmonyOS Python expects `.cpython-312-aarch64-linux-gnu.so`. Must rename after signing. Also, maturin wheel filenames contain spaces in the platform tag — pip rejects them. Manual installation is required.

### Medium: Rust serialization via maturin direct build (orjson)

orjson is a high-performance JSON serialization library built with Rust/PyO3. The build pattern is the same as pydantic-core.

1. Download source: `pip download orjson --no-binary :all:`
2. Build with maturin directly: `maturin build --release --interpreter $HOME/.local/bin/python3`
3. Extract wheel, sign .so, rename suffix: `.cpython-312.so` → `.cpython-312-aarch64-linux-gnu.so`
4. Fix WHEEL file platform tag (replace spaces with underscores)
5. Install to site-packages manually (pip can't install HarmonyOS-tagged wheels)

**e2e test results (7/7)**: basic serialization, datetime, numpy array, UTF-8, UUID, sort keys+pretty print, performance comparison.

**Key insight**: Same maturin pattern as pydantic-core — .so suffix rename + WHEEL tag fix + manual install. No additional C dependencies needed.

### Medium: Meson build with auto-sign wrapper (pandas)

Meson builds need to execute sanity check binaries during configuration. On HarmonyOS, unsigned binaries can't execute.

1. Create auto-sign clang wrapper at `$HOME/Claude/lib/meson_wrapper/clang`:
   ```bash
   #!/bin/sh
   REAL_CC=/data/service/hnp/bin/clang
   SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool
   TMPDIR="$HOME/Claude/tmpdir"
   # Parse -o argument from command line
   OUTPUT_FILE="" # ... parse logic ...
   $REAL_CC "$@"
   # Auto-sign if output is ELF and not .o/.so/.a
   # NOTE: PIE executables have Type: DYN, not EXEC — must sign those too
   # ...sign logic...
   ```
2. Create meson native.ini pointing CC/CXX to wrapper scripts
3. Build with mesonpy: `python3 -c "import mesonpy; mesonpy.build_wheel('...')"`
4. Sign all .so in resulting wheel
5. Install manually to site-packages

**Key insight**: The wrapper must sign ALL ELF outputs (including PIE/DYN type), not just EXEC type. Meson's sanity_check is a PIE executable.

### Medium: Meson build with C++ dependencies (matplotlib)

matplotlib uses mesonpy for its build system and has C++ extensions via pybind11 (kiwisolver) and C extensions (contourpy). The build requires additional pkg-config and build dependencies.

1. Install build dependencies:
   ```bash
   pip install meson-python setuptools_scm pybind11 ninja
   # setuptools_scm needs vcs_versioning plugin
   pip install setuptools_scm_git_archive  # or equivalent vcs plugin
   ```

2. Set PKG_CONFIG_PATH to find pybind11:
   ```bash
   export PKG_CONFIG_PATH=$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig:$PKG_CONFIG_PATH
   ```

3. Build with mesonpy Python API (same auto-sign clang wrapper as pandas):
   ```bash
   python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/matplotlib_src')"
   ```

4. Extract the wheel, then for each .so file (8 total):
   ```bash
   # Sign all .so files
   find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
     for f do
       /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
       mv "${f}.signed" "$f"
     done
   ' sh {} +

   # Add libc++_shared.so as NEEDED dependency (C++ extensions need it)
   find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
     for f do
       /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
     done
   ' sh {} +

   # Rename .so suffix
   for f in *.cpython-312.so; do
     mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
   done
   ```

5. Install manually to site-packages

**e2e test results (6/6)**: line plot (savefig), histogram, scatter plot, bar chart, subplots, contour plot.

**Key insight**: matplotlib's C++ extensions (pybind11-based kiwisolver, C-based contourpy) need `libc++_shared.so` added via patchelf because HarmonyOS's Python doesn't export C++ runtime symbols. Also requires pybind11's pkgconfig path in PKG_CONFIG_PATH and setuptools_scm with vcs_versioning for version detection.

### Easy: Node.js WASM32 fallback (sharp)

sharp has no openharmony-arm64 prebuilt. The WASM32 mode works as a functional (though slower) fallback.

1. `npm install sharp` (installs base package, but native module fails)
2. `npm install --force @img/sharp-wasm32` (installs WASM32 fallback)
3. sharp automatically detects WASM32 module and uses it

**Performance**: WASM32 is ~5-10x slower than native libvips, but all image operations (resize, convert, metadata, stats) work correctly.

### Hard: Complex C++ framework (PyTorch)

1. Build with CMake + Ninja (NOT make -j)
2. Use lightweight toolchain file (no CMAKE_SYSTEM_NAME)
3. Fix all 5 patchelf issues: NEEDED prefix, RPATH, hidden symbols (supplement.so)
4. Batch sign all .so files (including build tools like protoc)
5. Set LD_LIBRARY_PATH for torch/lib

## Key Rules Summary

1. **ALL `.so` files must be signed** — unsigned .so crashes Python with no error message
2. **Always set CC/CXX** — HarmonyOS has no gcc, only clang
3. **Always set TMPDIR** — `/tmp` is read-only
4. **Always add `-B$HOME/Claude/lib/linker_wrapper`** for C++ compilation — SDK lld is broken
5. **Check .so suffix** — must be `.cpython-312-aarch64-linux-gnu.so`
6. **Check NEEDED entries** with `llvm-readelf -d` — fix `lib/` prefix with patchelf
7. **Check symbol visibility** with `llvm-nm -D` — fix hidden symbols with supplement.so
8. **Use Ninja, not make -j** — mkfifo returns EPERM on HarmonyOS
9. **Use our `-rdynamic` Python** — system Python is statically linked and cannot load .so extensions