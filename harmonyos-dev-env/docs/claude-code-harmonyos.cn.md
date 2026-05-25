# Claude Code 在 HarmonyOS (aarch64) 上的适配指南

> **英文版本请查看 claude-code-harmonyos.md**

## 概述

**Claude Code for HarmonyOS** 是 Anthropic Claude Code AI 编程助手的移植版本，可在 HarmonyOS 6.0 PC（AArch64，musl libc）上原生运行。

**项目地址**：https://github.com/chenjh16/HarmonyOS-Claude-Code
**版本**：2.1.88-ohos.1（基于 Claude Code v2.1.88）

## 主要特性

- **交互式 TUI** — 富终端界面，支持语法高亮、流式响应
- **Agent 模式** — 自主编码，支持文件编辑、命令执行、多步推理
- **Bare 模式** — 可脚本化的单提示接口，适用于自动化
- **40+ 内置工具** — 文件编辑、grep、glob、bash、LSP、MCP 等
- **100+ 斜杠命令** — 常见任务的快捷操作
- **MCP 支持** — 通过 Model Context Protocol 服务器扩展
- **HarmonyOS 原生** — 在 HarmonyOS 6.0 PC 上测试验证通过

## 前置条件

| 要求 | 说明 |
|------|------|
| Node.js >= 20 | 从应用市场安装 DevNode-OH |
| npm 全局 PATH | `export PATH=$(npm prefix -g)/bin:$PATH` |
| "运行来自非应用市场的扩展程序" | 设置 > 隐私和安全 > 高级 |

## 安装步骤

### 第 1 步：安装 Node.js

1. 在 HarmonyOS PC 上打开**应用市场（AppGallery）**
2. 搜索并安装 **DevNode-OH**
3. 关闭并重新打开 **HiShell**
4. 验证：`node -v` → v24.13.0
5. 配置 PATH：
   ```bash
   echo 'export PATH=$(npm prefix -g)/bin:$PATH' >> $HOME/.zshrc
   ```
6. 重新打开 HiShell

### 第 2 步：获取 npm 包

**方式 A：下载预构建包**

从 [Releases](https://github.com/chenjh16/HarmonyOS-Claude-Code/releases) 下载：
- 下载 `claude-code-ohos-<version>.tgz`
- 传输到 HarmonyOS PC（通过云盘、IM 软件、邮件或 hdc）

**方式 B：从源码构建（在 Mac/Linux 上）**

```bash
git clone https://github.com/chenjh16/HarmonyOS-Claude-Code.git
cd HarmonyOS-Claude-Code
make npm-pack
# 输出：npm-dist/claude-code-ohos-<version>.tgz
```

### 第 3 步：启用系统设置（仅需一次）

> **关键**：进入 **设置 > 隐私和安全 > 高级**
> 启用 **"运行来自非应用市场的扩展程序"**

这允许签名后的下载二进制文件（如 ripgrep）正常执行。

### 第 4 步：在 HiShell 中安装

```bash
npm install -g ~/Claude/claude-code.tgz
```

安装后脚本自动：
- 下载 ripgrep 并使用 `binary-sign-tool` 签名
- 将 `start-claude.sh` 安装到 `~/.claude/`
- 将 `.env.example` 安装到 `~/.claude/`

验证：
```bash
claude --version
# → 2.1.88-ohos.1 (Claude Code)
```

### 第 5 步：配置 API

```bash
cp ~/.claude/.env.example ~/.claude/.env
vi ~/.claude/.env
```

示例配置：
```bash
# LiteLLM 代理（GLM-5 / Qwen）
export ANTHROPIC_API_KEY='你的-api-key'
export ANTHROPIC_AUTH_TOKEN=''
export ANTHROPIC_BASE_URL='http://你的-litellm-host:端口'

# 模型配置
export ANTHROPIC_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_OPUS_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_SONNET_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='Qwen3.6-Plus'
```

### 第 6 步：运行

```bash
mkdir -p ~/Claude && cd ~/Claude
sh ~/.claude/start-claude.sh
```

## HarmonyOS 特定适配

### 1. `/tmp` 只读

HarmonyOS 的 `/tmp` 是只读的。启动脚本会重定向：
```bash
export CLAUDE_CODE_TMPDIR=$HOME/Claude/tmpdir
export TMPDIR=$HOME/Claude/tmpdir
```

### 2. TLS 证书问题

系统 CA 证书不完整。WebFetch 需设置：
```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

### 3. ripgrep 代码签名

Grep/Glob 工具依赖 ripgrep。安装后脚本自动：
1. 检测 musl libc
2. 下载静态链接的 AArch64 musl 构建版
3. 使用 `binary-sign-tool` 签名

### 4. SSH V8 JIT 崩溃

在 SSH 会话中运行时，V8 JIT 可能崩溃：
```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**解决方案**：使用 `--jitless` 模式 + `node-fetch` polyfill。

启动脚本 (`~/.claude/start-claude.sh`) 会自动检测 SSH 环境并应用解决方案。SSH 会话中使用：

```bash
# SSH 特定启动（如需要）
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js
```

详见 [dropbear-harmonyos.cn.md](dropbear-harmonyos.cn.md) 中 SSH 设置和 V8 崩溃解决方案。

### 5. 隐私设置（推荐）

使用第三方 API 代理时，在 `start-claude.sh` 中启用：
```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_SKIP_ANTHROPIC_ACCOUNT=1
export CLAUDE_CODE_SKIP_WEBFETCH_DOMAIN_CHECK=1
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_ATTRIBUTION_HEADER=0
```

## 已知限制

| 功能 | 状态 | 说明 |
|------|------|------|
| `claude --version` | ✅ 正常 | |
| `claude -p "..." --bare` | ✅ 正常 | 非交互式单提示 |
| Agent 模式 | ✅ 正常 | 自主文件编辑和命令执行 |
| 交互式 TUI | ✅ 正常 | 完整的 React 终端 UI |
| Grep / Glob 工具 | ✅ 正常 | 自动签名 ripgrep；需系统设置 |
| `/tmp` 目录 | ⚠️ 只读 | 通过 TMPDIR 重定向 |
| TLS 到 HTTPS | ⚠️ 受限 | 需要 `NODE_TLS_REJECT_UNAUTHORIZED=0` |
| SSH 会话 | ⚠️ V8 崩溃 | 使用 `--jitless` + polyfill |

## ripgrep 在 HarmonyOS 上

HarmonyOS 有一个内核级 bug：Node.js `child_process` 管道 stdout 捕获对已签名二进制返回空缓冲区。Claude Code 通过将 ripgrep 输出重定向到临时文件自动绕过此问题。

## 项目结构

```
HarmonyOS-Claude-Code/
├── package.json          # npm 包定义
├── cli.js                # 主入口点
├── start-claude.sh       # HarmonyOS 启动脚本
├── .env.example          # API 配置模板
├── ssh-fetch-polyfill.js # SSH V8 崩溃解决方案
├── src/                  # 源代码
├── npm-dist/             # npm 包输出
└── ohos-deploy/          # HarmonyOS 部署包
```

## 参考

- 项目地址：https://github.com/chenjh16/HarmonyOS-Claude-Code
- Releases：https://github.com/chenjh16/HarmonyOS-Claude-Code/releases
- 原始 Claude Code：https://github.com/anthropics/claude-code
- SSH V8 崩溃解决方案：[dropbear-harmonyos.cn.md](dropbear-harmonyos.cn.md)