#!/bin/sh
# Python 3.12.8 Installation Script for HarmonyOS
# This script builds Python from source with -rdynamic for extension module support
#
# Usage: ./install.sh [--skip-build] [--skip-pip]
#
# Options:
#   --skip-build    Skip building Python (use existing python.exe)
#   --skip-pip      Skip pip installation

set -e

# Configuration
PYTHON_VERSION="3.12.8"
INSTALL_DIR="$HOME/.local"
BUILD_DIR="$HOME/Claude/python-build"
TMPDIR="$HOME/Claude/tmpdir"
SYSROOT="/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
CLANG="/data/service/hnp/bin/clang"
LINKER_WRAPPER_DIR="$HOME/Claude/lib/linker_wrapper"

# Parse arguments
SKIP_BUILD=false
SKIP_PIP=false

for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
        --skip-pip) SKIP_PIP=true ;;
    esac
done

echo "========================================"
echo "Python $PYTHON_VERSION Installation on HarmonyOS"
echo "========================================"
echo ""

# Step 1: Create directories and linker wrapper
echo "[1/9] Creating directories..."
mkdir -p "$BUILD_DIR"
mkdir -p "$TMPDIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib/python3.12/lib-dynload"
mkdir -p "$INSTALL_DIR/include/python3.12"

# Create ld.bfd wrapper (SDK's lld requires libxml2.so.16 which doesn't exist)
mkdir -p "$LINKER_WRAPPER_DIR"
if [ ! -f "$LINKER_WRAPPER_DIR/ld.lld" ]; then
    cat > "$LINKER_WRAPPER_DIR/ld.lld" << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
    chmod +x "$LINKER_WRAPPER_DIR/ld.lld"
    echo "Created linker wrapper at $LINKER_WRAPPER_DIR/ld.lld"
fi

# Step 2: Download source
if [ ! -f "$BUILD_DIR/Python-$PYTHON_VERSION.tar.xz" ]; then
    echo "[2/9] Downloading Python source..."
    cd "$BUILD_DIR"
    curl -fL "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tar.xz" \
        -o "Python-$PYTHON_VERSION.tar.xz"
else
    echo "[2/9] Source already downloaded, skipping..."
fi

# Step 3: Extract source
echo "[3/9] Extracting source..."
cd "$BUILD_DIR"
if [ ! -d "Python-$PYTHON_VERSION" ]; then
    tar xf "Python-$PYTHON_VERSION.tar.xz"
fi
cd "Python-$PYTHON_VERSION"

# Step 4: Fix configure
echo "[4/9] Fixing configure for HarmonyOS..."
sed -i 's|mktemp -d "./confXXXXXX"|mktemp -d "${TMPDIR:-$HOME/Claude/tmpdir}/confXXXXXX"|g' configure
sed -i 's|umask 077 && mkdir "$tmp"|mkdir "$tmp"|g' configure

# Create config.guess for HarmonyOS
echo '#!/bin/sh
echo "aarch64-linux-gnu"' > config.guess
chmod +x config.guess

# Step 5: Configure and build
if [ "$SKIP_BUILD" = false ]; then
    echo "[5/9] Configuring Python..."
    TMPDIR="$TMPDIR" \
    CC="$CLANG" \
    CFLAGS="--sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR" \
    LDFLAGS="--sysroot=$SYSROOT -L$SYSROOT/usr/lib/aarch64-linux-ohos -rdynamic -B$LINKER_WRAPPER_DIR" \
    ./configure \
        --prefix="$INSTALL_DIR" \
        --disable-shared || { echo "Configure failed!"; exit 1; }

    # Fix pyconfig.h
    echo "[5/9] Fixing pyconfig.h..."
    sed -i 's/#define HAVE_LIBINTL_H 1/\/* #undef HAVE_LIBINTL_H *\//' pyconfig.h
    sed -i 's/#define HAVE_LINUX_CAN_RAW_FD_FRAMES 1/\/* #undef HAVE_LINUX_CAN_RAW_FD_FRAMES *\//' pyconfig.h
    sed -i 's/#define HAVE_LINUX_CAN_RAW_JOIN_FILTERS 1/\/* #undef HAVE_LINUX_CAN_RAW_JOIN_FILTERS *\//' pyconfig.h

    echo "[5/9] Building Python..."
    make python.exe || { echo "Build failed!"; exit 1; }
