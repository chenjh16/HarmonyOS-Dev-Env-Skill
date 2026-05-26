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

> **前置依赖**: 本项目依赖 [HarmonyOS-Claude-Code](https://github.com/chenjh16/HarmonyOS-Claude-Code) 提供的 HarmonyOS PC 版 Claude Code 运行环境。请先按该项目说明完成 Claude Code 安装和基础环境配置，再安装本 Skill Pack。
>
> **Prerequisite**: This project depends on [HarmonyOS-Claude-Code](https://github.com/chenjh16/HarmonyOS-Claude-Code) for the HarmonyOS PC version of Claude Code runtime. Please complete Claude Code installation and basic environment setup following that project first, then install this Skill Pack.

---

<a id="中文版"></a>

# 🇨🇳 中文版

本项目是专为 **HarmonyOS (鸿蒙) PC** 设计的 Claude Code Skill Pack，让 AI Agent 在鸿蒙平台上也能获得完整的开发环境知识——包括平台特性、代码签名、工具链配置、常见问题解决方案等。

**为什么需要这个 Skill?** HarmonyOS PC 的开发环境与标准 Linux 差异巨大（代码签名、只读 /tmp、无 gcc、SDK lld 损坏等）。没有这些知识的 Agent 会反复踩坑、编译失败。安装本 Skill 后，Claude Code Agent 会自动获得所有鸿蒙适配经验，直接产出可用的构建方案。

## 📦 Skill 安装与使用

本 Skill 遵循 Claude Code 标准 Skill 结构（`~/.claude/skills/<name>/SKILL.md`），安装后 Agent 在每次对话中自动加载鸿蒙平台知识和完整适配文档。

### 方式一：一键安装（推荐）

使用项目自带的安装脚本，将 `harmonyos-dev-env/` 目录整体复制到 `~/.claude/skills/`：

```bash
# 克隆仓库
git clone https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git ~/Claude/HarmonyOS-Dev-Env-Skill

# 运行安装脚本（自动 cp -r harmonyos-dev-env/ → ~/.claude/skills/）
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh
```

安装后的 Skill 目录结构：

```
~/.claude/skills/harmonyos-dev-env/
├── SKILL.md                    ← Skill 定义（YAML frontmatter + 平台规则 + 工具链参考）
│                                  Agent 每次对话自动发现，用户可 /harmonyos-dev-env 调用
├── scripts/
│   ├── env-setup.sh            ← 一键环境配置（tmpdir + linker wrapper + zshenv + SSH polyfill）
│   ├── sign-all.sh             ← 批量 ELF 代码签名
│   ├── verify-env.sh           ← 环境验证（检查所有工具链）
│   ├── ssh-fetch-polyfill.js   ← SSH V8 崩溃 workaround
│   └── start-claude.sh         ← Claude Code 启动脚本（SSH 检测）
├── docs/                       ← 18 组双语适配文档（Agent 需要时主动 Read 查阅）
│   ├── python-harmonyos.md / .cn.md
│   ├── openssh-harmonyos.md / .cn.md
│   └── ...
├── tools/                      ← 11 工具构建指南 + install.sh
│   ├── python/  ├── rust/  ├── go/  ├── llama-cpp/  ├── mihomo/
│   ├── dropbear/ ├── openssh/ ├── pytorch/
│   ├── bat/  ├── eza/  ├── starship/
└── assets/                     ← 安装辅助资产（非 skill 知识本体）
    ├── zshenv                  ← Shell PATH/LD 配置模板
    └── rules/
        ├── CLAUDE.md           ← 全局平台规则（英文）
        └── CLAUDE.cn.md        ← 全局平台规则（中文）
```

### 方式二：Agent 自动安装

将以下 Prompt 复制并发送给 Claude Code Agent，Agent 会自动完成全局安装和环境配置：

```
请帮我安装 HarmonyOS 开发环境 Skill。步骤：
1. 克隆仓库 https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git 到 ~/Claude/HarmonyOS-Dev-Env-Skill
2. 运行安装脚本: sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh
3. 运行环境配置: sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh
4. 验证安装: 确认 ~/.claude/skills/harmonyos-dev-env/SKILL.md 存在
安装完成后告诉我结果。
```

### 方式三：项目级安装

仅对特定项目生效，不影响其他项目：

```bash
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh --project <your-project-path>
```

### 配置开发环境

安装 Skill 后，运行一键环境配置脚本（创建可写 tmpdir、ld.bfd 封装、安装 zshenv 等）：

```bash
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh
source ~/.zshenv
```

### 全局规则补充安装（可选）

除了 Skill 机制外，还可以将规则文件安装到全局 `~/.claude/CLAUDE.md`（双重保障）：

```bash
# env-setup.sh 步骤 [5/6] 会自动处理（如果 ~/.claude/CLAUDE.md 不存在）
# 手动更新：
cp ~/.claude/skills/harmonyos-dev-env/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/.claude/skills/harmonyos-dev-env/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
```

> **注意**: Skill 安装（方式一）和 CLAUDE.md 规则（方式三）是互补的。Skill 提供可调用的 `/harmonyos-dev-env` 命令和完整文档查阅能力，CLAUDE.md 规则在每次对话中强制注入核心平台知识。两者同时安装效果最佳。

### 验证安装

安装完成后，启动 Claude Code 并验证 Skill 是否生效：

```
# 方式一：在 Claude Code 中直接调用 Skill
> /harmonyos-dev-env 代码签名怎么做？

# 方式二：提问测试 Agent 是否加载了鸿蒙知识
> "HarmonyOS 上编译 C 代码需要注意什么？"
# 预期回答应包含：代码签名、ld.bfd 封装、-B 参数、无 gcc 等

# 方式三：运行验证脚本
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```

### Skill 工作原理

Claude Code 通过文件系统自动发现 Skills：

| 路径 | 作用 | 加载时机 |
|------|------|----------|
| `~/.claude/skills/<name>/SKILL.md` | Skill 定义（规则 + 文档索引） | 每次对话自动发现，用户可 `/name` 调用 |
| `~/.claude/CLAUDE.md` | 全局规则（强制注入核心知识） | 每次对话自动加载 |
| `SKILL.md` 中的 `docs/` 引用 | 完整适配指南 | Agent 需要时主动 Read 查阅 |
| `SKILL.md` 中的 `scripts/` | 签名/验证/启动脚本 | Agent 执行 Bash 命令时调用 |
| `assets/zshenv` | Shell PATH/LD 配置 | shell 启动时加载（env-setup.sh 自动安装） |

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
| Python | 3.12.8 | 语言 | ✅ | [docs/python-harmonyos.cn.md](harmonyos-dev-env/docs/python-harmonyos.cn.md) |
| Node.js | 24.13.0 | 语言 | ✅ | [docs/nodejs-harmonyos.cn.md](harmonyos-dev-env/docs/nodejs-harmonyos.cn.md) |
| Rust | 1.95.0 | 语言 | ✅ | [docs/rust-harmonyos.cn.md](harmonyos-dev-env/docs/rust-harmonyos.cn.md) |
| Go | 1.22.5 | 语言 | ✅ | [tools/go/build.cn.md](harmonyos-dev-env/tools/go/build.cn.md) |
| Claude Code | 2.1.88-ohos | AI工具 | ✅ | [docs/claude-code-harmonyos.cn.md](harmonyos-dev-env/docs/claude-code-harmonyos.cn.md) |
| PyTorch | 2.5.1 | ML框架 | ✅ | [docs/pytorch-harmonyos.cn.md](harmonyos-dev-env/docs/pytorch-harmonyos.cn.md) |
| llama.cpp | b9073 | ML推理 | ✅ | [docs/llama-cpp-harmonyos.cn.md](harmonyos-dev-env/docs/llama-cpp-harmonyos.cn.md) |
| mihomo | Meta | 网络 | ✅ | [docs/mihomo-harmonyos.cn.md](harmonyos-dev-env/docs/mihomo-harmonyos.cn.md) |
| Dropbear SSH | 2024.86 | 网络 | ✅ | [docs/dropbear-harmonyos.cn.md](harmonyos-dev-env/docs/dropbear-harmonyos.cn.md) |
| OpenSSH | 9.9p1 | 网络 | ✅ | [docs/openssh-harmonyos.cn.md](harmonyos-dev-env/docs/openssh-harmonyos.cn.md) |
| eza | 0.23.4 | 工具 | ✅ | [docs/eza-harmonyos.cn.md](harmonyos-dev-env/docs/eza-harmonyos.cn.md) |
| bat | 0.26.1 | 工具 | ✅ | [docs/bat-harmonyos.cn.md](harmonyos-dev-env/docs/bat-harmonyos.cn.md) |
| starship | 1.25.1 | 工具 | ✅ | [docs/starship-harmonyos.cn.md](harmonyos-dev-env/docs/starship-harmonyos.cn.md) |

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

# 从 harmonyos-dev-env/tools/ 目录运行（需要克隆仓库）
./harmonyos-dev-env/tools/python/install.sh    # Python (pip + numpy + 扩展模块)
./harmonyos-dev-env/tools/rust/install.sh      # Rust (官方 ohos 目标)
./harmonyos-dev-env/tools/go/install.sh        # Go
./harmonyos-dev-env/tools/llama-cpp/install.sh # llama.cpp (NEON/SVE 优化)
./harmonyos-dev-env/tools/mihomo/install.sh    # mihomo (Clash Meta 代理)
./harmonyos-dev-env/tools/dropbear/install.sh  # Dropbear SSH (需手动源码补丁)
# OpenSSH 需手动补丁+构建，见 harmonyos-dev-env/tools/openssh/build.md
```

> **注意**: 工具链 install.sh 脚本需要克隆完整仓库才能运行（Skill 安装目录也包含这些脚本）。Dropbear 和 OpenSSH 需要手动编辑源码补丁（5 个 / 16 个），install.sh 会提示哪些文件需要修改。

## 📚 文档索引

**工具适配指南**

| 文档 | 说明 |
|------|------|
| [Claude Code 适配](harmonyos-dev-env/docs/claude-code-harmonyos.cn.md) | AI 编程助手、npm 安装、SSH V8 修复 |
| [Node.js (DevNode-OH)](harmonyos-dev-env/docs/nodejs-harmonyos.cn.md) | Node.js 安装、TLS/V8 问题 |
| [Python 环境](harmonyos-dev-env/docs/python-harmonyos.cn.md) | Python 3.12.8、pip、numpy、扩展模块 |
| [Python 包兼容性](harmonyos-dev-env/docs/python-packages-harmonyos.cn.md) | 34 个包测试报告 |
| [Rust 适配](harmonyos-dev-env/docs/rust-harmonyos.cn.md) | Rust 1.95.0、cargo、FFI |
| [PyTorch 适配](harmonyos-dev-env/docs/pytorch-harmonyos.cn.md) | PyTorch v2.5.1、15/15 测试、LAPACK |
| [llama.cpp 适配](harmonyos-dev-env/docs/llama-cpp-harmonyos.cn.md) | NEON/SVE、Qwen3.5 模型 |
| [mihomo 适配](harmonyos-dev-env/docs/mihomo-harmonyos.cn.md) | HTTP/SOCKS5、GEOIP/GEOSITE |
| [Dropbear SSH](harmonyos-dev-env/docs/dropbear-harmonyos.cn.md) | SSH 服务器、5 个补丁、V8 crash 修复 |
| [OpenSSH 适配](harmonyos-dev-env/docs/openssh-harmonyos.cn.md) | OpenSSH 9.9p1、16 个补丁、scp/sftp/ssh-agent |
| [eza 适配](harmonyos-dev-env/docs/eza-harmonyos.cn.md) | 现代 ls、图标、Git 状态 |
| [bat 适配](harmonyos-dev-env/docs/bat-harmonyos.cn.md) | 语法高亮 cat |
| [starship 适配](harmonyos-dev-env/docs/starship-harmonyos.cn.md) | 跨 shell 提示符 |

**平台问题指南**

| 文档 | 说明 |
|------|------|
| [代码签名](harmonyos-dev-env/docs/code-signing.cn.md) | ELF/HAP 签名指南 |
| [LD_LIBRARY_PATH](harmonyos-dev-env/docs/ld-library-path.cn.md) | 动态库路径配置 |
| [SELinux 分析](harmonyos-dev-env/docs/selinux-analysis.cn.md) | .so 加载限制根因 |
| [IPC 可行性](harmonyos-dev-env/docs/ipc-feasibility.cn.md) | Native 子进程 API |
| [故障排除](harmonyos-dev-env/docs/troubleshooting.cn.md) | 综合问题解决参考 |

---

<a id="english-version"></a>

# 🇬🇧 English Version

This project is a **Claude Code Skill Pack** designed specifically for HarmonyOS PC. It gives AI Agents complete knowledge of the HarmonyOS development environment — platform quirks, code signing, toolchain configuration, and solutions to common pitfalls.

**Why this Skill?** HarmonyOS PC differs drastically from standard Linux (code signing mandatory, read-only /tmp, no gcc, broken SDK lld, etc.). Without this knowledge, Agents will repeatedly fail at compilation tasks. After installing this Skill, Claude Code automatically carries all HarmonyOS adaptation experience and produces working build solutions directly.

## 📦 Skill Installation & Usage

This Skill follows the standard Claude Code Skill structure (`~/.claude/skills/<name>/SKILL.md`). Once installed, the Agent automatically loads HarmonyOS platform knowledge and full adaptation documentation in every conversation.

### Option A: One-Click Install (Recommended)

Use the project's built-in install script to copy the entire `harmonyos-dev-env/` directory into `~/.claude/skills/`:

```bash
# Clone the repository
git clone https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git ~/Claude/HarmonyOS-Dev-Env-Skill

# Run the install script (automatically cp -r harmonyos-dev-env/ → ~/.claude/skills/)
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh
```

The installed Skill directory structure:

```
~/.claude/skills/harmonyos-dev-env/
├── SKILL.md                    ← Skill definition (YAML frontmatter + platform rules + toolchain reference)
│                                  Auto-discovered every conversation; user can invoke /harmonyos-dev-env
├── scripts/
│   ├── env-setup.sh            ← One-time env config (tmpdir + linker wrapper + zshenv + SSH polyfill)
│   ├── sign-all.sh             ← Batch ELF code signing
│   ├── verify-env.sh           ← Environment verification (checks all toolchains)
│   ├── ssh-fetch-polyfill.js   ← SSH V8 crash workaround
│   └── start-claude.sh         ← Claude Code startup script (SSH detection)
├── docs/                       ← 18 bilingual adaptation guides (Agent reads when needed)
│   ├── python-harmonyos.md / .cn.md
│   ├── openssh-harmonyos.md / .cn.md
│   └── ...
├── tools/                      ← 11 tool build guides + install.sh
│   ├── python/  ├── rust/  ├── go/  ├── llama-cpp/  ├── mihomo/
│   ├── dropbear/ ├── openssh/ ├── pytorch/
│   ├── bat/  ├── eza/  ├── starship/
└── assets/                     ← Installation assets (not skill knowledge per se)
    ├── zshenv                  ← Shell PATH/LD config template
    └── rules/
        ├── CLAUDE.md           ← Global platform rules (English)
        └── CLAUDE.cn.md        ← Global platform rules (Chinese)
```

### Option B: Agent Auto-Install

Copy and send the following Prompt to Claude Code Agent — it will automatically perform global install and environment setup:

```
Please install the HarmonyOS development environment Skill for me. Steps:
1. Clone repo https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill.git to ~/Claude/HarmonyOS-Dev-Env-Skill
2. Run install script: sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh
3. Run env setup: sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh
4. Verify: confirm ~/.claude/skills/harmonyos-dev-env/SKILL.md exists
Report the result when done.
```

### Option C: Project-Level Install

Only affects specific projects, doesn't change global behavior:

```bash
sh ~/Claude/HarmonyOS-Dev-Env-Skill/scripts/install-skill.sh --project <your-project-path>
```

### Configure Development Environment

After installing the Skill, run the one-time environment setup script (creates writable tmpdir, ld.bfd wrapper, installs zshenv, etc.):

```bash
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh
source ~/.zshenv
```

### Global Rules Supplement (Optional)

In addition to the Skill mechanism, install rules to global `~/.claude/CLAUDE.md` (double guarantee):

```bash
# env-setup.sh step [5/6] handles this automatically (if ~/.claude/CLAUDE.md doesn't exist)
# Manual update:
cp ~/.claude/skills/harmonyos-dev-env/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/.claude/skills/harmonyos-dev-env/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
```

> **Note**: Option A (Skill install) and the CLAUDE.md rules are complementary. The Skill provides an invocable `/harmonyos-dev-env` command and full documentation access, while CLAUDE.md rules force-inject core platform knowledge in every conversation. Best results with both installed.

### Verify Installation

After installation, start Claude Code and verify the Skill is active:

```
# Option A: Directly invoke the Skill in Claude Code
> /harmonyos-dev-env How does code signing work?

# Option B: Test if the Agent has loaded HarmonyOS knowledge
> "What do I need to know when compiling C code on HarmonyOS?"
# Expected answer should mention: code signing, ld.bfd wrapper, -B flag, no gcc, etc.

# Option C: Run the verification script
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```

### How the Skill Works

Claude Code auto-discovers Skills through the filesystem:

| Path | Purpose | When Loaded |
|------|---------|-------------|
| `~/.claude/skills/<name>/SKILL.md` | Skill definition (rules + doc index) | Auto-discovered every conversation; user can invoke `/name` |
| `~/.claude/CLAUDE.md` | Global rules (force-inject core knowledge) | Auto-loaded every conversation |
| `docs/` references in SKILL.md | Full adaptation guides | Agent reads when needed |
| `scripts/` references in SKILL.md | Sign/verify/start scripts | Agent calls via Bash when executing |
| `assets/zshenv` | Shell PATH/LD config | Loaded at shell startup (env-setup.sh auto-installs) |

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
| Python | 3.12.8 | Language | ✅ | [docs/python-harmonyos.md](harmonyos-dev-env/docs/python-harmonyos.md) |
| Node.js | 24.13.0 | Language | ✅ | [docs/nodejs-harmonyos.md](harmonyos-dev-env/docs/nodejs-harmonyos.md) |
| Rust | 1.95.0 | Language | ✅ | [docs/rust-harmonyos.md](harmonyos-dev-env/docs/rust-harmonyos.md) |
| Go | 1.22.5 | Language | ✅ | [tools/go/build.md](harmonyos-dev-env/tools/go/build.md) |
| Claude Code | 2.1.88-ohos | AI Tool | ✅ | [docs/claude-code-harmonyos.md](harmonyos-dev-env/docs/claude-code-harmonyos.md) |
| PyTorch | 2.5.1 | ML Framework | ✅ | [docs/pytorch-harmonyos.md](harmonyos-dev-env/docs/pytorch-harmonyos.md) |
| llama.cpp | b9073 | ML Inference | ✅ | [docs/llama-cpp-harmonyos.md](harmonyos-dev-env/docs/llama-cpp-harmonyos.md) |
| mihomo | Meta | Network | ✅ | [docs/mihomo-harmonyos.md](harmonyos-dev-env/docs/mihomo-harmonyos.md) |
| Dropbear SSH | 2024.86 | Network | ✅ | [docs/dropbear-harmonyos.md](harmonyos-dev-env/docs/dropbear-harmonyos.md) |
| OpenSSH | 9.9p1 | Network | ✅ | [docs/openssh-harmonyos.md](harmonyos-dev-env/docs/openssh-harmonyos.md) |
| eza | 0.23.4 | Utility | ✅ | [docs/eza-harmonyos.md](harmonyos-dev-env/docs/eza-harmonyos.md) |
| bat | 0.26.1 | Utility | ✅ | [docs/bat-harmonyos.md](harmonyos-dev-env/docs/bat-harmonyos.md) |
| starship | 1.25.1 | Utility | ✅ | [docs/starship-harmonyos.md](harmonyos-dev-env/docs/starship-harmonyos.md) |

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

# Run from harmonyos-dev-env/tools/ directory (requires cloned repo)
./harmonyos-dev-env/tools/python/install.sh    # Python (pip + numpy + extension modules)
./harmonyos-dev-env/tools/rust/install.sh      # Rust (official ohos target)
./harmonyos-dev-env/tools/go/install.sh        # Go
./harmonyos-dev-env/tools/llama-cpp/install.sh # llama.cpp (NEON/SVE optimization)
./harmonyos-dev-env/tools/mihomo/install.sh    # mihomo (Clash Meta proxy)
./harmonyos-dev-env/tools/dropbear/install.sh  # Dropbear SSH (requires manual source patches)
# OpenSSH requires manual patches + build, see harmonyos-dev-env/tools/openssh/build.md
```

> **Note**: Tool install.sh scripts require cloning the full repo (the Skill install directory also contains these scripts). Dropbear and OpenSSH require manual source code edits (5 / 16 patches respectively). See each tool's `build.md` for detailed patch instructions.

## 📚 Documentation Index

**Tool Adaptation Guides**

| Document | Description |
|----------|-------------|
| [Claude Code](harmonyos-dev-env/docs/claude-code-harmonyos.md) | AI assistant, npm install, SSH V8 fix |
| [Node.js (DevNode-OH)](harmonyos-dev-env/docs/nodejs-harmonyos.md) | Node.js setup, TLS/V8 issues |
| [Python Environment](harmonyos-dev-env/docs/python-harmonyos.md) | Python 3.12.8, pip, numpy, extensions |
| [Python Packages](harmonyos-dev-env/docs/python-packages-harmonyos.md) | 34 packages compatibility report |
| [Rust](harmonyos-dev-env/docs/rust-harmonyos.md) | Rust 1.95.0, cargo, FFI |
| [PyTorch](harmonyos-dev-env/docs/pytorch-harmonyos.md) | PyTorch v2.5.1, 15/15 tests, LAPACK |
| [llama.cpp](harmonyos-dev-env/docs/llama-cpp-harmonyos.md) | NEON/SVE, Qwen3.5 model |
| [mihomo](harmonyos-dev-env/docs/mihomo-harmonyos.md) | HTTP/SOCKS5, GEOIP/GEOSITE |
| [Dropbear SSH](harmonyos-dev-env/docs/dropbear-harmonyos.md) | SSH server, 5 patches, V8 crash fix |
| [OpenSSH](harmonyos-dev-env/docs/openssh-harmonyos.md) | OpenSSH 9.9p1, 16 patches, scp/sftp/ssh-agent |
| [eza](harmonyos-dev-env/docs/eza-harmonyos.md) | Modern ls, icons, Git status |
| [bat](harmonyos-dev-env/docs/bat-harmonyos.md) | Syntax-highlighted cat |
| [starship](harmonyos-dev-env/docs/starship-harmonyos.md) | Cross-shell prompt |

**Platform Issue Guides**

| Document | Description |
|----------|-------------|
| [Code Signing](harmonyos-dev-env/docs/code-signing.md) | ELF/HAP signing guide |
| [LD_LIBRARY_PATH](harmonyos-dev-env/docs/ld-library-path.md) | Library path configuration |
| [SELinux Analysis](harmonyos-dev-env/docs/selinux-analysis.md) | .so loading root cause |
| [IPC Feasibility](harmonyos-dev-env/docs/ipc-feasibility.md) | Native child process API |
| [Troubleshooting](harmonyos-dev-env/docs/troubleshooting.md) | Consolidated problem-solving |

---

<div align="center">

**Tested on**: HarmonyOS HongMeng Kernel 1.12.0, aarch64

MIT License — Issues and PRs welcome at [GitHub](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)

[🇨🇳 中文版](#中文版) ｜ [🇬🇧 English Version](#english-version)

</div>