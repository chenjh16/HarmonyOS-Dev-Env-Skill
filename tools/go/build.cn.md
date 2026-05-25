# Go 1.22.5 on HarmonyOS (aarch64) - 构建指南

> **英文版本见 build.md**

## 概述

Go 在 HarmonyOS 上需要下载官方 Linux ARM64 二进制包并签名所有 ELF 二进制文件。无需从源码编译——Go 提供了可在 musl 系统上运行的预编译二进制包。

**关键挑战**: HarmonyOS 上所有 ELF 二进制文件执行前必须代码签名。这包括 Go 编译器本身、`gofmt` 和 `pkg/tool/linux_arm64/` 中的所有构建工具。

## 前置条件

- HarmonyOS SDK（含 binary-sign-tool）
- 网络访问（或代理）用于下载 Go 二进制包
- `$HOME/Claude/tmpdir` 作为可写临时目录（`/tmp` 只读）

## 构建步骤

### 1. 下载 Go 二进制包

```bash
mkdir -p $HOME/Claude/go-build
cd $HOME/Claude/go-build
curl -L "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz" -o "go1.22.5.linux-arm64.tar.gz"
```

如果直接访问 `go.dev` 失败（国内常见），使用代理：

```bash
curl -L --proxy http://127.0.0.1:7890 \
  "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz" -o "go1.22.5.linux-arm64.tar.gz"
```

### 2. 解压

```bash
cd $HOME/Claude/go-build
tar xzf go1.22.5.linux-arm64.tar.gz
```

这会创建 `go/` 目录，包含完整的工具链。

### 3. 签名所有二进制文件

**关键**: Go 工具链中的每个 ELF 二进制文件都必须签名。包括：

- `go/bin/go` — 编译器
- `go/bin/gofmt` — 格式化工具
- `go/pkg/tool/linux_arm64/*` — 所有构建工具（compile、link、asm 等）

```bash
INSTALL_DIR="$HOME/Claude/go-build/go"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

# 签名 go 二进制
$SIGN_TOOL sign -selfSign 1 \
  -inFile "$INSTALL_DIR/bin/go" \
  -outFile "$INSTALL_DIR/bin/go.signed" \
  -signAlg SHA256withECDSA
mv "$INSTALL_DIR/bin/go.signed" "$INSTALL_DIR/bin/go"
chmod +x "$INSTALL_DIR/bin/go"

# 签名 gofmt
$SIGN_TOOL sign -selfSign 1 \
  -inFile "$INSTALL_DIR/bin/gofmt" \
  -outFile "$INSTALL_DIR/bin/gofmt.signed" \
  -signAlg SHA256withECDSA
mv "$INSTALL_DIR/bin/gofmt.signed" "$INSTALL_DIR/bin/gofmt"
chmod +x "$INSTALL_DIR/bin/gofmt"

# 签名所有构建工具
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

### 4. 配置 Shell 环境

添加到 `~/.zshenv`：

```bash
export GO_HOME="$HOME/Claude/go-build/go"
export PATH="$GO_HOME/bin:$PATH"
export GOPATH="$HOME/Claude/go-build/gopath"
export GOMODCACHE="$HOME/Claude/go-build/gomodcache"
export GOPROXY="https://goproxy.cn,direct"
export TMPDIR="$HOME/Claude/tmpdir"
```

**关键设置**:
- `GOPROXY=https://goproxy.cn,direct` — 国内 Go 模块镜像，失败时直连
- `TMPDIR=$HOME/Claude/tmpdir` — HarmonyOS 上 `/tmp` 只读
- `GOMODCACHE` 和 `GOPATH` — 将 Go 模块缓存与系统路径隔离

### 5. 验证

```bash
source ~/.zshenv
go version
# 期望输出: go version go1.22.5 linux/arm64

go env GOPROXY
# 期望输出: https://goproxy.cn,direct
```

## 使用 Go 构建项目

### mihomo (Clash Meta)

Go 在 HarmonyOS 上主要用于构建 mihomo（Clash Meta 代理）。完整构建指南见 `tools/mihomo/build.cn.md`。

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

**重要**: 所有 Go 编译的二进制文件也必须代码签名后才能执行。

## 已知问题

### /tmp 只读

Go 构建系统使用临时文件。HarmonyOS 上 `/tmp` 只读。必须设置 `TMPDIR=$HOME/Claude/tmpdir`。

### 代码签名要求

Go 工具链二进制和任何 Go 编译的二进制都必须签名。签名过程需要在解压后（工具链）和编译后（用户项目）分别执行。

### GitHub 直连可能失败

某些环境屏蔽 GitHub 直连。`GOPROXY` 处理模块下载，但 `git clone` 可能需要 `gh-proxy.com` 代理。

## Checklist

1. **下载**: 直接访问失败时使用代理
2. **解压**: `tar xzf` 创建完整工具链
3. **签名**: 所有 ELF 二进制（go、gofmt、pkg/tool/linux_arm64/*）
4. **环境**: GOPROXY、TMPDIR、GOPATH 写入 ~/.zshenv
5. **验证**: `go version` 确认安装
6. **用户构建**: 所有编译的二进制也必须签名