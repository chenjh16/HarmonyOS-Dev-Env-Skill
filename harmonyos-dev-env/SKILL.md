---
name: harmonyos-dev-env
description: HarmonyOS PC development environment skill pack. Provides complete platform knowledge (code signing, read-only /tmp, no gcc, ld.bfd wrapper, LD_LIBRARY_PATH ordering) and toolchain adaptation guides (Python, Rust, Go, PyTorch, llama.cpp, OpenSSH, etc.). Use when building, compiling, or configuring any software on HarmonyOS, or when user mentions "鸿蒙", "HarmonyOS", "HongMeng", or any HarmonyOS-specific issue. Read docs/ files for detailed build guides when needed.
argument-hint: [topic: e.g. "python build", "code signing", "openssh config"] or just describe what you need
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(clang *) Bash(binary-sign-tool *) Bash(patchelf *) Bash(cmake *) Bash(ninja *) Bash(make *) Bash(pip *) Bash(cargo *) Bash(go *) Bash(curl *) Bash(git *) Bash(sh *) Bash(bash *) Bash(chmod *) Bash(mkdir *) Bash(cp *) Bash(mv *) Bash(rm *) Bash(ln *) Bash(sed *) Bash(grep *) Bash(cat *) Bash(head *) Bash(tail *) Bash(find *) Bash(file *) Bash(nm *) Bash(llvm-objcopy *) Bash(llvm-readelf *) Bash(ssh *) Bash(sshd *) Bash(scp *) Bash(sftp *) Bash(ssh-keygen *) Bash(pkill *) Bash(pgrep *) Bash(ps *) Bash(echo *) Agent Read Write Edit Grep Glob
---

# HarmonyOS PC Development Environment Skill Pack

> **中文说明见下方 | For Chinese version, see below**

## English Version

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

7. **CMAKE_TOOLCHAIN_FILE**: Do NOT combine with `CMAKE_SYSTEM_NAME` — triggers cross-compile mode, breaking `try_run()`. Pass compiler flags directly via `-DCMAKE_C_COMPILER` and `-DCMAKE_CXX_COMPILER`.

8. **SSH V8 crash**: HarmonyOS PTY + V8 JIT crashes (ENOMEM). Use `node --jitless` + `node-fetch` polyfill for SSH sessions.

9. **OpenSSH passwd_compat**: sshd requires `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so` because uid 20020106 is not in /etc/passwd (read-only). Child env must preserve LD_PRELOAD/LD_LIBRARY_PATH (patch session.c).

10. **OpenSSH abstract socket**: ssh-agent bind() returns EPERM for filesystem Unix sockets. Uses abstract namespace fallback (`SSH_AUTH_SOCK=abstract:<name>`).

11. **OpenSSH authorized_keys UID**: Files owned by uid 20001006 (file_manager), processes run as uid 20020106. `platform_sys_dir_uid()` accepts 20001006 as system owner. `safe_path()` skips mode check for system-owned files. StrictModes=yes works.

12. **Dropbear -e flag**: Must start dropbear with `-e` flag to pass parent env to child sessions (LD_LIBRARY_PATH, PATH, etc.).

13. **musl libc**: No `crypt()` (no password auth), no `strerror_r` (errno crate needs patch), limited locale support, `__assert_fail` uses `int line` without `noexcept`.

14. **Python -rdynamic**: Our Python exports 948+ Py symbols via `-rdynamic`, enabling signed .so extension modules from user paths. No need for static-only extensions.

### Toolchain Quick Reference

| Tool | Version | Install Path | Key Feature |
|------|---------|-------------|-------------|
| Python | 3.12.8 | `$HOME/.local` | pip, -rdynamic, numpy, pillow, lxml |
| Node.js | 24.13.0 | AppGallery | DevNode-OH, --jitless SSH workaround |
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
| Claude Code | 2.1.88-ohos | npm global | HarmonyOS native, ripgrep auto-signing |

### Adaptation Guide Locations

