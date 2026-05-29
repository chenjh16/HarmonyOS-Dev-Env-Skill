# HarmonyOS Development Environment - Global Rules

> **Note**: This file (`CLAUDE.md`) is the English version. A Chinese version (`CLAUDE.cn.md`) must be maintained in parallel. When editing this file, update the Chinese version correspondingly.

## Platform: HarmonyOS (HongMeng Kernel 1.12.0, aarch64)

### Filesystem & Permissions

- `/tmp` is **read-only** on this system — do NOT use it for temp files, builds, or os.tmpname()
- The writable temp directory is `$HOME/Claude/tmpdir/` — use this instead of /tmp
- When overriding `os.tmpname` in Lua or other scripts, redirect output to `$HOME/Claude/tmpdir/`
- `io.tmpfile()` (C stdlib tmpfile) returns NULL on HarmonyOS — use fallback: fopen in writable dir then unlink
- User home is `$HOME/` (not /home/)

### Code Signing (CRITICAL)

- **All ELF binaries must be signed before execution** — this includes:
  - Compiled C/C++ programs (clang output)
  - Go compiled binaries
  - Rust compiled binaries
  - Python extension modules (.so files)
  - Any executable you build from source

**Signing command**:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

For development/testing, use `-selfSign 1`. For production, use proper certificates.

**Quick test**: After signing, verify:
```bash
/data/service/hnp/bin/binary-sign-tool display-sign -inFile <binary>
```

