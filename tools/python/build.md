# Python 3.12.8 on HarmonyOS - Complete Build Guide

> **中文版本请查看 build.cn.md**

## Overview

This guide documents the complete process for building Python 3.12.8 from source on HarmonyOS. The key challenge is that the system Python cannot load user-installed extension modules (.so files) because it's statically linked and doesn't export Python API symbols.

**Solution**: Build Python with `-rdynamic` flag to export all symbols, enabling extension module loading.

## Prerequisites

- HarmonyOS SDK with clang 15.0.4
- Writable TMPDIR (HarmonyOS `/tmp` is read-only)
- About 500MB disk space for build
- **ld.bfd wrapper** (SDK's lld requires libxml2.so.16 which doesn't exist)
- **clang wrapper** (configure test binaries need code signing to execute)

## Critical: clang Wrapper for configure

Configure generates test binaries (`conftest`) that must be code-signed before execution on HarmonyOS. Create wrapper scripts:

```bash
mkdir -p $HOME/Claude/bin

# clang wrapper: auto-sign binaries + handle --print-multiarch
cat > $HOME/Claude/bin/clang-wrapper << 'EOF'
#!/bin/sh
REAL_CLANG=/data/service/hnp/bin/clang
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool

# Handle --print-multiarch specially to match PLATFORM_TRIPLET
if echo "$*" | grep -q -- "--print-multiarch"; then
    echo "aarch64-linux-gnu"
    exit 0
fi

"$REAL_CLANG" "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    OUTPUT=""
    PREV=""
    for arg in "$@"; do
        if [ "$PREV" = "-o" ]; then
            OUTPUT="$arg"
            break
        fi
        case "$arg" in -o*) OUTPUT="${arg#-o}"; break ;; esac
        PREV="$arg"
    done
    if [ -n "$OUTPUT" ] && [ -f "$OUTPUT" ]; then
        if file "$OUTPUT" 2>/dev/null | grep -q "ELF"; then
            "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT" -outFile "$OUTPUT.signed" -signAlg SHA256withECDSA 2>/dev/null
            if [ -f "$OUTPUT.signed" ]; then
                mv "$OUTPUT.signed" "$OUTPUT"
                chmod +x "$OUTPUT"
            fi
        fi
    fi
fi
exit $EXIT_CODE
EOF

# clang++ wrapper (similar logic)
cat > $HOME/Claude/bin/clang++-wrapper << 'EOF'
#!/bin/sh
REAL_CLANG=/data/service/hnp/bin/clang++
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool

"$REAL_CLANG" "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    OUTPUT=""
    PREV=""
    for arg in "$@"; do
        if [ "$PREV" = "-o" ]; then OUTPUT="$arg"; break; fi
        case "$arg" in -o*) OUTPUT="${arg#-o}"; break ;; esac
        PREV="$arg"
    done
    if [ -n "$OUTPUT" ] && [ -f "$OUTPUT" ] && file "$OUTPUT" 2>/dev/null | grep -q "ELF"; then
        "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT" -outFile "$OUTPUT.signed" -signAlg SHA256withECDSA 2>/dev/null
        [ -f "$OUTPUT.signed" ] && mv "$OUTPUT.signed" "$OUTPUT" && chmod +x "$OUTPUT"
    fi
fi
exit $EXIT_CODE
EOF

chmod +x $HOME/Claude/bin/clang-wrapper $HOME/Claude/bin/clang++-wrapper
```

**Why --print-multiarch hack?**:
- `clang --print-multiarch` returns `aarch64-linux-ohos`
- Configure's preprocessor test detects `aarch64-linux-gnu`
- Configure requires these to match, causing triplet error
- Wrapper returns `aarch64-linux-gnu` to match the preprocessor result

## Critical: ld.bfd Wrapper

The SDK's lld linker dynamically links to `libxml2.so.16` which doesn't exist on HarmonyOS. You MUST use ld.bfd instead:

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

Then use `-B$HOME/Claude/lib/linker_wrapper` in all clang compilation commands.

## Source Code

```bash
cd $HOME/Claude/python-build
wget https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tar.xz
tar xf Python-3.12.8.tar.xz
cd Python-3.12.8
```

