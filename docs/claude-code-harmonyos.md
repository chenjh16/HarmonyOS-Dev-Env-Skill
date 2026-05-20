# Claude Code on HarmonyOS (aarch64) - Adaptation Guide

> **中文版本请查看 claude-code-harmonyos.cn.md**

## Overview

**Claude Code for HarmonyOS** is a port of Anthropic's Claude Code AI programming assistant, running natively on HarmonyOS 6.0 PC (AArch64, musl libc).

**Project**: https://github.com/chenjh16/HarmonyOS-Claude-Code
**Version**: 2.1.88-ohos.1 (based on Claude Code v2.1.88)

## Key Features

- **Interactive TUI** — Rich terminal interface with syntax highlighting, streaming responses
- **Agent Mode** — Autonomous coding with file editing, command execution, multi-step reasoning
- **Bare Mode** — Scriptable single-prompt interface for automation
- **40+ Built-in Tools** — File editing, grep, glob, bash, LSP, MCP, etc.
- **100+ Slash Commands** — Quick shortcuts for common tasks
- **MCP Support** — Extensible via Model Context Protocol servers
- **HarmonyOS Native** — Tested and verified on HarmonyOS 6.0 PC

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Node.js >= 20 | Install via DevNode-OH from AppGallery |
| npm global PATH | `export PATH=$(npm prefix -g)/bin:$PATH` |
| "Run extensions from non-AppGallery" | Settings > Privacy & Security > Advanced |

## Installation Steps

### Step 1: Install Node.js

1. Open **AppGallery** on HarmonyOS PC
2. Search and install **DevNode-OH**
3. Close and reopen **HiShell**
4. Verify: `node -v` → v24.13.0
5. Configure PATH:
   ```bash
   echo 'export PATH=$(npm prefix -g)/bin:$PATH' >> $HOME/.zshrc
   ```
6. Reopen HiShell

### Step 2: Get npm Package

**Option A: Download pre-built package**

From [Releases](https://github.com/chenjh16/HarmonyOS-Claude-Code/releases):
- Download `claude-code-ohos-<version>.tgz`
- Transfer to HarmonyOS PC (via cloud drive, IM, email, or hdc)

**Option B: Build from source (on Mac/Linux)**

```bash
git clone https://github.com/chenjh16/HarmonyOS-Claude-Code.git
cd HarmonyOS-Claude-Code
make npm-pack
# Output: npm-dist/claude-code-ohos-<version>.tgz
```

### Step 3: Enable System Setting (One-time)

> **Critical**: Go to **Settings > Privacy & Security > Advanced**
> Enable **"Run extensions from non-AppGallery"**

This allows signed downloaded binaries (like ripgrep) to execute.

### Step 4: Install in HiShell

```bash
npm install -g ~/Claude/claude-code.tgz
```

Postinstall script automatically:
- Downloads ripgrep and signs with `binary-sign-tool`
- Installs `start-claude.sh` to `~/.claude/`
- Installs `.env.example` to `~/.claude/`

Verify:
```bash
claude --version
# → 2.1.88-ohos.1 (Claude Code)
```

### Step 5: Configure API

```bash
cp ~/.claude/.env.example ~/.claude/.env
vi ~/.claude/.env
```

Example configuration:
```bash
# LiteLLM proxy (GLM-5 / Qwen)
export ANTHROPIC_API_KEY='your-api-key'
export ANTHROPIC_AUTH_TOKEN=''
export ANTHROPIC_BASE_URL='http://your-litellm-host:port'

# Model configuration
export ANTHROPIC_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_OPUS_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_SONNET_MODEL='GLM-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='Qwen3.6-Plus'
```

### Step 6: Run

```bash
mkdir -p ~/Claude && cd ~/Claude
sh ~/.claude/start-claude.sh
```

## HarmonyOS-Specific Adaptations

### 1. `/tmp` Read-only

HarmonyOS `/tmp` is read-only. The startup script redirects:
```bash
export CLAUDE_CODE_TMPDIR=$HOME/Claude/tmpdir
export TMPDIR=$HOME/Claude/tmpdir
```

### 2. TLS Certificate Issues

System CA certificates are incomplete. For WebFetch to work:
```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

### 3. ripgrep Code Signing

Grep/Glob tools depend on ripgrep. Postinstall automatically:
1. Detects musl libc
2. Downloads static AArch64 musl build
3. Signs with `binary-sign-tool`

### 4. SSH V8 JIT Crash

When running in SSH sessions, V8 JIT may crash:
```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**Solution**: Use `--jitless` mode + `node-fetch` polyfill.

The startup script (`~/.claude/start-claude.sh`) automatically detects SSH environment and applies workaround. For SSH sessions, use:

```bash
# SSH-specific startup (if needed)
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js
```

See [dropbear-harmonyos.md](dropbear-harmonyos.md) for SSH setup and V8 crash details.

### 5. Privacy Settings (Recommended)

For third-party API proxies, enable in `start-claude.sh`:
```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_SKIP_ANTHROPIC_ACCOUNT=1
export CLAUDE_CODE_SKIP_WEBFETCH_DOMAIN_CHECK=1
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_ATTRIBUTION_HEADER=0
```

## Known Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| `claude --version` | ✅ Works | |
| `claude -p "..." --bare` | ✅ Works | Non-interactive single prompt |
| Agent Mode | ✅ Works | Autonomous file editing and command execution |
| Interactive TUI | ✅ Works | Full React terminal UI |
| Grep / Glob tools | ✅ Works | Auto-signed ripgrep; requires system setting |
| `/tmp` directory | ⚠️ Read-only | Redirected via TMPDIR |
| TLS to HTTPS | ⚠️ Limited | `NODE_TLS_REJECT_UNAUTHORIZED=0` needed |
| SSH sessions | ⚠️ V8 crash | Use `--jitless` + polyfill |

## ripgrep on HarmonyOS

HarmonyOS has a kernel-level bug: Node.js `child_process` pipe stdout capture returns empty buffer for signed binaries. Claude Code automatically bypasses this by redirecting ripgrep output to temp file.

## Project Structure

```
HarmonyOS-Claude-Code/
├── package.json          # npm package definition
├── cli.js                # Main entry point
├── start-claude.sh       # HarmonyOS startup script
├── .env.example          # API configuration template
├── ssh-fetch-polyfill.js # SSH V8 crash workaround
├── src/                  # Source code
├── npm-dist/             # npm package output
└── ohos-deploy/          # HarmonyOS deployment package
```

## References

- Project: https://github.com/chenjh16/HarmonyOS-Claude-Code
- Releases: https://github.com/chenjh16/HarmonyOS-Claude-Code/releases
- Original Claude Code: https://github.com/anthropics/claude-code
- SSH V8 crash workaround: [dropbear-harmonyos.md](dropbear-harmonyos.md)