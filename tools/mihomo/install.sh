#!/usr/bin/sh
# mihomo (Clash Meta) Build Script for HarmonyOS
# Builds mihomo proxy from source using Go
#
# Usage: ./install.sh

set -e

INSTALL_DIR="$HOME/Claude/mihomo-build"
CONFIG_DIR="$HOME/Claude/mihomo-config"
TMPDIR="$HOME/Claude/tmpdir"
GO_BIN="$HOME/Claude/go-build/go/bin/go"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

echo "========================================"
echo "mihomo (Clash Meta) Build on HarmonyOS"
echo "========================================"
echo ""

# Check Go installation
if [ ! -f "$GO_BIN" ]; then
    echo "ERROR: Go not found at $GO_BIN"
    echo "Please install Go first using tools/go/install.sh"
    exit 1
fi

# Create directories
echo "[1/4] Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$TMPDIR"

# Clone repository
echo "[1/4] Cloning mihomo (Meta branch)..."
cd "$INSTALL_DIR"

if [ ! -d ".git" ]; then
    git clone https://github.com/MetaCubeX/mihomo.git . || {
        echo "Clone failed, trying proxy..."
        git clone https://gh-proxy.com/https://github.com/MetaCubeX/mihomo.git .
    }
    git checkout Meta
else
    echo "Repository already exists..."
fi

# Configure Go environment
export PATH="$HOME/Claude/go-build/go/bin:$PATH"
export GOPATH="$HOME/Claude/go-build/gopath"
export GOMODCACHE="$HOME/Claude/go-build/gomodcache"
export GOPROXY="https://goproxy.cn,direct"
export TMPDIR="$TMPDIR"

# Download dependencies
echo "[2/4] Downloading dependencies..."
go mod download

# Build
echo "[3/4] Building mihomo..."
mkdir -p "$INSTALL_DIR/bin"

GOARCH=arm64 GOOS=linux CGO_ENABLED=0 go build \
    -tags with_gvisor -trimpath \
    -ldflags '-X "github.com/metacubex/mihomo/constant.Version=local-$(date +%Y%m%d)" -w -s -buildid=' \
    -o "$INSTALL_DIR/bin/mihomo-linux-arm64" .

# Sign
echo "[4/4] Signing mihomo..."
$SIGN_TOOL sign -selfSign 1 \
    -inFile "$INSTALL_DIR/bin/mihomo-linux-arm64" \
    -outFile "$INSTALL_DIR/bin/mihomo-linux-arm64.signed" \
    -signAlg SHA256withECDSA
mv "$INSTALL_DIR/bin/mihomo-linux-arm64.signed" "$INSTALL_DIR/bin/mihomo-linux-arm64"
chmod +x "$INSTALL_DIR/bin/mihomo-linux-arm64"

# Verify build
echo ""
$INSTALL_DIR/bin/mihomo-linux-arm64 -v

# Create minimal config
if [ ! -f "$CONFIG_DIR/minimal.yaml" ]; then
    echo "[4/4] Creating minimal config..."
    cat > "$CONFIG_DIR/minimal.yaml" << 'EOF'
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090

dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:1053
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query

proxies:
  - name: "DIRECT"
    type: direct

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,PROXY
EOF
fi

echo ""
echo "========================================"
echo "mihomo build completed!"
echo "========================================"
echo ""
echo "Binary: $INSTALL_DIR/bin/mihomo-linux-arm64"
echo "Config: $CONFIG_DIR/minimal.yaml"
echo ""
echo "Start command:"
echo "  cd $CONFIG_DIR"
echo "  $INSTALL_DIR/bin/mihomo-linux-arm64 -d . -f minimal.yaml"
echo ""