# HarmonyOS PC 开发环境配置技能包

> **English version follows below**

本项目汇集了在 HarmonyOS (鸿蒙) PC 上搭建完整开发环境的所有经验和技能，包括工具链配置、代码签名、常见问题解决方案等。每个工具都有从源码获取到编译安装的完整流程。

## 项目概述

HarmonyOS PC (HongMeng Kernel 1.12.0, aarch64) 是一个独特的开发平台，与传统 Linux 系统有显著差异。本项目记录了完整的适配过程，帮助开发者快速搭建开发环境。

### 平台特性

- **内核**: HongMeng Kernel 1.12.0 (基于 musl libc)
- **架构**: aarch64 (ARM64)
- **编译器**: Clang 15.0.4 (无 gcc)
- **动态链接器**: `/lib/ld-musl-aarch64.so.1`
- **代码签名**: 所有 ELF 二进制必须签名才能执行

### 已适配的工具链

| 工具链 | 版本 | 状态 | 安装脚本 |
|--------|------|------|----------|
| Python | 3.12.8 | 完全可用 | `tools/python/install.sh` |
| Rust | 1.95.0 | 完全可用 | `tools/rust/install.sh` |
| Go | 1.22.5 | 完全可用 | `tools/go/install.sh` |
| PyTorch | 2.5.1 | 完全可用 | 见 `tools/pytorch/build.md` |
| llama.cpp | b9073 | 完全可用 | `tools/llama-cpp/install.sh` |
| mihomo | Meta | 完全可用 | `tools/mihomo/install.sh` |
| eza | 0.23.4 | 完全可用 | 见 `tools/eza/build.md` |
| bat | 0.26.1 | 完全可用 | 见 `tools/bat/build.md` |
| starship | 1.25.1 | 完全可用 | 见 `tools/starship/build.md` |

## 目录结构

```
HarmonyOS-Dev-Env-Skill/
├── README.md                 # 本文件 (双语)
├── skill.json                # Skill 定义文件
├── CLAUDE.md                 # Claude Code 规则文件 (英文)
├── CLAUDE.cn.md              # Claude Code 规则文件 (中文)
├── config/
│   └── .zshenv               # Shell 环境配置模板
│   └── pip.conf              # pip 配置模板
├── scripts/
│   └── sign-all.sh           # 批量签名脚本
└── tools/                    # 各工具的构建指南和安装脚本
    ├── python/
    │   ├── build.md          # 完整构建指南
    │   └── install.sh        # 一键安装脚本
    ├── rust/
    │   ├── build.md
    │   └── install.sh
    ├── go/
    │   ├── build.md
    │   └── install.sh
    ├── pytorch/
    │   └── build.md          # PyTorch 编译详解
    ├── llama-cpp/
    │   ├── build.md
    │   └── install.sh
    ├── mihomo/
    │   ├── build.md
    │   └── install.sh
    └── ...                   # 其他工具
```

## 快速开始

### 1. 安装 Claude Code 规则文件

将 `CLAUDE.md` 和 `CLAUDE.cn.md` 复制到 `~/.claude/` 目录，让 Claude Code 了解 HarmonyOS 平台特性：

```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
cp CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
```

### 2. 配置 Shell 环境

将 `config/.zshenv` 复制到用户主目录：

```bash
cp config/.zshenv ~/.zshenv
source ~/.zshenv
```

### 3. 安装工具链

每个工具都有完整的安装脚本：

```bash
# Python (带 pip 和扩展模块支持)
./tools/python/install.sh

# Rust (官方 ohos 目标)
./tools/rust/install.sh

# Go
./tools/go/install.sh

# llama.cpp (带 NEON/SVE 优化)
./tools/llama-cpp/install.sh

# mihomo (Clash Meta 代理)
./tools/mihomo/install.sh
```

## 核心问题与解决方案

### 代码签名 (最重要)

所有 ELF 二进制文件 (可执行程序、.so 动态库) 都必须签名才能执行：

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

批量签名：`./scripts/sign-all.sh <directory>`

### /tmp 只读问题

HarmonyOS 的 `/tmp` 目录是只读的：

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

### 动态库搜索路径

**关键**: `/usr/lib` 必须在 `$HOME/.rust/lib` 前面，否则 OpenSSL 符号版本冲突：

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

### 无 gcc 问题

HarmonyOS 只有 clang：

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

## Python 编译要点

Python 必须用 `-rdynamic` 编译才能加载扩展模块：

| Python Build | 导出 Py 符号数 | 扩展模块加载 |
|--------------|----------------|--------------|
| 系统 Python (静态) | 0 | Permission denied |
| 本地 Python (-rdynamic) | 948+ | SUCCESS |

完整流程见 `tools/python/build.md`。

## 工具链详细文档

| 工具 | 文档 | 主要特性 |
|------|------|----------|
| Python | `docs/python-harmonyos.md` | pip、numpy、扩展模块、pillow、lxml |
| Python Packages | `docs/python-packages-harmonyos.md` | 34个包兼容性报告 |
| Rust | `docs/rust-harmonyos.md` | 官方 ohos 目标、cargo、FFI |
| Go | `tools/go/build.md` | GOPROXY 支持 |
| PyTorch | `docs/pytorch-harmonyos.md` | MNIST 训练验证 (92.4%) |
| llama.cpp | `docs/llama-cpp-harmonyos.md` | NEON/SVE 优化、4x 加速 |
| mihomo | `docs/mihomo-harmonyos.md` | HTTP/SOCKS5 代理、GEOIP/GEOSITE 智能分流 |
| eza | `docs/eza-harmonyos.md` | 现代 ls、图标、Git 状态 |
| bat | `docs/bat-harmonyos.md` | 语法高亮、cat 替代 |
| starship | `docs/starship-harmonyos.md` | 跨 shell 提示符 |
| Dropbear | `tools/dropbear/build.md` | SSH 服务器、公钥认证、V8 crash 解决方案 |

