#!/usr/bin/sh
# Rust 1.95.0 Installation Script for HarmonyOS
# Downloads and installs Rust toolchain with official ohos target
#
# Usage: ./install.sh [--download-only] [--skip-sign]
#
# Options:
#   --download-only  Only download components, don't install
#   --skip-sign      Skip code signing (dangerous, binaries won't run)

set -e

# Configuration
RUST_VERSION="1.95.0"
INSTALL_DIR="$HOME/.rust"
BUILD_DIR="$HOME/Claude/rust-build/rust-dist"
TMPDIR="$HOME/Claude/tmpdir"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

# Parse arguments
DOWNLOAD_ONLY=false
SKIP_SIGN=false

for arg in "$@"; do
    case $arg in
        --download-only) DOWNLOAD_ONLY=true ;;
        --skip-sign) SKIP_SIGN=true ;;
    esac
done

echo "========================================"
echo "Rust $RUST_VERSION Installation on HarmonyOS"
echo "========================================"
echo ""

# Step 1: Get current version date from channel
echo "[1/6] Checking Rust channel for version $RUST_VERSION..."
CHANNEL_URL="https://static.rust-lang.org/dist/channel-rust-stable.toml"

# Default date (update this based on channel)
RUST_DATE="2026-04-16"
BASE_URL="https://static.rust-lang.org/dist/$RUST_DATE"

# Step 2: Create directories
echo "[2/6] Creating directories..."
mkdir -p "$BUILD_DIR"
mkdir -p "$TMPDIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"

# Step 3: Download components
cd "$BUILD_DIR"

if [ ! -f "rustc.tar.gz" ]; then
    echo "[3/6] Downloading rustc (ohos version)..."
    curl -L "$BASE_URL/rustc-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz" -o rustc.tar.gz || {
        echo "Download failed! Try updating RUST_DATE in script."
        exit 1
    }
else
    echo "[3/6] rustc already downloaded, skipping..."
fi

if [ ! -f "rust-std.tar.gz" ]; then
    echo "[3/6] Downloading rust-std (ohos version)..."
    curl -L "$BASE_URL/rust-std-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz" -o rust-std.tar.gz
else
    echo "[3/6] rust-std already downloaded, skipping..."
fi

if [ ! -f "cargo.tar.gz" ]; then
    echo "[3/6] Downloading cargo (MUSL version - IMPORTANT)..."
    # NOTE: Use musl version, not ohos version!
    curl -L "$BASE_URL/cargo-$RUST_VERSION-aarch64-unknown-linux-musl.tar.gz" -o cargo.tar.gz
else
    echo "[3/6] cargo already downloaded, skipping..."
fi

if [ "$DOWNLOAD_ONLY" = true ]; then
    echo "Download complete (--download-only)"
    exit 0
fi

# Step 4: Extract and install
echo "[4/6] Extracting components..."
tar xzf rustc.tar.gz
tar xzf rust-std.tar.gz
tar xzf cargo.tar.gz

echo "[4/6] Installing components..."
./rustc-$RUST_VERSION-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./rust-std-$RUST_VERSION-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./cargo-$RUST_VERSION-aarch64-unknown-linux-musl/install.sh --prefix="$INSTALL_DIR" --destdir=""

# Step 5: Code signing
if [ "$SKIP_SIGN" = false ]; then
    echo "[5/6] Signing all ELF binaries..."

    # Sign rustc
    $SIGN_TOOL sign -selfSign 1 \
        -inFile "$INSTALL_DIR/bin/rustc" \
        -outFile "$INSTALL_DIR/bin/rustc.signed" \
        -signAlg SHA256withECDSA
    mv "$INSTALL_DIR/bin/rustc.signed" "$INSTALL_DIR/bin/rustc"
    chmod +x "$INSTALL_DIR/bin/rustc"

    # Sign cargo
    $SIGN_TOOL sign -selfSign 1 \
        -inFile "$INSTALL_DIR/bin/cargo" \
        -outFile "$INSTALL_DIR/bin/cargo.signed" \
        -signAlg SHA256withECDSA
    mv "$INSTALL_DIR/bin/cargo.signed" "$INSTALL_DIR/bin/cargo"
    chmod +x "$INSTALL_DIR/bin/cargo"

    # Sign all .so files
    for f in "$INSTALL_DIR/lib"/*.so; do
        if [ -f "$f" ]; then
            $SIGN_TOOL sign -selfSign 1 \
                -inFile "$f" \
                -outFile "${f}.signed" \
                -signAlg SHA256withECDSA
            mv "${f}.signed" "$f"
        fi
    done

    # Sign rustlib binaries
    RUSTLIB_BIN="$INSTALL_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin"
    if [ -d "$RUSTLIB_BIN" ]; then
        for f in "$RUSTLIB_BIN"/*; do
            if [ -f "$f" ] && file "$f" | grep -q ELF; then
                $SIGN_TOOL sign -selfSign 1 \
                    -inFile "$f" \
                    -outFile "${f}.signed" \
                    -signAlg SHA256withECDSA
                mv "${f}.signed" "$f"
            fi
        done
    fi

    # Extract and sign libgcc_s.so.1
    echo "[5/6] Extracting libgcc_s.so.1..."
    LIBGCC_SRC="/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/cryptography.libs/libgcc_s-c8ae3477.so.1"
    if [ -f "$LIBGCC_SRC" ]; then
        cp "$LIBGCC_SRC" "$INSTALL_DIR/lib/libgcc_s.so.1"
        $SIGN_TOOL sign -selfSign 1 \
            -inFile "$INSTALL_DIR/lib/libgcc_s.so.1" \
            -outFile "$INSTALL_DIR/lib/libgcc_s.so.1.signed" \
            -signAlg SHA256withECDSA
        mv "$INSTALL_DIR/lib/libgcc_s.so.1.signed" "$INSTALL_DIR/lib/libgcc_s.so.1"
    else
        echo "WARNING: libgcc_s.so.1 source not found, cargo may not work"
    fi
else
    echo "[5/6] Skipping signing (--skip-sign)"
fi

# Step 6: Configure linker and environment
echo "[6/6] Configuring cargo..."
mkdir -p "$INSTALL_DIR/.cargo"

cat > "$INSTALL_DIR/.cargo/config.toml" << 'EOF'
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
EOF

# Download SSL certificates
echo "[6/6] Downloading SSL certificates for cargo..."
curl -L https://curl.se/ca/cacert.pem -o "$INSTALL_DIR/cacert.pem" || {
    echo "WARNING: SSL cert download failed, cargo may not access crates.io"
}

echo ""
echo "========================================"
echo "Rust installation completed!"
echo "========================================"
echo ""
echo "Binary: $INSTALL_DIR/bin/rustc"
echo "Cargo:  $INSTALL_DIR/bin/cargo"
echo ""
echo "Add to ~/.zshenv:"
echo "  export RUST_HOME=\"$INSTALL_DIR\""
echo "  export PATH=\"$RUST_HOME/bin:$PATH\""
echo "  export LD_LIBRARY_PATH=\"/usr/lib:$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH\""
echo "  export CARGO_HOME=\"$RUST_HOME\""
echo "  export RUSTUP_HOME=\"$RUST_HOME\""
echo "  export SSL_CERT_FILE=\"$RUST_HOME/cacert.pem\""
echo ""
echo "Verification:"
echo "  rustc --version"
echo "  cargo --version"
echo ""