else
    echo "[5/9] Skipping build (--skip-build)"
fi

# Step 6: Sign binary
echo "[6/9] Signing Python binary..."
$SIGN_TOOL sign -selfSign 1 \
    -inFile python.exe \
    -outFile python_signed \
    -signAlg SHA256withECDSA
chmod 755 python_signed

# Step 7: Install Python
echo "[7/9] Installing Python..."
cp python_signed "$INSTALL_DIR/bin/python3.12"
ln -sf python3.12 "$INSTALL_DIR/bin/python3"
ln -sf python3.12 "$INSTALL_DIR/bin/python"

# Install standard library
cp -r Lib/* "$INSTALL_DIR/lib/python3.12/"

# Install headers
cp -r Include/* "$INSTALL_DIR/include/python3.12/"
cp pyconfig.h "$INSTALL_DIR/include/python3.12/"

# Install static library
cp libpython3.12.a "$INSTALL_DIR/lib/"

# Step 8: Build extension modules
echo "[8/9] Building essential extension modules..."

# Build _pickle
$CLANG -shared --sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR \
    -I"$INSTALL_DIR/include/python3.12" \
    -I./Include \
    -I./Include/internal \
    -DPy_BUILD_CORE_MODULE \
    -o _pickle.so \
    ./Modules/_pickle.c \
    -L$SYSROOT/usr/lib/aarch64-linux-ohos

# Build _datetime
$CLANG -shared --sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR \
    -I"$INSTALL_DIR/include/python3.12" \
    -I./Include \
    -I./Include/internal \
    -DPy_BUILD_CORE_MODULE \
    -o _datetime.so \
    ./Modules/_datetimemodule.c \
    -L$SYSROOT/usr/lib/aarch64-linux-ohos

# Sign and install extension modules
for module in _pickle _datetime; do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "${module}.so" "${module}_unsigned.so"
    $SIGN_TOOL sign -selfSign 1 \
        -inFile "${module}_unsigned.so" \
        -outFile "$INSTALL_DIR/lib/python3.12/lib-dynload/${module}.cpython-312-aarch64-linux-gnu.so" \
        -signAlg SHA256withECDSA
    rm "${module}_unsigned.so" "${module}.so"
done

# Copy sysconfigdata
echo "[8/9] Configuring sysconfigdata..."
# Determine correct platform name for sysconfigdata
PLATFORM_NAME=$("$INSTALL_DIR/bin/python3" -c "import sysconfig; p=sysconfig.get_platform(); print(p.replace('-', '_').replace(' ', '_').replace('.', '_'))")
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/_sysconfigdata__linux_.py \
   "$INSTALL_DIR/lib/python3.12/_sysconfigdata__${PLATFORM_NAME}.py"

# Step 9: Install pip
if [ "$SKIP_PIP" = false ]; then
    echo "[9/9] Installing pip..."
    curl -fL https://bootstrap.pypa.io/get-pip.py -o "$TMPDIR/get-pip.py"
    "$INSTALL_DIR/bin/python3" "$TMPDIR/get-pip.py"

    # Configure pip mirror
    mkdir -p "$HOME/.pip"
    echo '[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple' > "$HOME/.pip/pip.conf"
else
    echo "[9/9] Skipping pip (--skip-pip)"
fi

echo ""
echo "========================================"
echo "Python installation completed!"
echo "========================================"
echo ""
echo "Binary: $INSTALL_DIR/bin/python3"
echo "Library: $INSTALL_DIR/lib/python3.12"
echo ""
echo "Verification:"
echo "  python3 --version"
echo "  python3 -c 'import pickle; print(pickle.dumps([1,2,3]))'"
echo "  python3 -m pip --version"
echo ""