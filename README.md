<div align="center">

# HarmonyOS PC Development Environment Skill Pack

**HarmonyOS (鸿蒙) PC 开发环境配置技能包**

[![GitHub](https://img.shields.io/badge/GitHub-chenjh16/HarmonyOS--Dev--Env--Skill-blue?logo=github)](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-HarmonyOS%20HongMeng%20Kernel-orange)](https://www.harmonyos.com)
[![Arch](https://img.shields.io/badge/Arch-aarch64-purple)](https://developer.huawei.com)
[![Tools](https://img.shields.io/badge/Tools-13%20Adapted-brightgreen)](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill%20Pack-8A2BE2)](https://claude.ai/code)

[🇨🇳 中文版](#中文版) ｜ [🇬🇧 English Version](#english-version)

</div>

---

<a id="中文版"></a>

# 🇨🇳 中文版

本项目是专为 **HarmonyOS (鸿蒙) PC** 设计的 Claude Code Skill Pack，让 AI Agent 在鸿蒙平台上也能获得完整的开发环境知识——包括平台特性、代码签名、工具链配置、常见问题解决方案等。

**为什么需要这个 Skill?** HarmonyOS PC 的开发环境与标准 Linux 差异巨大（代码签名、只读 /tmp、无 gcc、SDK lld 损坏等）。没有这些知识的 Agent 会反复踩坑、编译失败。安装本 Skill 后，Claude Code Agent 会自动获得所有鸿蒙适配经验，直接产出可用的构建方案。

## 📦 Skill 安装与使用

本 Skill 通过 Claude Code 的 `CLAUDE.md` 规则机制生效——安装后，Agent 在每次对话中都会自动加载这些鸿蒙平台知识。

### 方式一：全局安装（推荐）

适用于所有项目，Agent 在任何工作目录下都能获得鸿蒙知识：

```bash
# 克隆仓库
git clone https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git ~/Claude/HarmonyOS-Dev-Env-Skill

# 复制规则文件到 Claude Code 全局配置目录
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md

# 复制 SSH polyfill 和启动脚本（可选，SSH 场景必需）
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.claude/ssh-fetch-polyfill.js ~/.claude/ssh-fetch-polyfill.js
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.claude/start-claude.sh ~/.claude/start-claude.sh
```

### 方式二：项目级安装

仅对特定项目生效，不影响其他项目：

```bash
# 在项目根目录下创建 .claude/ 目录
mkdir -p <your-project>/.claude

# 复制规则文件
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.md <your-project>/.claude/CLAUDE.md
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.cn.md <your-project>/.claude/CLAUDE.cn.md
```

### 配置 Shell 环境

无论哪种安装方式，都需要配置 Shell 环境让工具链可用：

```bash
# 复制 zshenv 配置（包含所有 PATH/LD_LIBRARY_PATH/LD_PRELOAD 设置）
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.zshenv ~/.zshenv
source ~/.zshenv
```

### 验证安装

安装完成后，启动 Claude Code 并验证 Agent 是否加载了鸿蒙知识：

```
# 在 Claude Code 中提问，如果 Agent 知道以下信息则说明 Skill 已生效：
> "HarmonyOS 上编译 C 代码需要注意什么？"
# 预期回答应包含：代码签名、ld.bfd 封装、-B 参数、无 gcc 等

# 也可以运行验证脚本：
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/verify-env.sh
```

### Skill 工作原理

| 文件 | 作用 | 加载时机 |
|------|------|----------|
| `~/.claude/CLAUDE.md` | 全局规则（平台特性、工具链、核心问题） | 每次对话自动加载 |
| `~/.claude/CLAUDE.cn.md` | 中文版全局规则 | 与英文版并行加载 |
| `rules/CLAUDE.md` | 源规则文件（供复制到全局） | 不自动加载，需复制 |
| `config/.zshenv` | Shell PATH/LD 配置 | shell 启动时加载 |
| `config/.claude/start-claude.sh` | Claude Code 启动脚本（含 SSH 检测） | 手动启动或 SSH 环境 |
| `skill.json` | Skill 元数据（工具版本、文档路径） | 供 Agent 程序化查找 |
| `docs/*.md` | 详细适配指南 | Agent 需要时主动查阅 |

## 📋 平台特性

| 特性 | 说明 |
|------|------|
| 内核 | HongMeng Kernel 1.12.0 (基于 musl libc) |
| 架构 | aarch64 (ARM64) |
| 编译器 | Clang 15.0.4 (无 gcc) |
| 代码签名 | 所有 ELF 二进制必须签名才能执行 |
| /tmp | 只读，使用 `$HOME/Claude/tmpdir` 替代 |
| 动态链接器 | ld.bfd 封装（SDK lld 不工作） |

## 🔧 已适配工具链

| 工具链 | 版本 | 类别 | 状态 | 文档 |
|--------|------|------|:----:|------|
| Python | 3.12.8 | 语言 | ✅ | [docs/python-harmonyos.cn.md](docs/python-harmonyos.cn.md) |
| Node.js | 24.13.0 | 语言 | ✅ | [docs/nodejs-harmonyos.cn.md](docs/nodejs-harmonyos.cn.md) |
| Rust | 1.95.0 | 语言 | ✅ | [docs/rust-harmonyos.cn.md](docs/rust-harmonyos.cn.md) |
| Go | 1.22.5 | 语言 | ✅ | [tools/go/build.cn.md](tools/go/build.cn.md) |
| Claude Code | 2.1.88-ohos | AI工具 | ✅ | [docs/claude-code-harmonyos.cn.md](docs/claude-code-harmonyos.cn.md) |
| PyTorch | 2.5.1 | ML框架 | ✅ | [docs/pytorch-harmonyos.cn.md](docs/pytorch-harmonyos.cn.md) |
| llama.cpp | b9073 | ML推理 | ✅ | [docs/llama-cpp-harmonyos.cn.md](docs/llama-cpp-harmonyos.cn.md) |
| mihomo | Meta | 网络 | ✅ | [docs/mihomo-harmonyos.cn.md](docs/mihomo-harmonyos.cn.md) |
| Dropbear SSH | 2024.86 | 网络 | ✅ | [docs/dropbear-harmonyos.cn.md](docs/dropbear-harmonyos.cn.md) |
| OpenSSH | 9.9p1 | 网络 | ✅ | [docs/openssh-harmonyos.cn.md](docs/openssh-harmonyos.cn.md) |
| eza | 0.23.4 | 工具 | ✅ | [docs/eza-harmonyos.cn.md](docs/eza-harmonyos.cn.md) |
| bat | 0.26.1 | 工具 | ✅ | [docs/bat-harmonyos.cn.md](docs/bat-harmonyos.cn.md) |
| starship | 1.25.1 | 工具 | ✅ | [docs/starship-harmonyos.cn.md](docs/starship-harmonyos.cn.md) |

## ⚠️ 核心问题与解决方案

<details>
<summary><strong>代码签名</strong> (最重要 — 所有 ELF 二进制必须签名)</summary>

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned> -outFile <signed> -signAlg SHA256withECDSA
```

</details>

<details>
<summary><strong>/tmp 只读</strong> — 使用可写临时目录替代</summary>

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

</details>

<details>
<summary><strong>动态库搜索路径</strong> — /usr/lib 必须在最前面</summary>

**关键**: `/usr/lib` 必须在 `$HOME/.rust/lib` 前面，否则导致 OpenSSL 符号版本冲突：

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64
```

</details>

<details>
<summary><strong>无 gcc</strong> — 只有 clang 可用</summary>

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

</details>

<details>
<summary><strong>链接器封装</strong> — SDK lld 不工作</summary>

SDK 的 lld 需要 `libxml2.so.16`（不存在），必须用 ld.bfd 封装：

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
echo '#!/bin/sh' > $HOME/Claude/lib/linker_wrapper/ld.lld
echo 'exec /data/service/hnp/bin/ld.bfd "$@"' >> $HOME/Claude/lib/linker_wrapper/ld.lld
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
# 所有 clang 编译命令添加 -B$HOME/Claude/lib/linker_wrapper
```

</details>

<details>
<summary><strong>OpenSSH passwd_compat</strong> — uid 不在 /etc/passwd</summary>

sshd 需要 LD_PRELOAD 因为 uid 20020106 不在 /etc/passwd（只读）：

```bash
export LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so
```

ssh-agent 使用抽象命名空间 socket (`SSH_AUTH_SOCK=abstract:<name>`).

</details>

## 🔨 安装工具链

Skill 安装完成后，按需安装工具链（每个 install.sh 会自动处理代码签名）：

```bash
cd ~/Claude/HarmonyOS-Dev-Env-Skill

./tools/python/install.sh    # Python (pip + numpy + 扩展模块)
./tools/rust/install.sh      # Rust (官方 ohos 目标)
./tools/go/install.sh        # Go
./tools/llama-cpp/install.sh # llama.cpp (NEON/SVE 优化)
./tools/mihomo/install.sh    # mihomo (Clash Meta 代理)
./tools/dropbear/install.sh  # Dropbear SSH (需手动源码补丁)
# OpenSSH 需手动补丁+构建，见 tools/openssh/build.md
```

> **注意**: Dropbear 和 OpenSSH 需要手动编辑源码补丁（5 个 / 16 个），install.sh 会提示哪些文件需要修改。详见各工具的 `build.md` 构建指南。

## 📚 文档索引

**工具适配指南**

| 文档 | 说明 |
|------|------|
| [Claude Code 适配](docs/claude-code-harmonyos.cn.md) | AI 编程助手、npm 安装、SSH V8 修复 |
| [Node.js (DevNode-OH)](docs/nodejs-harmonyos.cn.md) | Node.js 安装、TLS/V8 问题 |
| [Python 环境](docs/python-harmonyos.cn.md) | Python 3.12.8、pip、numpy、扩展模块 |
| [Python 包兼容性](docs/python-packages-harmonyos.cn.md) | 34 个包测试报告 |
| [Rust 适配](docs/rust-harmonyos.cn.md) | Rust 1.95.0、cargo、FFI |
| [PyTorch 适配](docs/pytorch-harmonyos.cn.md) | PyTorch v2.5.1、15/15 测试、LAPACK |
| [llama.cpp 适配](docs/llama-cpp-harmonyos.cn.md) | NEON/SVE、Qwen3.5 模型 |
| [mihomo 适配](docs/mihomo-harmonyos.cn.md) | HTTP/SOCKS5、GEOIP/GEOSITE |
| [Dropbear SSH](docs/dropbear-harmonyos.cn.md) | SSH 服务器、5 个补丁、V8 crash 修复 |
| [OpenSSH 适配](docs/openssh-harmonyos.cn.md) | OpenSSH 9.9p1、16 个补丁、scp/sftp/ssh-agent |
| [eza 适配](docs/eza-harmonyos.cn.md) | 现代 ls、图标、Git 状态 |
| [bat 适配](docs/bat-harmonyos.cn.md) | 语法高亮 cat |
| [starship 适配](docs/starship-harmonyos.cn.md) | 跨 shell 提示符 |

**平台问题指南**

| 文档 | 说明 |
|------|------|
| [代码签名](docs/code-signing.cn.md) | ELF/HAP 签名指南 |
| [LD_LIBRARY_PATH](docs/ld-library-path.cn.md) | 动态库路径配置 |
| [SELinux 分析](docs/selinux-analysis.cn.md) | .so 加载限制根因 |
| [IPC 可行性](docs/ipc-feasibility.cn.md) | Native 子进程 API |
| [故障排除](docs/troubleshooting.cn.md) | 综合问题解决参考 |

---

<a id="english-version"></a>

# 🇬🇧 English Version

This project is a **Claude Code Skill Pack** designed specifically for HarmonyOS PC. It gives AI Agents complete knowledge of the HarmonyOS development environment — platform quirks, code signing, toolchain configuration, and solutions to common pitfalls.

**Why this Skill?** HarmonyOS PC differs drastically from standard Linux (code signing mandatory, read-only /tmp, no gcc, broken SDK lld, etc.). Without this knowledge, Agents will repeatedly fail at compilation tasks. After installing this Skill, Claude Code automatically carries all HarmonyOS adaptation experience and produces working build solutions directly.

## 📦 Skill Installation & Usage

This Skill works through Claude Code's `CLAUDE.md` rules mechanism — once installed, the Agent automatically loads HarmonyOS platform knowledge in every conversation.

### Option A: Global Install (Recommended)

Applies to all projects. The Agent gets HarmonyOS knowledge in any working directory:

```bash
# Clone the repository
git clone https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git ~/Claude/HarmonyOS-Dev-Env-Skill

# Copy rules to Claude Code's global config directory
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md

# Copy SSH polyfill and startup script (optional, required for SSH sessions)
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.claude/ssh-fetch-polyfill.js ~/.claude/ssh-fetch-polyfill.js
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.claude/start-claude.sh ~/.claude/start-claude.sh
```

### Option B: Project-Level Install

Only affects specific projects, doesn't change global behavior:

```bash
# Create .claude/ directory in your project root
mkdir -p <your-project>/.claude

# Copy rules files
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.md <your-project>/.claude/CLAUDE.md
cp ~/Claude/HarmonyOS-Dev-Env-Skill/rules/CLAUDE.cn.md <your-project>/.claude/CLAUDE.cn.md
```

### Configure Shell Environment

Either installation method requires shell environment setup for toolchain access:

```bash
# Copy zshenv config (includes all PATH/LD_LIBRARY_PATH/LD_PRELOAD settings)
cp ~/Claude/HarmonyOS-Dev-Env-Skill/config/.zshenv ~/.zshenv
source ~/.zshenv
```

### Verify Installation

After installation, start Claude Code and verify the Agent has loaded HarmonyOS knowledge:

```
# Ask Claude Code a question — if it knows these details, the Skill is active:
> "What do I need to know when compiling C code on HarmonyOS?"
# Expected answer should mention: code signing, ld.bfd wrapper, -B flag, no gcc, etc.

# Or run the verification script:
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/verify-env.sh
```

### How the Skill Works

| File | Purpose | When Loaded |
|------|---------|-------------|
| `~/.claude/CLAUDE.md` | Global rules (platform, toolchains, core issues) | Auto-loaded every conversation |
| `~/.claude/CLAUDE.cn.md` | Chinese version of global rules | Loaded alongside English version |
| `rules/CLAUDE.md` | Source rules file (to copy to global) | Not auto-loaded, must be copied |
| `config/.zshenv` | Shell PATH/LD configuration | Loaded at shell startup |
| `config/.claude/start-claude.sh` | Claude Code startup script (with SSH detection) | Manual start or SSH environment |
| `skill.json` | Skill metadata (tool versions, doc paths) | For programmatic Agent lookups |
| `docs/*.md` | Detailed adaptation guides | Agent reads when needed |

## 📋 Platform Characteristics

| Feature | Description |
|---------|-------------|
| Kernel | HongMeng Kernel 1.12.0 (based on musl libc) |
| Architecture | aarch64 (ARM64) |
| Compiler | Clang 15.0.4 (no gcc) |
| Code signing | All ELF binaries must be signed before execution |
| /tmp | Read-only, use `$HOME/Claude/tmpdir` instead |
| Dynamic linker | ld.bfd wrapper (SDK lld broken) |

## 🔧 Adapted Toolchains

| Toolchain | Version | Category | Status | Docs |
|-----------|---------|----------|:------:|------|
| Python | 3.12.8 | Language | ✅ | [docs/python-harmonyos.md](docs/python-harmonyos.md) |
| Node.js | 24.13.0 | Language | ✅ | [docs/nodejs-harmonyos.md](docs/nodejs-harmonyos.md) |
| Rust | 1.95.0 | Language | ✅ | [docs/rust-harmonyos.md](docs/rust-harmonyos.md) |
| Go | 1.22.5 | Language | ✅ | [tools/go/build.md](tools/go/build.md) |
| Claude Code | 2.1.88-ohos | AI Tool | ✅ | [docs/claude-code-harmonyos.md](docs/claude-code-harmonyos.md) |
| PyTorch | 2.5.1 | ML Framework | ✅ | [docs/pytorch-harmonyos.md](docs/pytorch-harmonyos.md) |
| llama.cpp | b9073 | ML Inference | ✅ | [docs/llama-cpp-harmonyos.md](docs/llama-cpp-harmonyos.md) |
| mihomo | Meta | Network | ✅ | [docs/mihomo-harmonyos.md](docs/mihomo-harmonyos.md) |
| Dropbear SSH | 2024.86 | Network | ✅ | [docs/dropbear-harmonyos.md](docs/dropbear-harmonyos.md) |
| OpenSSH | 9.9p1 | Network | ✅ | [docs/openssh-harmonyos.md](docs/openssh-harmonyos.md) |
| eza | 0.23.4 | Utility | ✅ | [docs/eza-harmonyos.md](docs/eza-harmonyos.md) |
| bat | 0.26.1 | Utility | ✅ | [docs/bat-harmonyos.md](docs/bat-harmonyos.md) |
| starship | 1.25.1 | Utility | ✅ | [docs/starship-harmonyos.md](docs/starship-harmonyos.md) |

## ⚠️ Core Issues

<details>
<summary><strong>Code Signing</strong> (Most Critical — all ELF binaries must be signed)</summary>

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned> -outFile <signed> -signAlg SHA256withECDSA
```

</details>

<details>
<summary><strong>/tmp Read-Only</strong> — use writable temp directory instead</summary>

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

</details>

<details>
<summary><strong>LD_LIBRARY_PATH Order</strong> — /usr/lib must come first</summary>

**Critical**: `/usr/lib` must come before `$HOME/.rust/lib` to avoid OpenSSL symbol version conflicts:

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64
```

</details>

<details>
<summary><strong>No gcc</strong> — only clang available</summary>

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

</details>

<details>
<summary><strong>Linker Wrapper</strong> — SDK lld doesn't work</summary>

SDK's lld requires `libxml2.so.16` (doesn't exist). Use ld.bfd wrapper:

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
echo '#!/bin/sh' > $HOME/Claude/lib/linker_wrapper/ld.lld
echo 'exec /data/service/hnp/bin/ld.bfd "$@"' >> $HOME/Claude/lib/linker_wrapper/ld.lld
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
# Add -B$HOME/Claude/lib/linker_wrapper to all clang commands
```

</details>

<details>
<summary><strong>OpenSSH passwd_compat</strong> — UID not in /etc/passwd</summary>

sshd requires LD_PRELOAD because uid 20020106 is not in /etc/passwd (read-only):

```bash
export LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so
```

ssh-agent uses abstract namespace socket (`SSH_AUTH_SOCK=abstract:<name>`).

</details>

## 🔨 Install Toolchains

After the Skill is installed, install toolchains as needed (each install.sh handles code signing automatically):

```bash
cd ~/Claude/HarmonyOS-Dev-Env-Skill

./tools/python/install.sh    # Python (pip + numpy + extension modules)
./tools/rust/install.sh      # Rust (official ohos target)
./tools/go/install.sh        # Go
./tools/llama-cpp/install.sh # llama.cpp (NEON/SVE optimization)
./tools/mihomo/install.sh    # mihomo (Clash Meta proxy)
./tools/dropbear/install.sh  # Dropbear SSH (requires manual source patches)
# OpenSSH requires manual patches + build, see tools/openssh/build.md
```

> **Note**: Dropbear and OpenSSH require manual source code edits (5 / 16 patches respectively). The install.sh will indicate which files need modification. See each tool's `build.md` for detailed patch instructions.

## 📚 Documentation Index

**Tool Adaptation Guides**

| Document | Description |
|----------|-------------|
| [Claude Code](docs/claude-code-harmonyos.md) | AI assistant, npm install, SSH V8 fix |
| [Node.js (DevNode-OH)](docs/nodejs-harmonyos.md) | Node.js setup, TLS/V8 issues |
| [Python Environment](docs/python-harmonyos.md) | Python 3.12.8, pip, numpy, extensions |
| [Python Packages](docs/python-packages-harmonyos.md) | 34 packages compatibility report |
| [Rust](docs/rust-harmonyos.md) | Rust 1.95.0, cargo, FFI |
| [PyTorch](docs/pytorch-harmonyos.md) | PyTorch v2.5.1, 15/15 tests, LAPACK |
| [llama.cpp](docs/llama-cpp-harmonyos.md) | NEON/SVE, Qwen3.5 model |
| [mihomo](docs/mihomo-harmonyos.md) | HTTP/SOCKS5, GEOIP/GEOSITE |
| [Dropbear SSH](docs/dropbear-harmonyos.md) | SSH server, 5 patches, V8 crash fix |
| [OpenSSH](docs/openssh-harmonyos.md) | OpenSSH 9.9p1, 16 patches, scp/sftp/ssh-agent |
| [eza](docs/eza-harmonyos.md) | Modern ls, icons, Git status |
| [bat](docs/bat-harmonyos.md) | Syntax-highlighted cat |
| [starship](docs/starship-harmonyos.md) | Cross-shell prompt |

**Platform Issue Guides**

| Document | Description |
|----------|-------------|
| [Code Signing](docs/code-signing.md) | ELF/HAP signing guide |
| [LD_LIBRARY_PATH](docs/ld-library-path.md) | Library path configuration |
| [SELinux Analysis](docs/selinux-analysis.md) | .so loading root cause |
| [IPC Feasibility](docs/ipc-feasibility.md) | Native child process API |
| [Troubleshooting](docs/troubleshooting.md) | Consolidated problem-solving |

---

<div align="center">

**Tested on**: HarmonyOS HongMeng Kernel 1.12.0, aarch64

MIT License — Issues and PRs welcome at [GitHub](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)

[🇨🇳 中文版](#中文版) ｜ [🇬🇧 English Version](#english-version)

</div>