---
name: harmonyos-dev-env
description: HarmonyOS PC development environment skill pack. Provides complete platform knowledge (code signing, read-only /tmp, no gcc, ld.bfd wrapper, LD_LIBRARY_PATH ordering) and toolchain adaptation guides (Python, Rust, Go, PyTorch, llama.cpp, OpenSSH, etc.). Use when building, compiling, or configuring any software on HarmonyOS, or when user mentions "鸿蒙", "HarmonyOS", "HongMeng", or any HarmonyOS-specific issue. Read docs/ files for detailed build guides when needed.
always-enable: true
---

# HarmonyOS PC Development Environment Skill Pack

### Critical Platform Rules

1. **Code Signing**: ALL ELF binaries (executables + .so) MUST be signed with `binary-sign-tool sign -selfSign 1 -inFile <unsigned> -outFile <signed> -signAlg SHA256withECDSA` before execution. Unsigned binaries crash immediately.

2. **/tmp is read-only**: Use `$HOME/Claude/tmpdir` instead. Override `TMPDIR`, `os.tmpname()`, `io.tmpfile()` in all build systems.

3. **No gcc**: Only clang 15.0.4 at `/data/service/hnp/bin/clang`. Set `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` for all builds.

4. **SDK lld is broken**: Requires `libxml2.so.16` which doesn't exist. Create ld.bfd wrapper:
   ```bash
   mkdir -p $HOME/Claude/lib/linker_wrapper
   cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
   #!/bin/sh
   exec /data/service/hnp/bin/ld.bfd "$@"
   EOF
   chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
   ```
   Add `-B$HOME/Claude/lib/linker_wrapper` to all clang compilation commands.

5. **LD_LIBRARY_PATH order**: `/usr/lib` MUST come before `$HOME/.rust/lib` to avoid OpenSSL symbol version conflicts (OPENSSL_3.0.0 vs OPENSSLOH_3.0.0).

6. **make -j fails**: `mkfifo` returns "Operation not permitted" — use Ninja for parallel builds.

7. **CMAKE_TOOLCHAIN_FILE + CMAKE_SYSTEM_NAME**: Do NOT combine — triggers cross-compile mode, breaking `try_run()`. Pass compiler flags directly via `-DCMAKE_C_COMPILER` and `-DCMAKE_CXX_COMPILER`.

8. **SSH V8 crash**: HarmonyOS PTY + V8 JIT crashes (ENOMEM). Use `node --jitless` + `node-fetch` polyfill for SSH sessions.

9. **OpenSSH passwd_compat**: sshd requires `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so` because uid 20020106 is not in /etc/passwd (read-only). Child env must preserve LD_PRELOAD/LD_LIBRARY_PATH (patch session.c).

10. **OpenSSH abstract socket**: ssh-agent bind() returns EPERM for filesystem Unix sockets. Uses abstract namespace fallback (`SSH_AUTH_SOCK=abstract:<name>`).

11. **OpenSSH authorized_keys UID**: Files owned by uid 20001006 (file_manager), processes run as uid 20020106. `platform_sys_dir_uid()` accepts 20001006 as system owner. `safe_path()` skips mode check for system-owned files. StrictModes=yes works.

12. **Dropbear -e flag**: Must start dropbear with `-e` flag to pass parent env to child sessions (LD_LIBRARY_PATH, PATH, etc.).

13. **musl libc**: No `crypt()` (no password auth), no `strerror_r` (errno crate needs patch), limited locale support, `__assert_fail` uses `int line` without `noexcept`.

14. **Python -rdynamic**: Our Python exports 948+ Py symbols via `-rdynamic`, enabling signed .so extension modules from user paths. No need for static-only extensions.

15. **Node.js dlopen signing**: HNP Node binary has NO .codesign section → kernel blocks `process.dlopen()` for user-space .node/.so files. Fix: create signed copy (`binary-sign-tool sign -selfSign 1`) at `$HOME/.local/bin/node-harmonyos`, put `$HOME/.local/bin` first in PATH. Native addons need: `patchelf --add-needed libc++_shared.so` + code signing. Use `sign-node-addon.sh` script for automation.

16. **psutil HarmonyOS patch**: `sys.platform.startswith("harmonyos")` should be treated as Linux. Patch `_common.py`: add `or sys.platform.startswith("harmonyos")` to LINUX check. Patch `net.c`: `#define sockaddr_storage __guard` before `#include <linux/if.h>` then `#undef` (prevent redefinition conflict).

17. **maturin direct build**: pip build isolation breaks maturin on HarmonyOS. Build Rust/PyO3 packages directly with `maturin build --release --interpreter $HOME/.local/bin/python3`, then sign .so, rename suffix to `.cpython-312-aarch64-linux-gnu.so`, install manually to site-packages.

18. **Meson auto-sign wrapper**: Create clang wrapper at `$HOME/Claude/lib/meson_wrapper/clang` that auto-signs all ELF outputs (including PIE/DYN type). Use as CC in meson native.ini. Build with mesonpy Python API.

