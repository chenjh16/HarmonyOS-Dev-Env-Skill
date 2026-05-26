# Python Environment Details

## Python Installation

**Single source**: `$HOME/.local/bin/python3` (Python 3.12.8)

```
Python 3.12.8 @ $HOME/.local/
├── bin/python3          # Main binary (compiled with -rdynamic)
├── lib/python3.12/      # Standard library
│   ├── lib-dynload/     # Extension modules (must be signed)
│   └── site-packages/   # pip packages
└── include/python3.12/  # Headers (for compiling extensions)
```

**Key features**:
- Compiled with `-rdynamic`, exports 948+ Py symbols (1521 total exported symbols)
- Can load signed .so extension modules from user directories
- pip runs directly, no wrapper needed
- numpy 2.4.4 scientific computing available
- pillow 12.2.0 image processing available
- lxml 6.1.0 XML/XSLT processing available

## Shell Configuration

`~/.zshenv`:
```bash
export PATH="$HOME/.local/bin:$PATH"
export TMPDIR="$HOME/Claude/tmpdir"
export LD_LIBRARY_PATH="$HOME/.local/lib:/system/lib64"
```

**Note**: `$HOME/.local/lib` is included in LD_LIBRARY_PATH, so lxml and other dynamic library extensions load correctly.

## pip Configuration

`~/.pip/pip.conf`:
```
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
```

## Package Installation Status

| Package Type | Availability | Notes |
|--------------|-------------|-------|
| Pure Python | ✅ | pip install works directly |
| numpy | ✅ | Requires wheel rename + signing |
| C/C++ extensions | ✅ | Set CC/CXX environment variables |
| Rust extensions | ✅ | Set CC/CXX environment variables |
| pillow | ✅ | Compile libjpeg/libpng from source |
| lxml | ✅ | Compile libxml2/libxslt from source, requires LD_LIBRARY_PATH |

## C/C++/Rust Extension Package Installation

When pip builds C/C++/Rust extensions, set compiler environment variables:

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
pip install <package>
```

**Verified working packages**:
- bcrypt (Rust crate) — sign .so after compilation
- greenlet (C++ extension) — sign .so after compilation
- sqlalchemy — pure Python, depends on greenlet
- pillow — compile libjpeg-turbo 3.0.4 + libpng 1.6.48
- lxml — compile libxml2 2.14.0 + libxslt 1.1.42

**Failed packages**:
- curses — autoconf doesn't recognize 'ohos' triplet, requires config.sub modification

## numpy Installation Steps

1. **Rename wheel**: Platform tag `harmonyos_hongmeng_kernel_1_12_0_aarch64`
2. **Sign extension modules**: Suffix `.cpython-312-aarch64-linux-gnu.so`

## pillow Installation Steps

pillow requires compiling libjpeg-turbo and libpng first:

1. **Compile libjpeg-turbo 3.0.4**:
   ```bash
   cmake -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

2. **Compile libpng 1.6.48**:
   ```bash
   cmake -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

3. **Install pillow**:
   ```bash
   CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install pillow
   ```

4. **Rename extension modules**:
   ```bash
   cd ~/.local/lib/python3.12/site-packages/PIL
   for f in *.cpython-312.so; do
     mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
   done
   ```

5. **Sign extension modules**:
   ```bash
   for f in *.cpython-312-aarch64-linux-gnu.so; do
     /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}_signed"
     mv "${f}_signed" "$f"
   done
   ```

## lxml Installation Steps

lxml requires compiling libxml2, libxslt and libexslt first:

1. **Compile libxml2 2.14.0**:
   ```bash
   cmake -DLIBXML2_WITH_PYTHON=OFF -DCMAKE_SYSTEM_NAME=Linux \
     -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

2. **Compile libxslt 1.1.42** (requires manually creating xsltconfig.h):
   ```bash
   # Create xsltconfig.h adding WITH_PROFILER=1
   # Compile modules with clang, link as libxslt.so and libexslt.so
   ```

3. **Install lxml**:
   ```bash
   CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install lxml
   ```

   **Note**: `$HOME/.local/lib` is already in `LD_LIBRARY_PATH`, no additional setup needed.

4. **Rename and sign extension modules** (same as pillow)

## Extension Module Compilation Template

> **For a comprehensive, step-by-step methodology for adapting any C/Rust/C++ Python package**, see [python-extension-adaptation.md](python-extension-adaptation.md) — it covers package type classification, build environment setup, 4 compilation strategies, code signing & patchelf repair, and common error diagnosis.

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot

/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$HOME/.local/include/python3.12 \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o module.cpython-312-aarch64-linux-gnu.so \
  source.c

# Sign
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign module.so module_tmp.so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile module_tmp.so -outFile module_signed.so
```

## FAQ

### Q: Why not use the system Python?

The system Python (`/data/service/hnp/bin/python3`) is statically linked and doesn't export Py symbols, so it cannot load .so extension modules from user directories.

### Q: Why don't pip-installed C extension packages work?

pip wheel .so files may depend on `libpython3.12.so.1.0`, which our locally compiled static Python doesn't provide as a dynamic library.

### Q: How to verify symbol exports?

```bash
nm -D ~/.local/bin/python3 | grep " T " | grep Py | wc -l
# Output: 948+ (Py public API symbols)
nm -D ~/.local/bin/python3 | grep " T " | wc -l
# Output: 1521 (all exported symbols including _Py internal)
```

### Q: What to do when bcrypt/greenlet packages fail to compile?

Set `CC` and `CXX` environment variables to point to clang:
```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install bcrypt
```

### Q: What to do when pillow installation fails?

pillow requires libjpeg and libpng development libraries, which the SDK doesn't provide. Compile from source:
- libjpeg-turbo 3.0.4 → `~/.local/lib/libjpeg.a`
- libpng 1.6.48 → `~/.local/lib/libpng16.a`

### Q: What to do when lxml reports "libxml2.so.16 not found"?

Ensure `LD_LIBRARY_PATH` includes `$HOME/.local/lib`:
```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
```

This is already configured in `~/.zshenv`.

### Q: Can the curses module be used?

No. ncurses's configure script doesn't recognize the HarmonyOS (ohos) target triplet, requiring modification of config.sub files.

## Related Documentation

- [python-packages-harmonyos.md](python-packages-harmonyos.md) — Complete package compatibility report