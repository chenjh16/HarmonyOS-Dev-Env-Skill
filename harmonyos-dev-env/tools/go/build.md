# Go 1.22.5 on HarmonyOS (aarch64) - Build Guide

> **中文版本见 build.cn.md**

## Overview

Go on HarmonyOS requires downloading the official Linux ARM64 binary and signing all ELF binaries. No compilation from source is needed — Go provides prebuilt binaries that work on musl-based systems.

**Key Challenge**: All ELF binaries must be code-signed before execution on HarmonyOS. This includes the Go compiler itself, `gofmt`, and all build tools in `pkg/tool/linux_arm64/`.

## Prerequisites

- HarmonyOS SDK with binary-sign-tool
- Network access (or proxy) for downloading Go binary
- `$HOME/Claude/tmpdir` as writable temp directory (`/tmp` is read-only)

## Build Steps

### 1. Download Go Binary

```bash
mkdir -p $HOME/Claude/go-build
cd $HOME/Claude/go-build
curl -L "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz" -o "go1.22.5.linux-arm64.tar.gz"
```

If direct access to `go.dev` fails (common in China), use a proxy:

```bash
curl -L --proxy http://127.0.0.1:7890 \
  "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz" -o "go1.22.5.linux-arm64.tar.gz"
```

### 2. Extract

```bash
cd $HOME/Claude/go-build
tar xzf go1.22.5.linux-arm64.tar.gz
```

This creates the `go/` directory with the complete toolchain.

### 3. Sign All Binaries

**Critical**: Every ELF binary in the Go toolchain must be signed. This includes:

- `go/bin/go` — the compiler
- `go/bin/gofmt` — the formatter
- `go/pkg/tool/linux_arm64/*` — all build tools (compile, link, asm, etc.)

```bash
INSTALL_DIR="$HOME/Claude/go-build/go"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

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
```

### 4. Configure Shell Environment

Add to `~/.zshenv`:

```bash
export GO_HOME="$HOME/Claude/go-build/go"
export PATH="$GO_HOME/bin:$PATH"
export GOPATH="$HOME/Claude/go-build/gopath"
export GOMODCACHE="$HOME/Claude/go-build/gomodcache"
export GOPROXY="https://goproxy.cn,direct"
export TMPDIR="$HOME/Claude/tmpdir"
```

**Key settings**:
- `GOPROXY=https://goproxy.cn,direct` — China mirror for Go modules, falls back to direct
- `TMPDIR=$HOME/Claude/tmpdir` — `/tmp` is read-only on HarmonyOS
- `GOMODCACHE` and `GOPATH` — isolate Go module cache from system paths

### 5. Verify

```bash
source ~/.zshenv
go version
# Expected: go version go1.22.5 linux/arm64

go env GOPROXY
# Expected: https://goproxy.cn,direct
```

## Using Go to Build Projects

### mihomo (Clash Meta)

Go is primarily used on HarmonyOS to build mihomo (Clash Meta proxy). See `tools/mihomo/build.md` for the complete mihomo build guide.

```bash
export PATH=$HOME/Claude/go-build/go/bin:$PATH
export GOPATH=$HOME/Claude/go-build/gopath
export GOMODCACHE=$HOME/Claude/go-build/gomodcache
export GOPROXY=https://goproxy.cn,direct
export TMPDIR=$HOME/Claude/tmpdir

cd $HOME/Claude/mihomo-build
go mod download
GOARCH=arm64 GOOS=linux CGO_ENABLED=0 go build \
  -tags with_gvisor -trimpath \
  -ldflags '-X "github.com/metacubex/mihomo/constant.Version=local-YYYYMMDD" -w -s -buildid=' \
  -o bin/mihomo-linux-arm64 .
```

**Important**: All Go-compiled binaries must also be code-signed before execution.

## Known Issues

### /tmp Read-Only

Go's build system uses temporary files. On HarmonyOS, `/tmp` is read-only. Must set `TMPDIR=$HOME/Claude/tmpdir`.

### Code Signing Required

Both the Go toolchain binaries and any binaries compiled with Go must be signed. The signing process must be done after extraction (for the toolchain) and after compilation (for user projects).

### GitHub Direct Access May Fail

Some environments block direct GitHub access. Use proxy (`GOPROXY` handles module downloads, but `git clone` may need `gh-proxy.com`).

## Checklist

1. **Download**: Use proxy if direct access fails
2. **Extract**: `tar xzf` creates complete toolchain
3. **Sign**: All ELF binaries (go, gofmt, pkg/tool/linux_arm64/*)
4. **Environment**: GOPROXY, TMPDIR, GOPATH in ~/.zshenv
5. **Verify**: `go version` confirms installation
6. **User builds**: All compiled binaries must also be signed