19. **sharp WASM32 fallback**: `npm install --force @img/sharp-wasm32`. Works for all operations, ~5-10x slower than native.

### Toolchain Quick Reference

| Tool | Version | Install Path | Key Feature |
|------|---------|-------------|-------------|
| Python | 3.12.8 | `$HOME/.local` | pip, -rdynamic, numpy, pillow, lxml, psutil, pydantic v2, pandas |
| Node.js | 24.13.0 | `$HOME/.local/bin` | Signed binary, native addons, sharp WASM32, MCP SDK, 61 packages, 66 e2e tests |
| Rust | 1.95.0 | `$HOME/.rust` | aarch64-unknown-linux-ohos target |
| Go | 1.22.5 | `$HOME/Claude/go-build/go` | GOPROXY=goproxy.cn |
| PyTorch | 2.5.1 | `$HOME/.local/lib/.../torch` | LAPACK, NumPy, 15/15 tests |
| llama.cpp | b9073 | `$HOME/Claude/llama.cpp/build/bin` | NEON/SVE, ~4x prompt eval boost |
| mihomo | Meta | `$HOME/Claude/mihomo-build/bin` | HTTP/SOCKS5, GEOIP/GEOSITE |
| Dropbear | 2024.86 | `$HOME/.local/bin` | pubkey only, -e flag, 5 patches |
| OpenSSH | 9.9p1 | `$HOME/Claude/openssh-build/openssh-prefix/bin` | 16 patches, scp/sftp/ssh-agent |
| eza | 0.23.4 | `$HOME/Claude/eza-build/.../release` | modern ls |
| bat | 0.26.1 | `$HOME/Claude/bat-build/.../release` | syntax-highlighted cat |
| starship | 1.25.1 | `$HOME/Claude/starship-build/.../release` | cross-shell prompt |
| Claude Code | 2.1.88-ohos.1 | npm global | HarmonyOS native, ripgrep auto-signing |

### Adaptation Guide Locations

Full build guides are in this skill's `docs/` directory. When the user asks about a specific tool, read the corresponding guide using the Read tool with relative path from this SKILL.md's directory:

- `docs/python-harmonyos.md` — Python 3.12.8 standalone build
- `docs/python-packages-harmonyos.md` — 97 packages tested (cchardet, msgpack, pycryptodome, bcrypt, loguru, pygments, httpx, pytest, mcp, rpds-py, tiktoken, lz4, zstd, hiredis all work; scipy/uvloop/polars/orjson/tokenizers cannot build), solutions for C/Rust/Meson extensions
- `docs/python-extension-adaptation.md` — **General guide for adapting C/Rust/C++/Meson Python packages**
- `docs/rust-harmonyos.md` — Rust ohos target installation
- `docs/pytorch-harmonyos.md` — PyTorch v2.5.1, 15/15 e2e tests
- `docs/openssh-harmonyos.md` — OpenSSH 9.9p1, 16 patches
- `docs/dropbear-harmonyos.md` — Dropbear, 5 patches, V8 crash
- `docs/llama-cpp-harmonyos.md` — NEON/SVE optimization, Qwen3.5
- `docs/claude-code-harmonyos.md` — Claude Code ohos adaptation
- `docs/nodejs-harmonyos.md` — **Node.js dlopen fix, native addon signing, sharp WASM32, MCP SDK + Anthropic SDK, ramda/zod/ajv/ioredis/pg/jsonwebtoken, 61 packages, 66 e2e tests**
- `docs/mihomo-harmonyos.md` — HTTP/SOCKS5, GEOIP/GEOSITE
- `docs/eza-harmonyos.md` — modern ls
- `docs/bat-harmonyos.md` — syntax-highlighted cat
- `docs/starship-harmonyos.md` — cross-shell prompt
- `docs/code-signing.md` — ELF/HAP signing guide
- `docs/ld-library-path.md` — LD_LIBRARY_PATH ordering
- `docs/selinux-analysis.md` — .so loading root cause
- `docs/ipc-feasibility.md` — Native child process API
- `docs/troubleshooting.md` — consolidated problem-solving

Tool build guides with install scripts are in `tools/`:
- `tools/python/`, `tools/rust/`, `tools/go/`, `tools/llama-cpp/`, `tools/mihomo/`, `tools/dropbear/`, `tools/openssh/`, `tools/pytorch/`, `tools/bat/`, `tools/eza/`, `tools/starship/`

### Quick Commands

```bash
# One-time environment setup (creates $HOME/Claude base dir, tmpdir, linker wrapper, copies zshenv)
# $HOME/Claude is the convention directory for all toolchain installs — env-setup.sh creates it
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh

# Batch code signing for a directory
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-all.sh <directory>

# Sign a Node.js native addon (.node file)
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-node-addon.sh <path-to-.node>

# Verify environment (checks all toolchains)
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```