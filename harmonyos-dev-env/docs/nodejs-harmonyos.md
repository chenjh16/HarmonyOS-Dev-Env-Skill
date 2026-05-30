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

## Verified Packages (E2E Tests)

| Package | Version | Status | Notes |
|---------|---------|--------|-------|
| better-sqlite3 | 12.10.0 | ✓ Working | Full CRUD, prepared statements, parameter binding |
| bcrypt | 6.0.0 | ✓ Working | hashSync, compareSync both functional |
| argon2 | 0.41.1 | ✓ Working | argon2id hash + verify, async API |
| sqlite3 | 5.1.0 | ✓ Working | verbose mode, async DB operations |
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
| typescript | 6.0.3 | ✓ Working | tsc compilation, type checking, interfaces, generics, async/await |
| esbuild | 0.28.0 | ✓ Working | Transform API, bundling (WASM32 native binary) |
| prettier | 3.8.3 | ✓ Working | Code formatting |
| eslint | 10.4.0 | ✓ Working | Linting |
| @modelcontextprotocol/sdk | 1.29.0 | ✓ Working | Server creation, tool/resource/prompt handler registration, StdioServerTransport, Client creation — 6/6 e2e tests (ESM sub-module imports) |
| @anthropic-ai/sdk | 0.100.1 | ✓ Working | SDK instance creation works (API client) |
| koa | 2.16.1 | ✓ Working | Koa app creation, middleware, route handling |
| fastify | 5.4.0 | ✓ Working | Fastify server creation, route registration, plugin system |
| cheerio | 1.0.0 | ✓ Working | HTML parsing, selector, text extraction |
| winston | 3.17.0 | ✓ Working | Logger creation, multiple transports (console, file) |
| helmet | 8.1.0 | ✓ Working | Express/Koa middleware for HTTP security headers |
| cors | 2.8.5 | ✓ Working | Express/Koa CORS middleware |
| nodemailer | 7.0.5 | ✓ Working | Email transport creation, message object |
| node-cron | 3.0.3 | ✓ Working | Task scheduling, cron expression validation |
| multer | 2.0.2 | ✓ Working | File upload middleware |
| body-parser | 1.20.3 | ✓ Working | JSON/urlencoded body parsing |

**Core modules**: All 14 tested (fs, crypto, http, net, os, path, child_process, worker_threads, stream, url, Intl, SQLite built-in, async/await, ESM) — 100% pass rate.

**Total**: 41/41 e2e tests passed (100%) (32 packages + 14 core modules, added MCP SDK + Anthropic SDK + koa/fastify/cheerio/winston/helmet/cors/nodemailer/node-cron/multer/body-parser).

### Verified Packages (Import Test)

The following packages were verified to load and import correctly. Full e2e functionality was not tested (e.g., next.js was not run as a server).

| Package | Version | Status | Notes |
|---------|---------|--------|-------|
| next.js | 16.2.6 | ✓ Import | Module loads; not tested as server |
| react | 19.2.6 | ✓ Import | Module loads |
| postcss | 8.5.15 | ✓ Import | CSS parsing works |
| autoprefixer | 10.5.0 | ✓ Import | Module loads |
| tailwindcss | 4.3.0 | ✓ Import | Module loads |

## Known Issues

### 1. chalk v5 ESM-only

chalk v5.6.2 uses `"type": "module"` in package.json. `require('chalk')` returns empty object (no methods). Use chalk v4 (CJS-compatible) or dynamic `import()` in ESM context.

### 2. sharp — WASM32 Fallback Works

sharp has no prebuilt binary for `openharmony-arm64`, but the WASM32 mode works as a functional (though slower) fallback:

```bash
npm install sharp
npm install --force @img/sharp-wasm32
```

sharp automatically detects the WASM32 module and uses it. All operations (resize, format conversion, metadata, stats) work correctly. Performance is ~5-10x slower than native libvips.

### 3. node-gyp V8 Crash with Unsigned Node

When using the **unsigned** system Node (`/data/service/hnp/bin/node`), node-gyp's configure step crashes with V8 `Check failed: 12 == (*__errno_location())` (Signal 5/SIGTRAP). This is resolved when using the **signed** Node binary.

### 4. canvas — Missing C Dependencies

canvas requires pixman/cairo system libraries not available on HarmonyOS. Would need manual compilation of these C dependencies first.

### 5. jest 30.4.2 — Package Exports Error

jest fails with `ERR_PACKAGE_PATH_NOT_EXPORTED` when loading the `jest-circus` runner module. The `runner.js` file exists in the package, but Node v24's exports system prevents loading it correctly. This is a Node v24 + jest compatibility issue, **not** HarmonyOS-specific. Use vitest as an alternative test framework (fully working on HarmonyOS).

### 6. @swc/core — Platform Check Rejection

@swc/core explicitly checks `process.platform` and returns: "Unsupported OS: openharmony, architecture: arm64". It uses pre-compiled Rust native binaries per platform (linux-x64-gnu, linux-arm64-gnu, etc.) — there is no openharmony build available. No workaround unless SWC project adds an openharmony target.

### 7. prisma 7.8.0 — ABI Incompatible Binary

prisma's schema engine is a pre-compiled glibc binary (debian-openssl-1.1.x). Even after code-signing, it fails with `ENOEXEC` error because the binary is linked against glibc, which is ABI incompatible with musl libc on HarmonyOS. glibc-linked binaries cannot run on musl systems.

### 8. canvas (Node.js) — Missing C Dependencies

Same issue as Python canvas: requires pixman/cairo system libraries not available on HarmonyOS. Would need manual compilation of these C dependencies first.

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

*Verified: 2026-05-29*
*Platform: HarmonyOS HongMeng Kernel 1.12.0*
*E2E Tests: 41/41 passed (100%) — 10 new: koa, fastify, cheerio, winston, helmet, cors, nodemailer, node-cron, multer, body-parser*
*Import Tests: 5 verified — next.js, react, postcss, autoprefixer, tailwindcss*
*Failed: 4 packages — jest (exports error), @swc/core (platform check), prisma (glibc ABI), canvas (C deps)*