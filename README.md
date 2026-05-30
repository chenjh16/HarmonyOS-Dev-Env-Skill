<div align="center">

# HarmonyOS PC Development Environment Skill Pack

**HarmonyOS (鸿蒙) PC 开发环境配置技能包**

[![GitHub](https://img.shields.io/badge/GitHub-chenjh16/HarmonyOS--Dev--Env--Skill-blue?logo=github)](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)
![License](https://img.shields.io/badge/License-MIT-green.svg)
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

**为什么需要这个 Skill?** HarmonyOS PC 的开发环境与标准 Linux 差异巨大，而且很多差异会直接阻断常规开发流程：所有 ELF 二进制和 `.so` 扩展模块都需要代码签名，`/tmp` 只读，系统无 gcc，SDK 自带 lld 因缺少 `libxml2.so.16` 无法直接使用，AppGallery 安装的 Python 开发环境难以支撑带原生 `.so` 的非纯 Python pip 包，系统没有开箱即用的原生 SSH 服务，也没有官方可直接使用的 Rust、Go、PyTorch 等开发环境。没有这些知识的 Agent 会反复踩坑、编译失败，甚至给出在标准 Linux 上正确但在 HarmonyOS PC 上不可执行的方案。安装本 Skill 后，Claude Code Agent 会自动获得完整的鸿蒙适配经验，直接产出可用的构建、签名、运行和排障方案。

## 📦 Skill 安装与使用

本 Skill 遵循 Claude Code 标准 Skill 结构（`~/.claude/skills/<name>/SKILL.md`），安装后 Agent 在每次对话中自动加载鸿蒙平台知识和完整适配文档。

| 安装方式 | 适用场景 | 影响范围 | 推荐程度 |
|----------|----------|----------|:--------:|
| 一键安装 | 本地已克隆仓库，希望快速安装 | 全局 Skill | 推荐 |
| Agent 自动安装 | 希望让 Claude Code Agent 代为克隆、安装、配置 | 全局 Skill + 环境配置 | 推荐 |
| 项目级安装 | 只希望在某个项目内启用 HarmonyOS 知识 | 单个项目 | 可选 |

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
├── SKILL.md                    ← Skill 定义（英文，自动加载）
├── SKILL.cn.md                 ← Skill 定义（中文）
├── scripts/
│   ├── env-setup.sh            ← 一键环境配置
│   ├── sign-all.sh             ← 批量 ELF 代码签名
│   ├── verify-env.sh           ← 环境验证
│   ├── ssh-fetch-polyfill.js   ← SSH V8 崩溃 workaround
│   └── start-claude.sh         ← Claude Code 启动脚本
├── docs/                       ← 19 组双语适配文档
│   ├── python-harmonyos.md
│   ├── python-harmonyos.cn.md
│   ├── openssh-harmonyos.md
│   ├── openssh-harmonyos.cn.md
│   └── ...
├── tools/                      ← 11 个工具构建目录（6 个含 install.sh；另有 2 个外部安装工具链）
│   ├── python/
│   ├── rust/
│   ├── go/
│   ├── llama-cpp/
│   ├── mihomo/
│   ├── dropbear/
│   ├── openssh/
│   ├── pytorch/
│   ├── bat/
│   ├── eza/
│   └── starship/
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
# env-setup.sh 步骤 [5/7] 会分别检查并安装：
# - ~/.claude/CLAUDE.md 不存在时安装英文规则
# - ~/.claude/CLAUDE.cn.md 不存在时安装中文规则
# 已存在的文件不会被覆盖。
# 手动更新：
cp ~/.claude/skills/harmonyos-dev-env/assets/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/.claude/skills/harmonyos-dev-env/assets/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
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

验证脚本的预期输出：
- 核心工具和环境项通过时显示 `✓`
- 未安装的可选工具（如 PyTorch/OpenSSH）可能显示 warning
- 如果 `LD_LIBRARY_PATH` 检查失败，请先运行 `source ~/.zshenv`，并确认 `/usr/lib` 位于最前

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

| 工具链 | 版本 | 类别 | 安装方式 | 状态 | 文档 |
|--------|------|------|----------|:----:|------|
| Python | 3.12.8 | 语言 | `install.sh` | ✅ | [docs/python-harmonyos.cn.md](harmonyos-dev-env/docs/python-harmonyos.cn.md) |
| Node.js | 24.13.0 | 语言 | AppGallery / DevNode-OH | ✅ | [docs/nodejs-harmonyos.cn.md](harmonyos-dev-env/docs/nodejs-harmonyos.cn.md) |
| Rust | 1.95.0 | 语言 | `install.sh` | ✅ | [docs/rust-harmonyos.cn.md](harmonyos-dev-env/docs/rust-harmonyos.cn.md) |
| Go | 1.22.5 | 语言 | `install.sh` | ✅ | [tools/go/build.cn.md](harmonyos-dev-env/tools/go/build.cn.md) |
| Claude Code | 2.1.88-ohos.1 | AI工具 | HarmonyOS-Claude-Code / npm | ✅ | [docs/claude-code-harmonyos.cn.md](harmonyos-dev-env/docs/claude-code-harmonyos.cn.md) |
| PyTorch | 2.5.1 | ML框架 | `build.md` | ✅ | [docs/pytorch-harmonyos.cn.md](harmonyos-dev-env/docs/pytorch-harmonyos.cn.md) |
| llama.cpp | b9073 | ML推理 | `install.sh` | ✅ | [docs/llama-cpp-harmonyos.cn.md](harmonyos-dev-env/docs/llama-cpp-harmonyos.cn.md) |
| mihomo | Meta | 网络 | `install.sh` | ✅ | [docs/mihomo-harmonyos.cn.md](harmonyos-dev-env/docs/mihomo-harmonyos.cn.md) |
| Dropbear SSH | 2024.86 | 网络 | `install.sh` + 手动补丁 | ✅ | [docs/dropbear-harmonyos.cn.md](harmonyos-dev-env/docs/dropbear-harmonyos.cn.md) |
| OpenSSH | 9.9p1 | 网络 | `build.md` + 手动补丁 | ✅ | [docs/openssh-harmonyos.cn.md](harmonyos-dev-env/docs/openssh-harmonyos.cn.md) |
| eza | 0.23.4 | 工具 | `build.md` | ✅ | [docs/eza-harmonyos.cn.md](harmonyos-dev-env/docs/eza-harmonyos.cn.md) |
| bat | 0.26.1 | 工具 | `build.md` | ✅ | [docs/bat-harmonyos.cn.md](harmonyos-dev-env/docs/bat-harmonyos.cn.md) |
| starship | 1.25.1 | 工具 | `build.md` | ✅ | [docs/starship-harmonyos.cn.md](harmonyos-dev-env/docs/starship-harmonyos.cn.md) |

## ⚠️ 核心问题与解决方案

**14 个核心问题总览**

| # | 问题 | 影响 | 解决方向 |
|---|------|------|----------|
| 1 | 代码签名 | 未签名 ELF 二进制会立即崩溃 | 使用 `binary-sign-tool sign -selfSign 1` |
| 2 | `/tmp` 只读 | 构建、测试、临时文件创建失败 | 使用 `$HOME/Claude/tmpdir` |
| 3 | 无 gcc | 默认 gcc 的构建脚本失败 | 设置 `CC=/data/service/hnp/bin/clang` |
| 4 | SDK lld 损坏 | 链接时报缺少 `libxml2.so.16` | 创建 ld.bfd wrapper 并添加 `-B` |
| 5 | LD_LIBRARY_PATH 顺序 | OpenSSL 符号版本冲突 | `/usr/lib` 必须在 `$HOME/.rust/lib` 前 |
| 6 | `make -j` 失败 | mkfifo 权限错误导致并行构建失败 | 使用 Ninja |
| 7 | CMake toolchain 限制 | `try_run()` 在交叉编译模式失败 | 不要同时使用 `CMAKE_TOOLCHAIN_FILE` + `CMAKE_SYSTEM_NAME` |
| 8 | SSH V8 崩溃 | SSH PTY 下 Claude Code/Node.js 崩溃 | 使用 `node --jitless` + fetch polyfill |
| 9 | OpenSSH passwd_compat | uid 不在 `/etc/passwd`，sshd 启动/会话异常 | 使用 `LD_PRELOAD=passwd_compat_signed.so` |
| 10 | OpenSSH abstract socket | 文件系统 Unix socket bind 返回 EPERM | ssh-agent 使用 `abstract:` socket |
| 11 | OpenSSH authorized_keys UID | 文件 owner uid 与进程 uid 不一致 | 将 uid 20001006 视为系统目录 owner |
| 12 | Dropbear `-e` 参数 | SSH 子会话丢失 PATH/LD_LIBRARY_PATH | 启动 dropbear 时使用 `-e` |
| 13 | musl libc 差异 | 无 `crypt()`、locale 有限、errno/断言差异 | 禁用密码认证并按文档 patch |
| 14 | Python `-rdynamic` | 扩展模块需要 Python 符号导出 | 使用已适配的 Python 3.12.8 |

**重点问题展开说明**

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
# 以下工具以 build.md 为主（需要按文档手动构建/补丁）
# PyTorch: 见 harmonyos-dev-env/tools/pytorch/build.cn.md
# OpenSSH: 见 harmonyos-dev-env/tools/openssh/build.cn.md
# eza:     见 harmonyos-dev-env/tools/eza/build.cn.md
# bat:     见 harmonyos-dev-env/tools/bat/build.cn.md
# starship:见 harmonyos-dev-env/tools/starship/build.cn.md
```

> **注意**: 工具链 install.sh 脚本需要克隆完整仓库才能运行（Skill 安装目录也包含这些脚本）。Dropbear 和 OpenSSH 需要手动编辑源码补丁（5 个 / 16 个），install.sh 会提示哪些文件需要修改。

## 📚 文档索引

**工具适配指南**

| 文档 | 说明 |
|------|------|
| [Claude Code 适配](harmonyos-dev-env/docs/claude-code-harmonyos.cn.md) | AI 编程助手、npm 安装、SSH V8 修复 |
| [Node.js (DevNode-OH)](harmonyos-dev-env/docs/nodejs-harmonyos.cn.md) | Node.js 安装、TLS/V8 问题 |
| [Python 环境](harmonyos-dev-env/docs/python-harmonyos.cn.md) | Python 3.12.8、pip、numpy、扩展模块 |
| [Python 包兼容性](harmonyos-dev-env/docs/python-packages-harmonyos.cn.md) | 97 个包测试报告 |
| [Python 扩展适配指南](harmonyos-dev-env/docs/python-extension-adaptation.cn.md) | C/Rust/C++/Meson 包通用适配流程 |
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

## 🛠 维护说明

- README 内容刻意保持中英文完整镜像；修改时必须同步更新两个语言章节。
- 每个新增文档都必须同时提供 `.md` 和 `.cn.md` 版本。
- 新增或移除工具时，需要同步更新 README、`harmonyos-dev-env/SKILL.md`、`harmonyos-dev-env/SKILL.cn.md` 和 `skill.json`。
- 所有用户可变路径保持 `$HOME` 可移植写法；不要新增用户私有绝对路径。
- 保持 docs、scripts 和 `assets/rules/CLAUDE.md` 与核心平台规则和适配清单一致。

---

<a id="english-version"></a>

# 🇬🇧 English Version

This project is a **Claude Code Skill Pack** designed specifically for HarmonyOS PC. It gives AI Agents complete knowledge of the HarmonyOS development environment — platform quirks, code signing, toolchain configuration, and solutions to common pitfalls.

**Why this Skill?** HarmonyOS PC differs drastically from standard Linux, and many differences directly block normal development workflows: every ELF binary and `.so` extension module must be code-signed, `/tmp` is read-only, gcc is unavailable, the SDK-provided lld cannot be used directly because it requires the missing `libxml2.so.16`, the AppGallery Python development environment is difficult to use for non-pure-Python pip packages that ship native `.so` modules, there is no out-of-the-box native SSH service, and there are no officially ready-to-use Rust, Go, or PyTorch development environments. Without this knowledge, Agents will repeatedly hit platform-specific failures or suggest solutions that are correct on standard Linux but unusable on HarmonyOS PC. After installing this Skill, Claude Code automatically carries the full HarmonyOS adaptation experience and can produce working build, signing, runtime, and troubleshooting solutions directly.

## 📦 Skill Installation & Usage

This Skill follows the standard Claude Code Skill structure (`~/.claude/skills/<name>/SKILL.md`). Once installed, the Agent automatically loads HarmonyOS platform knowledge and full adaptation documentation in every conversation.

| Install method | Best for | Scope | Recommendation |
|----------------|----------|-------|:--------------:|
| One-click install | Users who already cloned the repository and want a quick install | Global Skill | Recommended |
| Agent auto-install | Users who want Claude Code Agent to clone, install, and configure everything | Global Skill + environment setup | Recommended |
| Project-level install | Users who only want HarmonyOS knowledge enabled for one project | Single project | Optional |

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
├── SKILL.md                    ← Skill definition (English, auto-loaded)
├── SKILL.cn.md                 ← Skill definition (Chinese)
├── scripts/
│   ├── env-setup.sh            ← One-time environment setup
│   ├── sign-all.sh             ← Batch ELF code signing
│   ├── verify-env.sh           ← Environment verification
│   ├── ssh-fetch-polyfill.js   ← SSH V8 crash workaround
│   └── start-claude.sh         ← Claude Code startup script
├── docs/                       ← 19 bilingual adaptation guides
│   ├── python-harmonyos.md
│   ├── python-harmonyos.cn.md
│   ├── openssh-harmonyos.md
│   ├── openssh-harmonyos.cn.md
│   └── ...
├── tools/                      ← 11 tool build directories (6 with install.sh; plus 2 external-install toolchains)
│   ├── python/
│   ├── rust/
│   ├── go/
│   ├── llama-cpp/
│   ├── mihomo/
│   ├── dropbear/
│   ├── openssh/
│   ├── pytorch/
│   ├── bat/
│   ├── eza/
│   └── starship/
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
# env-setup.sh step [5/7] checks and installs these independently:
# - Installs English rules if ~/.claude/CLAUDE.md does not exist
# - Installs Chinese rules if ~/.claude/CLAUDE.cn.md does not exist
# Existing files are not overwritten.
# Manual update:
cp ~/.claude/skills/harmonyos-dev-env/assets/rules/CLAUDE.md ~/.claude/CLAUDE.md
cp ~/.claude/skills/harmonyos-dev-env/assets/rules/CLAUDE.cn.md ~/.claude/CLAUDE.cn.md
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

Expected verification output:
- Critical tools and environment checks show `✓` when they pass
- Optional tools that are not installed yet (such as PyTorch/OpenSSH) may show warnings
- If the `LD_LIBRARY_PATH` check fails, run `source ~/.zshenv` and make sure `/usr/lib` is first

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

| Toolchain | Version | Category | Install method | Status | Docs |
|-----------|---------|----------|----------------|:------:|------|
| Python | 3.12.8 | Language | `install.sh` | ✅ | [docs/python-harmonyos.md](harmonyos-dev-env/docs/python-harmonyos.md) |
| Node.js | 24.13.0 | Language | AppGallery / DevNode-OH | ✅ | [docs/nodejs-harmonyos.md](harmonyos-dev-env/docs/nodejs-harmonyos.md) |
| Rust | 1.95.0 | Language | `install.sh` | ✅ | [docs/rust-harmonyos.md](harmonyos-dev-env/docs/rust-harmonyos.md) |
| Go | 1.22.5 | Language | `install.sh` | ✅ | [tools/go/build.md](harmonyos-dev-env/tools/go/build.md) |
| Claude Code | 2.1.88-ohos.1 | AI Tool | HarmonyOS-Claude-Code / npm | ✅ | [docs/claude-code-harmonyos.md](harmonyos-dev-env/docs/claude-code-harmonyos.md) |
| PyTorch | 2.5.1 | ML Framework | `build.md` | ✅ | [docs/pytorch-harmonyos.md](harmonyos-dev-env/docs/pytorch-harmonyos.md) |
| llama.cpp | b9073 | ML Inference | `install.sh` | ✅ | [docs/llama-cpp-harmonyos.md](harmonyos-dev-env/docs/llama-cpp-harmonyos.md) |
| mihomo | Meta | Network | `install.sh` | ✅ | [docs/mihomo-harmonyos.md](harmonyos-dev-env/docs/mihomo-harmonyos.md) |
| Dropbear SSH | 2024.86 | Network | `install.sh` + manual patches | ✅ | [docs/dropbear-harmonyos.md](harmonyos-dev-env/docs/dropbear-harmonyos.md) |
| OpenSSH | 9.9p1 | Network | `build.md` + manual patches | ✅ | [docs/openssh-harmonyos.md](harmonyos-dev-env/docs/openssh-harmonyos.md) |
| eza | 0.23.4 | Utility | `build.md` | ✅ | [docs/eza-harmonyos.md](harmonyos-dev-env/docs/eza-harmonyos.md) |
| bat | 0.26.1 | Utility | `build.md` | ✅ | [docs/bat-harmonyos.md](harmonyos-dev-env/docs/bat-harmonyos.md) |
| starship | 1.25.1 | Utility | `build.md` | ✅ | [docs/starship-harmonyos.md](harmonyos-dev-env/docs/starship-harmonyos.md) |

## ⚠️ Core Issues

**Overview of the 14 core issues**

| # | Issue | Impact | Fix direction |
|---|-------|--------|---------------|
| 1 | Code signing | Unsigned ELF binaries crash immediately | Use `binary-sign-tool sign -selfSign 1` |
| 2 | `/tmp` read-only | Builds, tests, and temp-file creation fail | Use `$HOME/Claude/tmpdir` |
| 3 | No gcc | Build scripts that default to gcc fail | Set `CC=/data/service/hnp/bin/clang` |
| 4 | SDK lld broken | Linking fails with missing `libxml2.so.16` | Create ld.bfd wrapper and add `-B` |
| 5 | LD_LIBRARY_PATH order | OpenSSL symbol version conflicts | `/usr/lib` must come before `$HOME/.rust/lib` |
| 6 | `make -j` fails | mkfifo permission error breaks parallel builds | Use Ninja |
| 7 | CMake toolchain limitation | `try_run()` fails in cross-compile mode | Do not combine `CMAKE_TOOLCHAIN_FILE` + `CMAKE_SYSTEM_NAME` |
| 8 | SSH V8 crash | Claude Code/Node.js crashes under SSH PTY | Use `node --jitless` + fetch polyfill |
| 9 | OpenSSH passwd_compat | uid missing from `/etc/passwd`; sshd/session issues | Use `LD_PRELOAD=passwd_compat_signed.so` |
| 10 | OpenSSH abstract socket | Filesystem Unix socket bind returns EPERM | ssh-agent uses `abstract:` socket |
| 11 | OpenSSH authorized_keys UID | File owner uid differs from process uid | Treat uid 20001006 as system directory owner |
| 12 | Dropbear `-e` flag | SSH child sessions lose PATH/LD_LIBRARY_PATH | Start dropbear with `-e` |
| 13 | musl libc differences | No `crypt()`, limited locale, errno/assert differences | Disable password auth and apply documented patches |
| 14 | Python `-rdynamic` | Extension modules need exported Python symbols | Use the adapted Python 3.12.8 |

**Detailed notes for key issues**

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
# The following tools are build.md-first (manual build/patches per guide)
# PyTorch:  see harmonyos-dev-env/tools/pytorch/build.md
# OpenSSH:  see harmonyos-dev-env/tools/openssh/build.md
# eza:      see harmonyos-dev-env/tools/eza/build.md
# bat:      see harmonyos-dev-env/tools/bat/build.md
# starship: see harmonyos-dev-env/tools/starship/build.md
```

> **Note**: Tool install.sh scripts require cloning the full repo (the Skill install directory also contains these scripts). Dropbear and OpenSSH require manual source code edits (5 / 16 patches respectively). See each tool's `build.md` for detailed patch instructions.

## 📚 Documentation Index

**Tool Adaptation Guides**

| Document | Description |
|----------|-------------|
| [Claude Code](harmonyos-dev-env/docs/claude-code-harmonyos.md) | AI assistant, npm install, SSH V8 fix |
| [Node.js (DevNode-OH)](harmonyos-dev-env/docs/nodejs-harmonyos.md) | Node.js setup, TLS/V8, 61/61 e2e tests |
| [Python Environment](harmonyos-dev-env/docs/python-harmonyos.md) | Python 3.12.8, pip, numpy, extensions |
| [Python Packages](harmonyos-dev-env/docs/python-packages-harmonyos.md) | 97 packages compatibility report |
| [Python Extension Adaptation](harmonyos-dev-env/docs/python-extension-adaptation.md) | General guide for adapting C/Rust/C++ Python packages |
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

## 🛠 Maintenance Notes

- README content is intentionally fully mirrored in Chinese and English; update both sections together.
- Every new documentation page must have both `.md` and `.cn.md` versions.
- When adding or removing tools, update README, `harmonyos-dev-env/SKILL.md`, `harmonyos-dev-env/SKILL.cn.md`, and `skill.json` together.
- Keep user-variable paths portable with `$HOME`; do not add user-specific absolute paths.
- Keep docs, scripts, and `assets/rules/CLAUDE.md` aligned with the core platform rules and adaptation checklist.

---

<div align="center">

**Tested on**: HarmonyOS HongMeng Kernel 1.12.0, aarch64

MIT License — Issues and PRs welcome at [GitHub](https://github.com/chenjh16/HarmonyOS-Dev-Env-Skill)

[🇨🇳 中文版](#中文版) ｜ [🇬🇧 English Version](#english-version)

</div>