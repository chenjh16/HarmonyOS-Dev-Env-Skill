#!/usr/bin/sh
# llama.cpp Build Script for HarmonyOS
# Builds llama.cpp with NEON/SVE optimization
#
# Usage: ./install.sh [--no-optimize]

set -e

INSTALL_DIR="$HOME/Claude/llama.cpp"
BUILD_DIR="$HOME/Claude/llama.cpp/build"
TMPDIR="$HOME/Claude/tmpdir"
CLANG="/data/service/hnp/bin/clang"
CMAKE="/data/service/hnp/bin/cmake"
NINJA="/data/service/hnp/bin/ninja"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
LINKER_WRAPPER_DIR="$HOME/Claude/lib/linker_wrapper"

NO_OPTIMIZE=false
for arg in "$@"; do
    case $arg in
        --no-optimize) NO_OPTIMIZE=true ;;
    esac
done

echo "========================================"
echo "llama.cpp Build on HarmonyOS"
echo "========================================"
echo ""

# Clone repository
echo "[1/5] Cloning llama.cpp..."
mkdir -p "$HOME/Claude"

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

if [ ! -d "$INSTALL_DIR" ]; then
    cd "$HOME/Claude"
    # Use GitHub proxy for China
    git clone https://gh-proxy.com/https://github.com/ggml-org/llama.cpp.git || {
        echo "Clone failed, trying direct..."
        git clone https://github.com/ggml-org/llama.cpp.git
    }
else
    echo "Repository already exists, skipping clone..."
fi

cd "$INSTALL_DIR"

# Check for empty files (HarmonyOS filesystem issue)
if [ ! -s "src/unicode-data.cpp" ]; then
    echo "[1/5] Recovering empty files..."
    git show HEAD:src/unicode-data.cpp > "$TMPDIR/unicode-data.cpp"
    cp "$TMPDIR/unicode-data.cpp" src/unicode-data.cpp
fi

# Patch CMake for architecture detection
echo "[2/5] Patching CMake for HarmonyOS..."
if [ -f "ggml/cmake/common.cmake" ]; then
    # Check if patch already applied
    if ! grep -q "COMPILER_TARGET" "ggml/cmake/common.cmake"; then
        # Create patch file
        cat > "$TMPDIR/cmake_patch.txt" << 'PATCH_EOF'
if (NOT CMAKE_SYSTEM_PROCESSOR OR CMAKE_SYSTEM_PROCESSOR STREQUAL "unknown")
    execute_process(
        COMMAND ${CMAKE_C_COMPILER} -dumpmachine
        OUTPUT_VARIABLE COMPILER_TARGET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if (COMPILER_TARGET MATCHES "aarch64|arm")
        set(CMAKE_SYSTEM_PROCESSOR "aarch64")
    elseif (COMPILER_TARGET MATCHES "x86_64|i686|amd64")
        set(CMAKE_SYSTEM_PROCESSOR "x86_64")
    endif()
endif()
PATCH_EOF
        # Insert after function declaration line
        sed -i '/function(ggml_get_system_arch)/r $TMPDIR/cmake_patch.txt' "ggml/cmake/common.cmake"
        echo "CMake patched successfully"
    else
        echo "CMake patch already applied, skipping..."
    fi
fi

# Build
echo "[3/5] Building llama.cpp..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ "$NO_OPTIMIZE" = true ]; then
    $CMAKE -S "$INSTALL_DIR" -B "$BUILD_DIR" \
        -GNinja \
        -DCMAKE_C_COMPILER=$CLANG \
        -DCMAKE_CXX_COMPILER="${CLANG}++" \
        -DCMAKE_C_FLAGS="-B$LINKER_WRAPPER_DIR" \
        -DCMAKE_CXX_FLAGS="-B$LINKER_WRAPPER_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF \
        -DGGML_LLAMAFILE=OFF \
        -DGGML_BLAS=OFF \
        -DGGML_CUDA=OFF \
        -DGGML_METAL=OFF \
        -DGGML_VULKAN=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_SERVER=ON \
        -DBUILD_SHARED_LIBS=OFF
else
    $CMAKE -S "$INSTALL_DIR" -B "$BUILD_DIR" \
        -GNinja \
        -DCMAKE_C_COMPILER=$CLANG \
        -DCMAKE_CXX_COMPILER="${CLANG}++" \
        -DCMAKE_C_FLAGS="-B$LINKER_WRAPPER_DIR" \
        -DCMAKE_CXX_FLAGS="-B$LINKER_WRAPPER_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DGGML_LLAMAFILE=ON \
        -DGGML_BLAS=OFF \
        -DGGML_CUDA=OFF \
        -DGGML_METAL=OFF \
        -DGGML_VULKAN=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_SERVER=ON \
        -DBUILD_SHARED_LIBS=OFF
fi

$NINJA -C "$BUILD_DIR"

# Sign binaries
echo "[4/5] Signing binaries..."
mkdir -p "$BUILD_DIR/bin"

for f in "$BUILD_DIR/bin"/*; do
    if [ -f "$f" ] && file "$f" | grep -q ELF; then
        $SIGN_TOOL sign -selfSign 1 \
            -inFile "$f" \
            -outFile "${f}.signed" \
            -signAlg SHA256withECDSA
        mv "${f}.signed" "$f"
        chmod +x "$f"
    fi
done

# Set LD_LIBRARY_PATH for OpenMP
echo "[5/5] Configuring environment..."

echo ""
echo "========================================"
echo "llama.cpp build completed!"
echo "========================================"
echo ""
echo "Binaries: $BUILD_DIR/bin/"
echo ""
echo "Add to ~/.zshenv:"
echo "  export LLAMA_HOME=\"$BUILD_DIR/bin\""
echo "  export PATH=\"$LLAMA_HOME:$PATH\""
echo "  export LD_LIBRARY_PATH=\"$HOME/Claude/llama.cpp/build/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos:$LD_LIBRARY_PATH\""
echo ""
echo "Verification:"
echo "  llama-cli --version"
echo ""