## Build Steps

### Step 1: Fix configure for HarmonyOS

HarmonyOS has several differences from standard Linux that require configure modifications:

```bash
# Fix 1: Temporary directory (HarmonyOS /tmp is read-only)
sed -i 's|mktemp -d "./confXXXXXX"|mktemp -d "${TMPDIR:-$HOME/Claude/tmpdir}/confXXXXXX"|g' configure
sed -i 's|umask 077 && mkdir "$tmp"|mkdir "$tmp"|g' configure

# Fix 2: Platform triplet (config.guess can't identify HarmonyOS)
echo '#!/bin/sh
echo "aarch64-linux-gnu"' > config.guess
chmod +x config.guess
```

### Step 2: Configure

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
LINKER_WRAPPER_DIR=$HOME/Claude/lib/linker_wrapper

TMPDIR=$HOME/Claude/tmpdir \
CC=$HOME/Claude/bin/clang-wrapper \
CXX=$HOME/Claude/bin/clang++-wrapper \
CFLAGS="--sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR" \
CXXFLAGS="--sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR" \
LDFLAGS="--sysroot=$SYSROOT -L$SYSROOT/usr/lib/aarch64-linux-ohos -rdynamic -B$LINKER_WRAPPER_DIR" \
./configure \
  --prefix=$HOME/.local \
  --disable-shared \
  --host=aarch64-linux-gnu \
  --build=aarch64-linux-gnu
```

**Key parameters explained**:
- `-rdynamic`: **Critical** - exports all symbols for extension module loading
- `-B$LINKER_WRAPPER_DIR`: **Critical** - bypass broken lld, use ld.bfd
- `--sysroot`: HarmonyOS SDK sysroot path
- `--disable-shared`: Build only executable, not libpython.so (HarmonyOS lacks libdl.so/libm.so)
- `CC/CXX`: **Critical** - use wrapper scripts, not direct clang
- `--host/--build`: Set triplet to `aarch64-linux-gnu` to avoid triplet mismatch

### Step 3: Fix pyconfig.h for missing HarmonyOS features

```bash
# Wait for configure to complete, then fix pyconfig.h
sed -i 's/#define HAVE_LIBINTL_H 1/\/* #undef HAVE_LIBINTL_H *\//' pyconfig.h
sed -i 's/#define HAVE_LINUX_CAN_RAW_FD_FRAMES 1/\/* #undef HAVE_LINUX_CAN_RAW_FD_FRAMES *\//' pyconfig.h
sed -i 's/#define HAVE_LINUX_CAN_RAW_JOIN_FILTERS 1/\/* #undef HAVE_LINUX_CAN_RAW_JOIN_FILTERS *\//' pyconfig.h
```

### Step 4: Build

```bash
make python.exe
```

This produces `python.exe` (~40MB).

### Step 5: Sign the binary

All ELF binaries must be signed before execution on HarmonyOS:

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile python.exe \
  -outFile python_signed \
  -signAlg SHA256withECDSA
chmod 755 python_signed
```

### Step 6: Install

```bash
# Create directories
mkdir -p $HOME/.local/bin
mkdir -p $HOME/.local/lib/python3.12
mkdir -p $HOME/.local/include/python3.12
mkdir -p $HOME/.local/lib/python3.12/lib-dynload

# Install binary
cp python_signed $HOME/.local/bin/python3.12
ln -sf python3.12 $HOME/.local/bin/python3
ln -sf python3.12 $HOME/.local/bin/python

# Install standard library
cp -r Lib/* $HOME/.local/lib/python3.12/

# Install headers (for building extensions)
cp -r Include/* $HOME/.local/include/python3.12/
cp pyconfig.h $HOME/.local/include/python3.12/

# Install static library
cp libpython3.12.a $HOME/.local/lib/
```

### Step 7: Build essential extension modules

Two critical extension modules need to be built for pip to work:

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
PYTHON_INCLUDE=$HOME/.local/include/python3.12

# Build _pickle
/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$PYTHON_INCLUDE \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o _pickle.so \
  ./Modules/_pickle.c \
  -L$SYSROOT/usr/lib/aarch64-linux-ohos

