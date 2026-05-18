#!/usr/bin/sh
# Go 1.22.5 Installation Script for HarmonyOS
# Downloads prebuilt Go toolchain and signs all binaries
#
# Usage: ./install.sh

set -e

GO_VERSION="1.22.5"
INSTALL_DIR="$HOME/Claude/go-build/go"
TMPDIR="$HOME/Claude/tmpdir"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

echo "========================================"
echo "Go $GO_VERSION Installation on HarmonyOS"
echo "========================================"
echo ""

# Create directories
echo "[1/4] Creating directories..."
mkdir -p "$HOME/Claude/go-build"
mkdir -p "$TMPDIR"

# Download Go
cd "$HOME/Claude/go-build"

if [ ! -f "go${GO_VERSION}.linux-arm64.tar.gz" ]; then
    echo "[2/4] Downloading Go..."
    curl -L "https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz" -o "go${GO_VERSION}.linux-arm64.tar.gz"
else
    echo "[2/4] Go already downloaded, skipping..."
fi

# Extract
echo "[2/4] Extracting..."
if [ ! -d "go" ]; then
    tar xzf "go${GO_VERSION}.linux-arm64.tar.gz"
fi

# Sign all binaries
echo "[3/4] Signing Go toolchain..."

# Sign go binary
$SIGN_TOOL sign -selfSign 1 \
    -inFile "$INSTALL_DIR/bin/go" \
    -outFile "$INSTALL_DIR/bin/go.signed" \
    -signAlg SHA256withECDSA
mv "$INSTALL_DIR/bin/go.signed" "$INSTALL_DIR/bin/go"
chmod +x "$INSTALL_DIR/bin/go"

# Sign gofmt
$SIGN_TOOL sign -selfSign 1 \
    -inFile "$INSTALL_DIR/bin/gofmt" \
    -outFile "$INSTALL_DIR/bin/gofmt.signed" \
    -signAlg SHA256withECDSA
mv "$INSTALL_DIR/bin/gofmt.signed" "$INSTALL_DIR/bin/gofmt"
chmod +x "$INSTALL_DIR/bin/gofmt"

# Sign all build tools
for f in "$INSTALL_DIR/pkg/tool/linux_arm64"/*; do
    if [ -f "$f" ] && file "$f" | grep -q ELF; then
        $SIGN_TOOL sign -selfSign 1 \
            -inFile "$f" \
            -outFile "${f}.signed" \
            -signAlg SHA256withECDSA
        mv "${f}.signed" "$f"
        chmod +x "$f"
    fi
done

# Configure environment
echo "[4/4] Configuring shell environment..."
echo "Add to ~/.zshenv:"
echo "  export GO_HOME=\"$INSTALL_DIR\""
echo "  export PATH=\"$GO_HOME/bin:$PATH\""
echo "  export GOPATH=\"$HOME/Claude/go-build/gopath\""
echo "  export GOPROXY=\"https://goproxy.cn,direct\""
echo "  export TMPDIR=\"$HOME/Claude/tmpdir\""

echo ""
echo "========================================"
echo "Go installation completed!"
echo "========================================"
echo ""
echo "Verification:"
echo "  $INSTALL_DIR/bin/go version"
echo ""