See code-signing.md for full documentation (in skill's `docs/` directory).

### Toolchain (no gcc available)

- **CC**: `/data/service/hnp/bin/clang` (clang 15.0.4, aarch64-unknown-linux-ohos target)
- **AR**: `/data/service/hnp/bin/ar`
- **RANLIB**: `/data/service/hnp/bin/ranlib`
- **MAKE**: `/data/service/hnp/bin/make`
- **CMAKE**: `/data/service/hnp/bin/cmake`
- **NINJA**: `/data/service/hnp/bin/ninja`
- **LD**: `/data/service/hnp/bin/ld.lld` — **BROKEN** (requires libxml2.so.16 which doesn't exist)
- **STRIP**: `/data/service/hnp/bin/llvm-strip`
- **NM**: `/data/service/hnp/bin/llvm-nm`
- **OBJCOPY**: `/data/service/hnp/bin/llvm-objcopy`
- **OBJDUMP**: `/data/service/hnp/bin/llvm-objdump`
- **READELF**: `/data/service/hnp/bin/llvm-readelf`
- **GDB**: `/data/service/hnp/bin/gdb`
- **LLDB**: `/data/service/hnp/bin/lldb`
- No `gcc` is available — always use clang. Do NOT write Makefiles that default to gcc.
- Clang triplet targets: `aarch64-unknown-linux-ohos-clang`, `armv7-unknown-linux-ohos-clang`
- **`make -j` fails on HarmonyOS**: mkfifo returns "Operation not permitted" (jobserver uses mkfifo for parallel builds). Use Ninja instead.
- **Do NOT use CMAKE_TOOLCHAIN_FILE with CMAKE_SYSTEM_NAME**: triggers CMake cross-compilation mode causing try_run() failures. Use lightweight toolchain file (only compilers + linker wrapper, no CMAKE_SYSTEM_NAME) or pass compiler flags directly.
- **OpenBLAS/LAPACK**: Compile OpenBLAS v0.3.28 with NOFORTRAN=1; modify Makefile.prebuild for -B wrapper + code signing; create .so from .a; set LAPACK_LIBRARIES and LAPACK_FOUND explicitly in CMake
- **Sleef NATIVE_BUILD_DIR**: Modify sleef CMakeLists.txt add_host_executable to use NATIVE_BUILD_DIR when provided, even without CMAKE_CROSSCOMPILING
- **CMake 4.1.2 ldd**: CMake 4.1.2 runs ldd after linking; copy ldd wrapper to ~/.local/bin/ldd

**CRITICAL**: SDK's lld linker requires `libxml2.so.16` which doesn't exist on HarmonyOS. You MUST use ld.bfd instead by creating a wrapper:

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

Then add `-B$HOME/Claude/lib/linker_wrapper` to all clang compilation commands, or set in CMake:
```cmake
set(CMAKE_C_FLAGS "-B$HOME/Claude/lib/linker_wrapper")
set(CMAKE_CXX_FLAGS "-B$HOME/Claude/lib/linker_wrapper")
```
- **Rust**: `rustc 1.95.0` (aarch64-unknown-linux-ohos) at `$HOME/.rust/bin/`; `cargo 1.95.0` (musl) at same path; must use `-C linker=/data/service/hnp/bin/clang`; all ELF binaries must be code-signed before execution
- **Node.js**: v24.13.0; **CRITICAL**: HNP Node binary (`/data/service/hnp/bin/node`) has NO .codesign section → kernel blocks `process.dlopen()` for user-space .node/.so files. Fix: use signed copy at `$HOME/.local/bin/node-harmonyos` (with .codesign section); `$HOME/.local/bin` must come first in PATH. For native addons (bcrypt, better-sqlite3, etc.): compile with `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ CFLAGS="-B$HOME/Claude/lib/linker_wrapper"`, then `patchelf --add-needed libc++_shared.so <.node>` + `binary-sign-tool sign -selfSign 1`; use `sign-node-addon.sh` script for automation. Claude Code SSH sessions require `node --jitless` + node-fetch polyfill due to HarmonyOS PTY + V8 JIT crash. **29/29 e2e tests passed** (better-sqlite3, bcrypt, express, lodash, axios, dayjs, uuid, jsdom, ws, rxjs, socket.io, vitest, typescript, esbuild, prettier, eslint, all core modules)
- **llama.cpp**: built at `$HOME/Claude/llama.cpp/build/bin/`; `llama-cli`, `llama-server`, `llama-quantize` etc. available
- **eza**: v0.23.4 at `$HOME/Claude/eza-build/eza/target/release/`; modern `ls` replacement with colors, icons, tree view
- **bat**: v0.26.1 at `$HOME/Claude/bat-build/bat/target/release/`; `cat` clone with syntax highlighting
- **starship**: v1.25.1 at `$HOME/Claude/starship-build/starship/target/release/`; cross-shell prompt
- **Go**: v1.22.5 at `$HOME/Claude/go-build/go/`; use `GOPROXY=https://goproxy.cn,direct`; set `TMPDIR=$HOME/Claude/tmpdir`
- **mihomo**: Clash Meta proxy at `$HOME/Claude/mihomo-build/bin/mihomo-linux-arm64`; config at `$HOME/Claude/mihomo-config/`; proxy port 7890, API port 9090; supports GEOIP/GEOSITE intelligent routing
- **PyTorch**: v2.5.1 at `$HOME/.local/lib/python3.12/site-packages/torch/`; **15/15 e2e tests passed** (all functional: NumPy fixed via post-build patch, LAPACK enabled via OpenBLAS + supplement.so); requires `LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH`; build must use Ninja (not `make -j` which fails due to mkfifo); do NOT use CMAKE_TOOLCHAIN_FILE with CMAKE_SYSTEM_NAME; use lightweight toolchain file; OpenBLAS v0.3.28 at `$HOME/.local/lib/libopenblas.so`; `libtorch_supplement.so` provides 3 hidden symbols (decref/incref/invoke_parallel); patchelf needed to fix NEEDED path prefixes
- **Dropbear**: v2024.86 SSH server/client at `$HOME/.local/bin/`; `dropbear` (server), `dbclient` (client), `dropbearkey` (key generation); pubkey auth only (no password auth due to missing crypt()); any non-system username accepted (chenh, user, currentUser, UID all work — single-user device); **must use `-e` flag** (passes env vars to child sessions); PTY interactive sessions limited (TIOCSCTTY fails on HarmonyOS)
- **OpenSSH**: 9.9p1 at `$HOME/Claude/openssh-build/openssh-prefix/bin`; `ssh`, `sshd`, `scp`, `sftp`, `ssh-add`, `ssh-agent`, `ssh-keygen`, `ssh-keyscan`; requires `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so`; ssh-agent uses abstract namespace sockets (`SSH_AUTH_SOCK=abstract:<name>`); scp/sftp work with `SetEnv PATH` in sshd_config; all 16 HarmonyOS patches applied; **authorized_keys UID**: files owned by uid 20001006 (file_manager), sshd runs as uid 20020106 — `platform_sys_dir_uid()` accepts 20001006 as system owner, `safe_path()` skips mode check for system-owned files, StrictModes=yes works

### Third-party tools in PATH

All third-party toolchains are configured in `$HOME/.zshenv` and auto-loaded on shell startup:
- Rust: `$HOME/.rust/bin` → `rustc`, `cargo`
- llama.cpp: `$HOME/Claude/llama.cpp/build/bin` → `llama-cli`, `llama-server`, etc.
- eza: `$HOME/Claude/eza-build/eza/target/release` → `eza`
- bat: `$HOME/Claude/bat-build/bat/target/release` → `bat`
- starship: `$HOME/Claude/starship-build/starship/target/release` → `starship`
- Dropbear: `$HOME/.local/bin` → `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`
- OpenSSH: `$HOME/Claude/openssh-build/openssh-prefix/bin` → `ssh`, `sshd`, `scp`, `sftp`, `ssh-add`, `ssh-agent`, `ssh-keygen`, `ssh-keyscan`; requires `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so`; ssh-agent uses abstract namespace sockets (`SSH_AUTH_SOCK=abstract:<name>`)
- `LD_LIBRARY_PATH` includes `$HOME/.rust/lib`, `/system/lib64`, and llama.cpp bin dir
- `LD_PRELOAD` set to `$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so` (for OpenSSH sshd)
- `SSL_CERT_FILE` set to `$HOME/.rust/cacert.pem` (for cargo crates.io access)
- `TMPDIR` set to `$HOME/Claude/tmpdir` (because `/tmp` is read-only on HarmonyOS)

**CRITICAL**: `/usr/lib` must come before `$HOME/.rust/lib` in LD_LIBRARY_PATH to avoid OpenSSL symbol version conflicts. See ld-library-path.md for details (in skill's `docs/` directory).

### Code Signing

- **ELF signing**: `/data/service/hnp/bin/binary-sign-tool`
  - Commands: `sign`, `display-sign`
  - Sign algorithm: SHA256withECDSA or SHA384withECDSA
  - Required params: `-keyAlias`, `-appCertFile`, `-profileFile`, `-inFile`, `-outFile`, `-keystoreFile`, `-signAlg`
  - Self-sign option: `-selfSign 1` for local testing
  - Example: `binary-sign-tool sign -keyAlias "key" -appCertFile cert.cer -profileFile profile.p7b -inFile unsigned.elf -outFile signed.elf -keystoreFile keystore.p12 -signAlg SHA256withECDSA`

- **HAP/App signing**: `/data/service/hnp/bin/hap-sign-tool`
  - Commands: `generate-keypair`, `generate-csr`, `generate-cert`, `generate-ca`, `generate-app-cert`, `generate-profile-cert`, `sign-profile`, `verify-profile`, `sign-app`, `verify-app`
  - Key algorithm: ECC (NIST-P-256 / NIST-P-384)

### Device Deployment

- **hdc** (HarmonyOS Device Connector): `/data/service/hnp/bin/hdc` (v3.1.0e)
  - Similar to adb for Android — used for app install, file push, shell access, debugging

### Kernel & Runtime Differences

- `io.stdin:seek("set", ...)` succeeds on HarmonyOS (returns 0) instead of failing — tests expecting stdin seek to fail need `_port = true`
- C stdlib functions `tmpfile()`, `mkstemp()` may not work — prefer explicit file creation in writable dirs
- `os.tmpname()` returns paths under `/tmp` which is read-only — must override or redirect
- Dynamic library loading (Lua `require` for .so) may not work — skip related tests
- Locale support is limited (no pt_BR, collate, ctype locales) — skip locale-dependent tests
- musl libc differences: `__assert_fail` signature uses `int line` without `noexcept` (glibc uses `unsigned int` + `noexcept`)

### Python Environment

- **Python**: `$HOME/.local/bin/python3` (3.12.8) — single source, supports pip and extension module loading; compiled with `-rdynamic`, exports 948+ Py symbols (1521 total), enabling signed .so extension modules from user paths
- **pip mirror**: `pypi.tuna.tsinghua.edu.cn`
- **Extension modules (.so) must be code-signed** before loading
- **C/C++ extensions**: Set `CC=/data/service/hnp/bin/clang` and `CXX=/data/service/hnp/bin/clang++` before pip install

See python-harmonyos.md for details (in skill's `docs/` directory).

### Adaptation Experience

Detailed adaptation guides are in the skill's `docs/` directory. The skill install directory depends on installation scope:
- **Global**: `~/.claude/skills/harmonyos-dev-env/docs/`
- **Project-level**: `<project>/.claude/skills/harmonyos-dev-env/docs/`

Use the Read tool with the appropriate path. Available guides:

| File | Description |
|------|-------------|
| claude-code-harmonyos.md | AI programming assistant, npm package, SSH V8 crash workaround |
| nodejs-harmonyos.md | **Node.js dlopen fix, native addon signing, libc++_shared.so patchelf, sharp WASM32, 29/29 e2e tests** |
| python-harmonyos.md | Python installation, configuration, numpy/pillow/lxml setup |
| python-packages-harmonyos.md | 59 packages tested (orjson, matplotlib, httpx, pytest, **mcp**, **rpds-py** all work; scipy/uvloop cannot build), solutions for C/Rust/Meson extensions |
| python-extension-adaptation.md | **General guide for adapting C/Rust/C++/Meson Python packages** (signing, patchelf, supplement.so, .so suffix, meson wrapper, maturin direct build, psutil patch) |
| llama-cpp-harmonyos.md | Build, NEON/SVE optimization, ModelScope model download |
| rust-harmonyos.md | Toolchain install, signing, cargo config, FFI interop |
| eza-harmonyos.md | Rust build, SELinux/hmdfs attributes |
| bat-harmonyos.md | Rust build, syntax highlighting |
| starship-harmonyos.md | Rust build, errno patch, prompt config |
| mihomo-harmonyos.md | Go toolchain, proxy config, GEOIP/GEOSITE rules |
| pytorch-harmonyos.md | PyTorch v2.5.1, 15 key adaptations, **15/15 e2e tests all passed**, MNIST training |
| dropbear-harmonyos.md | SSH server/client, 5 source patches, V8 JIT crash workaround |
| openssh-harmonyos.md | OpenSSH 9.9p1, 16 source patches, scp/sftp/ssh-agent all working |
| code-signing.md | Detailed code signing instructions |
| ld-library-path.md | Dynamic library path configuration |
| selinux-analysis.md | Root cause of .so loading restrictions |
| ipc-feasibility.md | Native Child Process API analysis |
| troubleshooting.md | Consolidated problem-solving reference |