# Build _datetime  
/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$PYTHON_INCLUDE \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o _datetime.so \
  ./Modules/_datetimemodule.c \
  -L$SYSROOT/usr/lib/aarch64-linux-ohos

# Sign and install
for module in _pickle _datetime; do
  /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign ${module}.so ${module}_unsigned.so
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile ${module}_unsigned.so \
    -outFile $HOME/.local/lib/python3.12/lib-dynload/${module}.cpython-312-aarch64-linux-gnu.so \
    -signAlg SHA256withECDSA
done
```

### Step 8: Install pip

```bash
# Download get-pip.py
curl -L https://bootstrap.pypa.io/get-pip.py -o $HOME/Claude/tmpdir/get-pip.py

# Install pip
$HOME/.local/bin/python3 $HOME/Claude/tmpdir/get-pip.py

# Configure pip mirror
mkdir -p $HOME/.pip
echo '[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple' > $HOME/.pip/pip.conf
```

### Step 9: Configure sysconfigdata

```bash
# Copy and rename sysconfigdata for HarmonyOS platform name
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/_sysconfigdata__linux_.py \
   $HOME/.local/lib/python3.12/_sysconfigdata__harmonyosHongMengKernel1_aarch64-linux-ohos.py
```

## Verification

```bash
# Test Python version
python3 --version
# Python 3.12.8

# Test extension module loading
python3 -c "import pickle; print(pickle.dumps([1,2,3]))"
# b'\x80\x04\x95...

# Test datetime
python3 -c "import datetime; print(datetime.datetime.now())"
# 2026-05-18 ...

# Test pip
python3 -m pip --version
# pip 24.3.1 from ...
```

## Symbol Export Comparison

| Python Build | Exported Py Symbols | Extension Loading |
|--------------|---------------------|-------------------|
| System Python (static) | 0 | Permission denied |
| Local Python (-rdynamic) | 948+ | SUCCESS |

Verify with:
```bash
nm -D $HOME/.local/bin/python3 | grep " T " | grep Py | wc -l
# 948
```

## Installing numpy

For numpy, use the prebuilt HarmonyOS wheel approach. The wheel must be renamed to match pip's expected platform tag:

**Prerequisite**: Obtain numpy wheel with `harmonyos_aarch64` platform tag. This is NOT available on PyPI - it comes from HarmonyOS-specific sources or must be built locally.

```bash
# If you have numpy-2.4.4-cp312-cp312-harmonyos_aarch64.whl, rename it:
cp numpy-2.4.4-cp312-cp312-harmonyos_aarch64.whl \
   numpy-2.4.4-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl

# Install with --no-deps
pip install numpy-2.4.4-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl --no-deps

# Rename and sign extension modules (wheel .so suffix differs from expected)
cd $HOME/.local/lib/python3.12/site-packages/numpy
find . -name "*.cpython-312.so" | while read f; do
    new_name="${f%.so}-aarch64-linux-gnu.so"
    cp "$f" "$new_name"
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$new_name" "${new_name}.tmp"
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "${new_name}.tmp" -outFile "$new_name" -signAlg SHA256withECDSA
    rm "${new_name}.tmp"
done
```

**Key points**:
1. HarmonyOS Python platform tag is `harmonyos_hongmeng_kernel_1_12_0_aarch64`
2. Wheel must be renamed from `harmonyos_aarch64` to match this tag
3. Extension suffix in wheel is `.cpython-312.so`, but Python expects `.cpython-312-aarch64-linux-gnu.so`
4. All .so files must be code-signed

## Known Limitations

1. **curses module**: ncurses configure doesn't recognize HarmonyOS triplet
2. **locale support**: Limited (no pt_BR, collate, ctype locales)
3. **BLAS/LAPACK**: Not available from SDK, affects numpy performance

## Build Time

- Configure: ~5 minutes
- Build python.exe: ~15 minutes (single-threaded)
- Extension modules: ~2 minutes each
- Total: ~30 minutes

## Disk Space

- Source: 20MB (tar.xz)
- Build: 400MB
- Installation: 60MB