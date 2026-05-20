# Node.js on HarmonyOS (DevNode-OH)

> **Chinese version**: nodejs-harmonyos.cn.md

## Overview

Node.js is available on HarmonyOS PC through **DevNode-OH**, a HarmonyOS-native Node.js distribution from the AppGallery.

**Version**: v24.13.0 (verified working)
**Source**: HarmonyOS AppGallery (DevNode-OH package)

## Installation

### Step 1: Install from AppGallery

1. Open **AppGallery (应用市场)** on HarmonyOS PC
2. Search for **DevNode-OH**
3. Install the application
4. Close and reopen **HiShell** terminal

### Step 2: Verify Installation

```bash
node -v
# → v24.13.0

npm -v
# → 10.x.x
```

### Step 3: Configure PATH

Add npm global bin to PATH:

```bash
echo 'export PATH=$(npm prefix -g)/bin:$PATH' >> $HOME/.zshrc
source $HOME/.zshrc
```

## System Requirements

### Privacy Settings (Critical)

Before running Node.js applications that download binaries (like Claude Code):

1. Open **Settings (设置)**
2. Navigate to **Privacy & Security (隐私和安全)**
3. Go to **Advanced (高级)**
4. Enable **"Run extensions from non-AppGallery sources" (运行来自非应用市场的扩展程序)**

This allows code-signed downloaded binaries to execute.

## Key Differences from Standard Node.js

### 1. /tmp Read-Only

HarmonyOS `/tmp` is read-only. Set TMPDIR:

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

For Node.js apps:
```bash
export NODE_TMPDIR=$HOME/Claude/tmpdir
```

### 2. TLS Certificate Issues

System CA certificates may be incomplete. For web requests:

```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**Warning**: This reduces security. Only use for development or trusted networks.

### 3. V8 JIT Crash in SSH Sessions

When running Node.js in SSH sessions, V8 JIT may crash:

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**Solution**: Use `--jitless` mode:

```bash
node --jitless your-app.js
```

See [dropbear-harmonyos.md](dropbear-harmonyos.md) for SSH setup and V8 crash workaround details.

## npm Usage

### Installing Global Packages

```bash
npm install -g <package>
```

Example packages verified working:
- `claude-code` (HarmonyOS port)
- `typescript`
- `eslint`

### Installing Local Packages

```bash
npm install <package>
```

### Using npm Mirrors

For faster downloads in China:

```bash
npm config set registry https://registry.npmmirror.com
```

## Verified Applications

| Application | Status | Notes |
|-------------|--------|-------|
| node -v | ✓ Working | v24.13.0 |
| npm install | ✓ Working | Global and local |
| Claude Code | ✓ Working | Requires HarmonyOS port |
| TypeScript | ✓ Working | tsc compiles correctly |
| V8 JIT | ⚠ SSH issue | Use --jitless in SSH |

## Troubleshooting

### "Permission denied" for downloaded binaries

1. Enable privacy setting (see above)
2. Ensure binary is code-signed:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned> -outFile <signed> \
  -signAlg SHA256withECDSA
```

### npm install fails with network error

1. Check proxy settings if using mihomo:
```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
```

2. Or use npm mirror:
```bash
npm config set registry https://registry.npmmirror.com
```

### Node.js crashes in SSH

Use `--jitless` flag:
```bash
node --jitless your-app.js
```

## Related Documentation

- [Claude Code for HarmonyOS](claude-code-harmonyos.md) — AI programming assistant
- [Dropbear SSH](dropbear-harmonyos.md) — SSH server with V8 crash workaround
- [mihomo](mihomo-harmonyos.md) — Proxy configuration

---

*Verified: 2026-05-20*
*Platform: HarmonyOS HongMeng Kernel 1.12.0*