## 核心问题文档

| 问题 | 文档 | 说明 |
|------|------|------|
| 代码签名 | `docs/code-signing.md` | 所有 ELF 必须签名 |
| LD_LIBRARY_PATH | `docs/ld-library-path.md` | /usr/lib 必须在最前面 |
| 链接器封装 | `CLAUDE.md` | SDK lld 不工作，用 ld.bfd |

---

# HarmonyOS PC Development Environment Skill Pack

> **中文版本见上方**

This project collects all experiences and skills for setting up a complete development environment on HarmonyOS PC. Each tool has a complete workflow from source acquisition to compilation and installation.

## Project Overview

HarmonyOS PC (HongMeng Kernel 1.12.0, aarch64) is a unique development platform with significant differences from traditional Linux systems.

### Platform Characteristics

- **Kernel**: HongMeng Kernel 1.12.0 (based on musl libc)
- **Architecture**: aarch64 (ARM64)
- **Compiler**: Clang 15.0.4 (no gcc)
- **Dynamic linker**: `/lib/ld-musl-aarch64.so.1`
- **Code signing**: All ELF binaries must be signed before execution

### Adapted Toolchains

| Toolchain | Version | Status | Install Script |
|-----------|---------|--------|----------------|
| Python | 3.12.8 | Fully functional | `tools/python/install.sh` |
| Rust | 1.95.0 | Fully functional | `tools/rust/install.sh` |
| Go | 1.22.5 | Fully functional | `tools/go/install.sh` |
| PyTorch | 2.5.1 | Fully functional | See `tools/pytorch/build.md` |
| llama.cpp | b9073 | Fully functional | `tools/llama-cpp/install.sh` |
| mihomo | Meta | Fully functional | `tools/mihomo/install.sh` |
| eza | 0.23.4 | Fully functional | See `tools/eza/build.md` |
| bat | 0.26.1 | Fully functional | See `tools/bat/build.md` |
| starship | 1.25.1 | Fully functional | See `tools/starship/build.md` |

## Directory Structure

```
HarmonyOS-Dev-Env-Skill/
├── README.md                 # This file (bilingual)
├── skill.json                # Skill definition file
├── CLAUDE.md                 # Claude Code rules (English)
├── CLAUDE.cn.md              # Claude Code rules (Chinese)
├── config/
│   └── .zshenv               # Shell config template
│   └── pip.conf              # pip config template
├── scripts/
│   └── sign-all.sh           # Batch signing script
└── tools/                    # Build guides and install scripts
    ├── python/
    │   ├── build.md          # Complete build guide
    │   └ install.sh          # One-click install script
    ├── rust/
    │   ├── build.md
    │   └ install.sh
    ├── go/
    │   ├── build.md
    │   └ install.sh
    ├── pytorch/
    │   └ build.md            # PyTorch compilation details
    ├── llama-cpp/
    │   ├── build.md
    │   └ install.sh
    ├── mihomo/
    │   ├── build.md
    │   └ install.sh
    └── ...                   # Other tools
```

## Quick Start

### 1. Install Claude Code Rules Files

Copy rules files to `~/.claude/`:

```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
cp CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
```

### 2. Configure Shell Environment

Copy shell config:

```bash
cp config/.zshenv ~/.zshenv
source ~/.zshenv
```

### 3. Install Toolchains

Each tool has a complete install script:

```bash
# Python (with pip and extension module support)
./tools/python/install.sh

# Rust (official ohos target)
./tools/rust/install.sh

# Go
./tools/go/install.sh

# llama.cpp (with NEON/SVE optimization)
./tools/llama-cpp/install.sh

# mihomo (Clash Meta proxy)
./tools/mihomo/install.sh
```

## Core Issues

### Code Signing (Most Critical)

All ELF binaries must be signed:

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

Batch signing: `./scripts/sign-all.sh <directory>`

### /tmp Read-Only

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

### LD_LIBRARY_PATH Order

**Critical**: `/usr/lib` must come before `$HOME/.rust/lib`:

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

### No gcc

Only clang available:

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

## Python Compilation

Python must be compiled with `-rdynamic` for extension module support:

| Python Build | Py Symbols Exported | Extension Loading |
|--------------|---------------------|-------------------|
| System Python (static) | 0 | Permission denied |
| Local Python (-rdynamic) | 1521 | SUCCESS |

See `docs/python-harmonyos.md` for complete workflow.

## Documentation Index

| Document | Description |
|----------|-------------|
| `docs/python-harmonyos.md` | Python environment setup |
| `docs/python-packages-harmonyos.md` | 34 packages compatibility |
| `docs/rust-harmonyos.md` | Rust toolchain installation |
| `docs/pytorch-harmonyos.md` | PyTorch v2.5.1 compilation |
| `docs/llama-cpp-harmonyos.md` | llama.cpp with NEON/SVE |
| `docs/mihomo-harmonyos.md` | Proxy client setup |
| `docs/eza-harmonyos.md` | Modern ls replacement |
| `docs/bat-harmonyos.md` | cat with syntax highlighting |
| `docs/starship-harmonyos.md` | Cross-shell prompt |
| `docs/code-signing.md` | Code signing guide |
| `docs/ld-library-path.md` | Library path configuration |

## License

MIT License

## Contributing

Issues and Pull Requests welcome at [GitHub](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill).

---

**Tested on**: HarmonyOS HongMeng Kernel 1.12.0, aarch64
**Generated**: 2026-05-18