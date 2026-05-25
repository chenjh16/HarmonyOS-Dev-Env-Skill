# Dropbear SSH Server on HarmonyOS (aarch64) - Adaptation Guide

> **中文版本请查看 dropbear-harmonyos.cn.md**

## Overview

Dropbear is a lightweight SSH server/client that's easier to compile on HarmonyOS compared to OpenSSH. This guide documents the complete adaptation process.

**Result**: Dropbear 2024.86 fully functional with:
- Server: `dropbear` (285KB)
- Client: `dbclient` (273KB)
- Key generation: `dropbearkey` (187KB)
- Key conversion: `dropbearconvert` (195KB)

**Authentication**: Pubkey auth only (no password auth due to missing `crypt()`)

**Installation**: `$HOME/.local/bin/`

## Key Adaptations

### 1. HarmonyOS User System Patches

HarmonyOS uses non-traditional user management:
- Users NOT registered in `/etc/passwd`
- Process UID (e.g., 20020106) differs from file owner UID (e.g., 20001006)
- No `/etc/shells` file

Five source files require patching:

| File | Issue | Patch |
|------|-------|-------|
| `src/common-session.c` | `getpwnam()` fails | Accept any non-system username as device user |
| `src/svr-auth.c` | Shell validation fails | Skip `/etc/shells` check |
| `src/svr-authpubkey.c` | Permission check fails | Skip file ownership check |
| `src/svr-chansession.c` | PTY allocation fails | Reuse authstate passwd |
| `src/loginrec.c` | Login recording fails | Accept any non-system username (same logic as common-session) |

### 2. No crypt() Function

HarmonyOS lacks `crypt()` for password hashing. Solution: disable password auth:
```c
// In options.h
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_CLI_PASSWORD_AUTH 0
```

### 3. ld.bfd Wrapper Required

SDK's `lld` requires `libxml2.so.16` which doesn't exist. Use ld.bfd wrapper:
```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

### 4. config.h Configuration

Key settings for HarmonyOS:
```c
#undef HAVE_GETRANDOM  /* HarmonyOS uses /dev/urandom */
#define BUNDLED_LIBTOM 1
#define HAVE_OPENPTY 1
#define HAVE_PTY_H 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_IPV6 1
```

### 5. V8 JIT Crash in SSH Sessions

**Issue**: Node.js V8 JIT crashes in SSH PTY environment with `errno=ENOMEM`.

**Solution**: Use `--jitless` mode + `node-fetch` polyfill:
```bash
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /path/to/claude-code/cli.js --dangerously-skip-permissions
```

**Why node-fetch polyfill**:
- `--jitless` disables WebAssembly
- Native `fetch` requires WebAssembly for compression
- `node-fetch` uses `http.request` (no WebAssembly)

## Build Summary

```bash
# 1. Download source
cd $HOME/Claude/dropbear-build
curl -L -o dropbear-2024.86.tar.bz2 \
  "https://matt.ucc.asn.au/dropbear/releases/dropbear-2024.86.tar.bz2"
tar xjf dropbear-2024.86.tar.bz2

# 2. Build libtommath + libtomcrypt
cd libtommath && make
cd libtomcrypt && make -f makefile.unix

# 3. Create config.h and options.h (see build.md for details)

# 4. Build with custom Makefile
make dropbear dbclient dropbearkey dropbearconvert

# 5. Sign binaries
for binary in dropbear dbclient dropbearkey dropbearconvert; do
  llvm-objcopy --remove-section=.codesign $binary ${binary}.unsigned
  binary-sign-tool sign -selfSign 1 -inFile ${binary}.unsigned -outFile ${binary}.signed
  mv ${binary}.signed $binary
  chmod +x $binary
done

# 6. Generate host keys
mkdir -p $HOME/.local/etc/dropbear
dropbearkey -t rsa -f ~/.local/etc/dropbear/dropbear_rsa_host_key -s 2048
dropbearkey -t ecdsa -f ~/.local/etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f ~/.local/etc/dropbear/dropbear_ed25519_host_key
```

## Running the Server

### Manual Start

```bash
# Foreground with logging (-e passes parent env to child sessions)
dropbear -p 2222 -e -F -E

# Background (with -e for env passthrough)
dropbear -p 2222 -e
```

**CRITICAL**: The `-e` flag passes the parent process's environment variables (LD_LIBRARY_PATH, PATH, etc.) to SSH child sessions. Without `-e`, `clearenv()` wipes all environment variables before setting only minimal defaults (PATH=/usr/bin:/bin), breaking SSH sessions on HarmonyOS.

### Connect

Any non-system username works (HarmonyOS is a single-user device):
```bash
# Any username works
ssh -p 2222 chenh@localhost
ssh -p 2222 user@localhost
ssh -p 2222 currentUser@localhost

# Numeric UID also works
dbclient 20020106@localhost -p 2222
# From remote: ssh -p 2222 chenh@<HarmonyOS-IP>
```

**Note**: Interactive SSH sessions (shell with PTY) have a known limitation — `ioctl(TIOCSCTTY)` fails on HarmonyOS, resulting in no controlling tty. This means limited job control in interactive sessions. Command execution mode (`ssh user@host command`) works correctly.

### Auto-start on Login

Scripts in `$HOME/.local/bin/`:
- `start-ssh.sh [port]` - Start server
- `stop-ssh.sh` - Stop server

Auto-start in `.zshrc`:
```bash
if [ -z "$NO_AUTOSTART_SSH" ]; then
    "$HOME/.local/bin/start-ssh.sh"
fi
```

Disable with: `export NO_AUTOSTART_SSH=1`

## Known Limitations

1. **No password authentication** - HarmonyOS lacks `crypt()`
2. **Any non-system username accepted** - All usernames (except root/bin/system) map to the same device user
3. **Five source patches required** - Must modify source files
4. **PTY TIOCSCTTY fails** - Interactive sessions have no controlling tty (HarmonyOS kernel limitation); command execution works fine
5. **Must use `-e` flag** - Environment passthrough critical for SSH child sessions
6. **V8 JIT crash** - Node.js apps need `--jitless` + polyfill

## Troubleshooting

### "Login attempt for nonexistent user"

Apply `common-session.c` and `loginrec.c` patches. Both now accept any non-system username as the device user. After patching, usernames like `chenh`, `user`, `currentUser`, or numeric UID all work.

### "must be owned by user or root"

Apply `svr-authpubkey.c` patch to skip permission check.

### V8 crash (ENOMEM)

Use `--jitless` mode + node-fetch polyfill. See `tools/dropbear/build.md` for full script.

## Files Produced

| Binary | Size | Purpose |
|--------|------|---------|
| dropbear | 285KB | SSH server |
| dbclient | 273KB | SSH client |
| dropbearkey | 187KB | Key generation |
| dropbearconvert | 195KB | Key conversion |

## Comparison with OpenSSH

| Feature | Dropbear | OpenSSH |
|---------|----------|---------|
| Binary size | ~1MB total | ~4MB+ |
| Configure | Manual Makefile | Complex autoconf |
| Password auth | Not supported | Requires crypt |
| Build time | ~5 min | ~15+ min |
| Dependencies | Bundled libtomcrypt | OpenSSL headers |
| HarmonyOS patches | 5 source files | More complex |

Dropbear is recommended for HarmonyOS due to simpler build and bundled crypto libraries.

## References

- Dropbear source: https://matt.ucc.asn.au/dropbear/releases/
- Full build guide: `tools/dropbear/build.md`
- SSH polyfill script: `config/.claude/ssh-fetch-polyfill.js`