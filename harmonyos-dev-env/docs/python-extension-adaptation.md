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
| Rust extension (PyO3) | `Cargo.toml` present, uses maturin | bcrypt, cryptography | Medium-High — Rust toolchain + CC |

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

For PyO3-based packages:

```bash
# Install maturin
pip install maturin

# Build wheel
maturin build --release --target aarch64-unknown-linux-ohos \
  --cargo-flags="-C linker=/data/service/hnp/bin/clang"

# Install built wheel
pip install target/wheels/<package>-*.whl
```

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
for f in $(find "$SIGN_DIR" -name "*.so" -type f); do
  /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
  mv "$f.tmp" "$f"
done

# Sign all .so files
for f in $(find "$SIGN_DIR" -name "*.so" -type f); do
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile "$f" -outFile "${f}.signed"
  mv "${f}.signed" "$f"
done

# Also sign compiled C dependencies in $HOME/.local/lib/
for f in $(find $HOME/.local/lib -name "*.so" -newer $HOME/.local/lib/libjpeg.so -type f); do
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile "$f" -outFile "${f}.signed"
  mv "${f}.signed" "$f"
done
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
for f in $(find "$SIGN_DIR" -name "*.so" -type f); do
  # Strip "lib/" prefix from NEEDED entries
  /data/service/hnp/bin/patchelf --replace-needed lib/libfoo.so libfoo.so "$f"
  # Set RUNPATH so the linker can find dependencies
  /data/service/hnp/bin/patchelf --set-rpath '$ORIGIN:$HOME/.local/lib' "$f"
done
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