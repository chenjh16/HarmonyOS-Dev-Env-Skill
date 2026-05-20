# HarmonyOS Development Environment - Global Rules

> **Note**: This file (`CLAUDE.md`) is the English version. A Chinese version (`CLAUDE.cn.md`) must be maintained in parallel. When editing this file, update the Chinese version correspondingly.

## Platform: HarmonyOS (HongMeng Kernel 1.12.0, aarch64)

### Filesystem & Permissions

- `/tmp` is **read-only** on this system — do NOT use it for temp files, builds, or os.tmpname()
- The writable temp directory is `$HOME/Claude/tmpdir/` — use this instead of /tmp
- When overriding `os.tmpname` in Lua or other scripts, redirect output to `$HOME/Claude/tmpdir/`
- `io.tmpfile()` (C stdlib tmpfile) returns NULL on HarmonyOS — use fallback: fopen in writable dir then unlink
- User home is `$HOME/` (not /home/)

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
- **llama.cpp**: built at `$HOME/Claude/llama.cpp/build/bin/`; `llama-cli`, `llama-server`, `llama-quantize` etc. available
- **eza**: v0.23.4 at `$HOME/Claude/eza-build/eza/target/release/`; modern `ls` replacement with colors, icons, tree view
- **bat**: v0.26.1 at `$HOME/Claude/bat-build/bat/target/release/`; `cat` clone with syntax highlighting
- **starship**: v1.25.1 at `$HOME/Claude/starship-build/starship/target/release/`; cross-shell prompt
- **Go**: v1.22.5 at `$HOME/Claude/go-build/go/`; use `GOPROXY=https://goproxy.cn,direct`; set `TMPDIR=$HOME/Claude/tmpdir`
- **mihomo**: Clash Meta proxy at `$HOME/Claude/mihomo-build/bin/mihomo-linux-arm64`; config at `$HOME/Claude/mihomo-config/`; proxy port 7890, API port 9090; supports GEOIP/GEOSITE intelligent routing
- **PyTorch**: v2.5.1 at `$HOME/.local/lib/python3.12/site-packages/torch/`; fully functional on HarmonyOS (12 e2e tests passed); requires `LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH`
- **Dropbear**: v2024.86 SSH server/client at `$HOME/.local/bin/`; `dropbear` (server), `dbclient` (client), `dropbearkey` (key generation); pubkey auth only (no password auth due to missing crypt())

### Third-party tools in PATH

All third-party toolchains are configured in `$HOME/.zshenv` and auto-loaded on shell startup:
- Rust: `$HOME/.rust/bin` → `rustc`, `cargo`
- llama.cpp: `$HOME/Claude/llama.cpp/build/bin` → `llama-cli`, `llama-server`, etc.
- eza: `$HOME/Claude/eza-build/eza/target/release` → `eza`
- bat: `$HOME/Claude/bat-build/bat/target/release` → `bat`
- starship: `$HOME/Claude/starship-build/starship/target/release` → `starship`
- Dropbear: `$HOME/.local/bin` → `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`
- `LD_LIBRARY_PATH` includes `$HOME/.rust/lib`, `/system/lib64`, and llama.cpp bin dir
- `SSL_CERT_FILE` set to `$HOME/.rust/cacert.pem` (for cargo crates.io access)
- `TMPDIR` set to `$HOME/Claude/tmpdir` (because `/tmp` is read-only on HarmonyOS)

**CRITICAL**: `/usr/lib` must come before `$HOME/.rust/lib` in LD_LIBRARY_PATH to avoid OpenSSL symbol version conflicts. See [ld-library-path.md](docs/ld-library-path.md) for details.

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

### Model Capability Matrix

- **Opus-mapped model**: strongest backend coding and planning capability; NO vision capability
- **Sonnet-mapped model**: strong coding and frontend capability; NO vision capability
- **Haiku-mapped model**: has vision capability (can read images, screenshots, PNG/JPG); lighter reasoning

**When delegating tasks via the Agent tool, choose the model based on task nature:**

| Task type | Recommended model | Reason |
|-----------|-------------------|--------|
| Visual observation (screenshots, image analysis) | `model: "haiku"` | Only model with vision capability |
| Backend coding, complex planning, architecture design | `model: "opus"` | Strongest backend & planning ability |
| Frontend coding, general coding tasks | `model: "sonnet"` | Strong coding & frontend ability |
| Simple research, file search, quick lookups | `model: "haiku"` | Lightweight, fast |

This balances model load and leverages each model's strengths.

### Python Environment

- **Python**: `$HOME/.local/bin/python3` (3.12.8) — single source, supports pip and extension module loading
- **pip mirror**: `pypi.tuna.tsinghua.edu.cn`
- **Extension modules (.so) must be code-signed** before loading
- **C/C++ extensions**: Set `CC=/data/service/hnp/bin/clang` and `CXX=/data/service/hnp/bin/clang++` before pip install

See [python-harmonyos.md](docs/python-harmonyos.md) for details.

### Adaptation Experience

Detailed adaptation guides are available in the `docs/` directory:
- [Claude Code for HarmonyOS](docs/claude-code-harmonyos.md) — AI programming assistant, npm package, SSH V8 crash workaround
- [Python Environment Guide](docs/python-harmonyos.md) — installation, configuration, numpy/pillow/lxml setup
- [Python Package Compatibility](docs/python-packages-harmonyos.md) — 34 packages tested, solutions for C/Rust extensions
- [llama.cpp Adaptation](docs/llama-cpp-harmonyos.md) — build, NEON/SVE optimization, ModelScope model download
- [Rust Adaptation](docs/rust-harmonyos.md) — toolchain install, signing, cargo config, FFI interop
- [eza Adaptation](docs/eza-harmonyos.md) — Rust build, SELinux/hmdfs attributes
- [bat Adaptation](docs/bat-harmonyos.md) — Rust build, syntax highlighting
- [starship Adaptation](docs/starship-harmonyos.md) — Rust build, errno patch, prompt config
- [mihomo Adaptation](docs/mihomo-harmonyos.md) — Go toolchain, proxy config, GEOIP/GEOSITE rules
- [PyTorch Adaptation](docs/pytorch-harmonyos.md) — PyTorch v2.5.1 compilation, 7 key adaptations, 12 e2e tests, MNIST training
- [Dropbear SSH Adaptation](docs/dropbear-harmonyos.md) — SSH server/client, 5 source patches, V8 JIT crash workaround
- [Code Signing Guide](docs/code-signing.md) — detailed code signing instructions
- [LD_LIBRARY_PATH Guide](docs/ld-library-path.md) — dynamic library path configuration