Full build guides are in this skill's `docs/` directory. When the user asks about a specific tool, read the corresponding guide using the Read tool with relative path from this SKILL.md's directory:

- `docs/python-harmonyos.md` / `.cn.md` — Python 3.12.8 standalone build
- `docs/rust-harmonyos.md` / `.cn.md` — Rust ohos target installation
- `docs/pytorch-harmonyos.md` / `.cn.md` — PyTorch v2.5.1, 15/15 e2e tests
- `docs/openssh-harmonyos.md` / `.cn.md` — OpenSSH 9.9p1, 16 patches
- `docs/dropbear-harmonyos.md` / `.cn.md` — Dropbear, 5 patches, V8 crash
- `docs/llama-cpp-harmonyos.md` / `.cn.md` — NEON/SVE optimization, Qwen3.5
- `docs/claude-code-harmonyos.md` / `.cn.md` — Claude Code ohos adaptation
- `docs/nodejs-harmonyos.md` / `.cn.md` — DevNode-OH, TLS workaround
- `docs/mihomo-harmonyos.md` / `.cn.md` — HTTP/SOCKS5, GEOIP/GEOSITE
- `docs/eza-harmonyos.md` / `.cn.md` — modern ls
- `docs/bat-harmonyos.md` / `.cn.md` — syntax-highlighted cat
- `docs/starship-harmonyos.md` / `.cn.md` — cross-shell prompt
- `docs/code-signing.md` / `.cn.md` — ELF/HAP signing guide
- `docs/ld-library-path.md` / `.cn.md` — LD_LIBRARY_PATH ordering
- `docs/selinux-analysis.md` / `.cn.md` — .so loading root cause
- `docs/troubleshooting.md` / `.cn.md` — consolidated problem-solving

Tool build guides with install scripts are in `tools/`:
- `tools/python/`, `tools/rust/`, `tools/go/`, `tools/llama-cpp/`, `tools/mihomo/`, `tools/dropbear/`, `tools/openssh/`, `tools/pytorch/`, `tools/bat/`, `tools/eza/`, `tools/starship/`

### Quick Commands

```bash
# One-time environment setup (creates tmpdir, linker wrapper, copies zshenv)
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh

# Batch code signing for a directory
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-all.sh <directory>

# Verify environment (checks all toolchains)
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```

---

### 中文说明

#### 关键平台规则

1. **代码签名**: 所有 ELF 二进制必须签名才能执行。未签名二进制立即崩溃。
2. **/tmp 只读**: 使用 `$HOME/Claude/tmpdir` 替代。
3. **无 gcc**: 只有 `/data/service/hnp/bin/clang` 可用。
4. **SDK lld 损坏**: 需要 `libxml2.so.16`（不存在），必须创建 ld.bfd 封装。
5. **LD_LIBRARY_PATH 顺序**: `/usr/lib` 必须在 `$HOME/.rust/lib` 前面。
6. **make -j 失败**: mkfifo 返回 "Operation not permitted"——使用 Ninja。
7. **不要用 CMAKE_TOOLCHAIN_FILE + CMAKE_SYSTEM_NAME**: 会触发交叉编译导致 try_run() 失败。
8. **SSH V8 崩溃**: 使用 `node --jitless` + node-fetch polyfill。
9. **OpenSSH passwd_compat**: sshd 需要 LD_PRELOAD passwd_compat.so。
10. **OpenSSH 抽象socket**: ssh-agent 使用抽象命名空间。
11. **OpenSSH authorized_keys**: uid 20001006 (file_manager) 加入 platform_sys_dir_uid()。
12. **Dropbear -e 参数**: 必须使用 `-e` 传递环境变量给子会话。
13. **musl libc**: 无 crypt()、strerror_r，locale 支持有限。
14. **Python -rdynamic**: 导出 948+ Py 符号，支持用户路径签名 .so 扩展模块。

#### 快捷命令

```bash
# 一次性环境设置（创建 tmpdir、linker wrapper、复制 zshenv）
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh

# 批量代码签名
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-all.sh <目录>

# 环境验证
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```