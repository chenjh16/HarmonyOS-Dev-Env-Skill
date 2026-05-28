# Node.js on HarmonyOS (DevNode-OH)

> **Chinese version**: nodejs-harmonyos.cn.md

## Overview

Node.js v24.13.0 is available on HarmonyOS PC through **DevNode-OH** (AppGallery) and the **HNP package** (`/data/service/hnp/node.org/node_v24.13.0/`).

**Version**: v24.13.0
**npm**: 11.6.2
**Platform**: `openharmony` / `arm64`
**Source**: HarmonyOS AppGallery (DevNode-OH) + HNP package

## Critical Issue: process.dlopen Blocked for User-Space Libraries

### The Problem

The HNP-packaged Node.js binary (`/data/service/hnp/node.org/node_v24.13.0/bin/node`) has **no .codesign section**. HarmonyOS kernel enforces a security policy where **unsigned processes can only dlopen() libraries from system paths** (`/system/lib64`, `/usr/lib`). This means `process.dlopen()` — used by ALL native addon packages (bcrypt, better-sqlite3, canvas, etc.) — returns `ERR_DLOPEN_FAILED` with "Permission denied" for any `.node` or `.so` file in user-writable directories.

**Evidence**:
- `better-sqlite3.node`: "Permission denied" (ERR_DLOPEN_FAILED)
- `libffi.so.8` (user-compiled): "Permission denied"
- Same files load successfully via Python `ctypes.CDLL()` and standalone C `dlopen()`

**Root Cause**: The restriction is NOT in Node.js source code (which uses standard `dlopen()` on POSIX). It's a HarmonyOS kernel-level enforcement: unsigned ELF processes are restricted to system-path dlopen only.

### The Fix: Add .codesign to Node Binary

**No rebuild from source is needed.** Simply add a `.codesign` section to the Node binary:

```bash
# Create signed copy in user space
cp /data/service/hnp/node.org/node_v24.13.0/bin/node $HOME/.local/bin/node-harmonyos

/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/node-harmonyos \
  -outFile $HOME/.local/bin/node-harmonyos.signed \
  -signAlg SHA256withECDSA

mv $HOME/.local/bin/node-harmonyos.signed $HOME/.local/bin/node-harmonyos
chmod +x $HOME/.local/bin/node-harmonyos

# Create symlink so it's picked up by PATH
ln -sf node-harmonyos $HOME/.local/bin/node
```

**Ensure `$HOME/.local/bin` comes before `/data/service/hnp/bin` in PATH** so npm/npx also use the signed Node binary.

## Native Addon Build & Sign Workflow

### Step 1: Compile with HarmonyOS Toolchain

```bash
export PATH=$HOME/.local/bin:$PATH  # Signed Node first
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export CFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export CXXFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export TMPDIR=$HOME/Claude/tmpdir

npm install <native-addon-package>
```

**Note**: The `-B$HOME/Claude/lib/linker_wrapper` flag is **essential** — without it, clang invokes the broken `lld` linker which requires `libxml2.so.16` (not available on HarmonyOS).

### Step 2: Sign & Patch the .node File

All `.node` files (ELF shared objects) need two modifications:

1. **Add `libc++_shared.so` dependency** — C++ addons need C++ runtime symbols (`_Znwm` / operator new) that Node doesn't export
2. **Add `.codesign` section** — Required for `process.dlopen` to load from user space

Use the automated script:

```bash
$HOME/.local/bin/sign-node-addon <path-to-.node-file>
```

Or manually:

```bash
# Remove existing .codesign (patchelf can't modify signed files)
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign \
  addon.node addon_unsigned.node

# Add libc++_shared.so dependency
/data/service/hnp/bin/patchelf --add-needed libc++_shared.so addon_unsigned.node

# Sign
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile addon_unsigned.node -outFile addon_signed.node

# Replace original
cp addon_signed.node addon.node
chmod 775 addon.node
```

**Batch signing** for all .node files in a project:

```bash
find node_modules -name "*.node" -type f -exec \
  $HOME/.local/bin/sign-node-addon {} \;
```

## Verified Native Addons (E2E Tests)

| Package | Version | Status | Notes |
|---------|---------|--------|-------|
| better-sqlite3 | 12.10.0 | ✓ Working | Full CRUD, prepared statements, parameter binding |
| bcrypt | 6.0.0 | ✓ Working | hashSync, compareSync both functional |
| express | 5.2.1 | ✓ Working | HTTP server, JSON responses |
| lodash | 4.18.1 | ✓ Working | All utility functions |
| axios | 1.16.1 | ✓ Working | HTTP client, external HTTPS requests |
| dayjs | 1.11.21 | ✓ Working | Date formatting |
| uuid | 14.0.0 | ✓ Working | v4 generation |
| commander | 14.0.3 | ✓ Working | CLI argument parsing |
| dotenv | 17.4.2 | ✓ Working | .env loading |
| jsdom | 29.1.1 | ✓ Working | DOM manipulation |
| ws | 8.21.0 | ✓ Working | WebSocket server/client |
| rxjs | 7.8.2 | ✓ Working | Observable, of() |
| socket.io | 4.8.3 | ✓ Working | Real-time bidirectional |
| vitest | 4.1.7 | ✓ Working | Test framework (ESM import) |

**Core modules**: All 14 tested (fs, crypto, http, net, os, path, child_process, worker_threads, stream, url, Intl, SQLite built-in, async/await, ESM) — 100% pass rate.

**Total**: 23/23 e2e tests passed (100%).

## Known Issues

### 1. chalk v5 ESM-only

chalk v5.6.2 uses `"type": "module"` in package.json. `require('chalk')` returns empty object (no methods). Use chalk v4 (CJS-compatible) or dynamic `import()` in ESM context.

### 2. sharp — No Prebuilt Binary

sharp requires libvips prebuilt binaries. No binary exists for `openharmony-arm64`. The WASM fallback also fails (npm enforces `cpu=wasm32` matching). Would require building libvips from source first.

### 3. node-gyp V8 Crash with Unsigned Node

When using the **unsigned** system Node (`/data/service/hnp/bin/node`), node-gyp's configure step crashes with V8 `Check failed: 12 == (*__errno_location())` (Signal 5/SIGTRAP). This is resolved when using the **signed** Node binary.

### 4. canvas — Missing C Dependencies

canvas requires pixman/cairo system libraries not available on HarmonyOS. Would need manual compilation of these C dependencies first.

## Key Differences from Standard Node.js

### 1. /tmp Read-Only

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

Node.js respects `TMPDIR` — `os.tmpdir()` returns `$HOME/Claude/tmpdir`.

### 2. TLS Certificate Issues

```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**Warning**: This reduces security. Only use for development or trusted networks.

### 3. V8 JIT Crash in SSH Sessions

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**Solution**: Use `--jitless` mode:
```bash
node --jitless your-app.js
```

See [dropbear-harmonyos.md](dropbear-harmonyos.md) for SSH setup and V8 crash workaround details.

### 4. process.platform = "openharmony"

`process.platform` returns `openharmony` (not `linux`). This may affect packages that check for specific platforms. Consider patching via sitecustomize.js (similar to Python's approach for maturin).

## Privacy Settings (Critical)

Before running Node.js applications that download binaries:

1. Open **Settings (设置)**
2. Navigate to **Privacy & Security (隐私和安全)**
3. Go to **Advanced (高级)**
4. Enable **"Run extensions from non-AppGallery sources"**

## Related Documentation

- [Code Signing](code-signing.md) — Detailed code signing instructions
- [LD_LIBRARY_PATH](ld-library-path.md) — Dynamic library path configuration
- [Python Extension Adaptation](python-extension-adaptation.md) — General .so adaptation patterns
- [Dropbear SSH](dropbear-harmonyos.md) — SSH server with V8 crash workaround
- [SELinux Analysis](selinux-analysis.md) — HarmonyOS security enforcement analysis

---

*Verified: 2026-05-28*
*Platform: HarmonyOS HongMeng Kernel 1.12.0*
*E2E Tests: 23/23 passed (100%)*