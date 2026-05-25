# Dropbear SSH Server on HarmonyOS (aarch64) - Complete Build Guide

> **中文版本请查看 build.cn.md**

## Overview

Dropbear is a lightweight SSH server/client that's easier to compile on HarmonyOS compared to OpenSSH. This guide documents the complete build process.

**Key Challenges**:
1. HarmonyOS lacks `crypt()` function - password auth must be disabled
2. `configure` script fails due to cross-compile detection issues
3. `fake-rfc2553.h` causes structure redefinition conflicts
4. `HAVE_GETRANDOM` should be undefined - HarmonyOS uses `/dev/urandom` instead
5. **Non-standard user system** - Users not in `/etc/passwd`, must patch source code
6. **File ownership mismatch** - Process UID differs from file owner UID

## Build Summary

**Result**: Successfully compiled Dropbear 2024.86 with:
- Server: `dropbear` (285KB)
- Client: `dbclient` (273KB)
- Key generation: `dropbearkey` (187KB)
- Key conversion: `dropbearconvert` (195KB)

**Authentication**: Pubkey auth only (no password auth due to missing `crypt()`)

## Prerequisites

- HarmonyOS SDK with clang 15.0.4
- ld.bfd wrapper (SDK's lld requires libxml2.so.16 which doesn't exist)
- sysroot from SDK

## Build Steps

### 1. Download Source

```bash
cd $HOME/Claude/dropbear-build
curl -L --connect-timeout 30 -o dropbear-2024.86.tar.bz2 \
  "https://matt.ucc.asn.au/dropbear/releases/dropbear-2024.86.tar.bz2"
tar xjf dropbear-2024.86.tar.bz2
cd dropbear-2024.86
```

### 2. Create ld.bfd Wrapper

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

### 3. Build libtommath

```bash
cd libtommath
cat > Makefile << 'EOF'
CC=/data/service/hnp/bin/clang
AR=/data/service/hnp/bin/ar
RANLIB=/data/service/hnp/bin/ranlib
CFLAGS=-O2 -I. -I../src -I../libtomcrypt/src/headers -I.. -Wno-deprecated
LIBNAME=libtommath.a

SOURCES=bn_cutoffs.c bn_deprecated.c bn_mp_2expt.c ... # all bn_*.c files
OBJECTS=$(SOURCES:.c=.o)

$(LIBNAME): $(OBJECTS)
	$(AR) rcs $@ $(OBJECTS)
	$(RANLIB) $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@
EOF
make
```

### 4. Build libtomcrypt

```bash
cd libtomcrypt
make -f makefile.unix \
  CC=/data/service/hnp/bin/clang \
  AR=/data/service/hnp/bin/ar \
  RANLIB=/data/service/hnp/bin/ranlib \
  CFLAGS="-O2 -Isrc/headers -I../libtommath -I.. -I../src -DLTC_SOURCE -DUSE_LTM -DLTM_DESC -DDROPBEAR_BUNDLED_LIBTOM --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot" \
  EXTRALIBS="../libtommath/libtommath.a"
```

### 5. Create config.h

```c
/* config.h for HarmonyOS */
#ifndef DROPBEAR_CONFIG_H
#define DROPBEAR_CONFIG_H

#undef HAVE_GETRANDOM  /* HarmonyOS uses /dev/urandom */

/* Use bundled libtomcrypt/libtommath */
#define BUNDLED_LIBTOM 1

#define HAVE_CLOCK_GETTIME 1
#define HAVE_DAEMON 1
#define HAVE_GETADDRINFO 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_WRITEV 1

/* PTY support - HarmonyOS uses Unix98 PTY (/dev/ptmx + /dev/pts/) */
#define HAVE_OPENPTY 1
#define HAVE_PTY_H 1

/* Network structures exist on HarmonyOS */
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_IN6_ADDR 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_IPV6 1

#endif
```

### 6. Create options.h

**Important**: Include order matters! `default_options.h` must be included FIRST, then override macros with `#undef` and `#define`.

Also, `config.h` must be included at the very beginning so that `HAVE_STRUCT_*` definitions are available for `fake-rfc2553.h` checks (preventing structure redefinition conflicts with system headers).

```bash
cat > src/options.h << 'EOF'
#ifndef DROPBEAR_OPTIONS_H
#define DROPBEAR_OPTIONS_H

/* Include config.h first for HAVE_* definitions */
#include "config.h"

/* Include default options first */
#include "default_options.h"

/* Override for HarmonyOS - disable password auth (no crypt()) */
#undef DROPBEAR_SVR_PASSWORD_AUTH
#define DROPBEAR_SVR_PASSWORD_AUTH 0

#undef DROPBEAR_CLI_PASSWORD_AUTH  
#define DROPBEAR_CLI_PASSWORD_AUTH 0

/* Key paths */
#undef RSA_PRIV_FILENAME
#define RSA_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_rsa_host_key"
#undef ECDSA_PRIV_FILENAME
#define ECDSA_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_ecdsa_host_key"
#undef ED25519_PRIV_FILENAME
#define ED25519_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_ed25519_host_key"

#include "sysoptions.h"
#endif
EOF
```

### 7. Create Makefile

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot

cat > Makefile << 'EOF'
CC=/data/service/hnp/bin/clang
CPPFLAGS=-I. -Isrc -Ilibtomcrypt/src/headers -Ilibtommath --sysroot=$(SYSROOT)
CFLAGS=-B$(HOME)/Claude/lib/linker_wrapper -O2 -Wall -DDROPBEAR_SERVER=1 -DDROPBEAR_CLIENT=1
LDFLAGS=-B$(HOME)/Claude/lib/linker_wrapper --sysroot=$(SYSROOT) -L$(SYSROOT)/usr/lib/aarch64-linux-ohos
LIBS=-lz
LIBTOM_LIBS=libtomcrypt/libtomcrypt.a libtommath/libtommath.a

# Define object lists...

dropbear: $(dropbearobjs) $(LIBTOM_LIBS)
	$(CC) $(LDFLAGS) -o $@ $(dropbearobjs) $(LIBTOM_LIBS) $(LIBS)
EOF
make
```

### 8. Sign Binaries

All ELF binaries must be signed:

```bash
for binary in dropbear dbclient dropbearkey dropbearconvert; do
  llvm-objcopy --remove-section=.codesign $binary ${binary}.unsigned
  binary-sign-tool sign -selfSign 1 -inFile ${binary}.unsigned -outFile ${binary}.signed -signAlg SHA256withECDSA
  mv ${binary}.signed $binary
  chmod +x $binary
done
```

### 9. Generate Host Keys

```bash
mkdir -p $HOME/.local/etc/dropbear
dropbearkey -t rsa -f ~/.local/etc/dropbear/dropbear_rsa_host_key -s 2048
dropbearkey -t ecdsa -f ~/.local/etc/dropbear/dropbear_ecdsa_host_key -s 256
dropbearkey -t ed25519 -f ~/.local/etc/dropbear/dropbear_ed25519_host_key
```

### 10. Source Code Patches for HarmonyOS User System

HarmonyOS uses a non-traditional user management system where:
- Users are NOT registered in `/etc/passwd`
- Process UID (e.g., 20020106) differs from file owner UID (e.g., 20001006)
- Home directories have group-writable permissions that cannot be changed
- No `/etc/shells` file for shell validation

Five source files need to be patched:

#### Patch 1: `src/common-session.c` - User Lookup Fallback

Add fallback for `getpwnam()` failure to accept any non-system username as the device user:

```c
// In fill_passwd() function, after line "pw = getpwnam(username);"
pw = getpwnam(username);
if (!pw) {
    /* HarmonyOS fallback: /etc/passwd has minimal entries (root, bin,
     * system services). The actual device user has a numeric UID and
     * is not listed by any human-readable name. Since this is a single-
     * user device, accept any username not in the system UID range
     * (0-9999) as referring to the current device user. */
    char uid_str[32];
    snprintf(uid_str, sizeof(uid_str), "%u", getuid());
    /* Reject system usernames (root, bin, system, etc.) —
     * these have UIDs < 10000 and should not get device-user access */
    long uid_check = strtol(username, NULL, 10);
    if (strcmp(username, "root") == 0 || strcmp(username, "bin") == 0
        || strcmp(username, "system") == 0
        || (username[0] != '\0' && uid_check > 0 && uid_check < 10000)) {
        /* This is a known system user that doesn't exist — reject */
        return;
    }
    /* Accept any other username as the device user */
    ses.authstate.pw_uid = getuid();
    ses.authstate.pw_gid = getgid();
    ses.authstate.pw_name = m_strdup(uid_str);
    ses.authstate.pw_dir = m_strdup(getenv("HOME") ? getenv("HOME") : "/");
    ses.authstate.pw_shell = m_strdup(getenv("SHELL") ? getenv("SHELL") : "/usr/bin/zsh");
    ses.authstate.pw_passwd = m_strdup("!!");
    return;
}
```

**Explanation**: HarmonyOS `/etc/passwd` has minimal entries (root, bin, system services). The actual device user has a numeric UID (e.g., 20020106) and is not listed by any human-readable name. Since HarmonyOS is a single-user device, the patch accepts any username that doesn't match a system account as referring to the current device user. This means SSH clients can connect with any arbitrary username (e.g., `chenh`, `user`, `currentUser`, `20020106`) — all will be treated as the same device user.

**Security note**: System usernames (root, bin, system) and numeric UIDs below 10000 are explicitly rejected to prevent unauthorized access to system accounts that shouldn't exist.

**Important**: Shell must be set to `$SHELL` (typically `/usr/bin/zsh` on HarmonyOS), not `/bin/sh`. Using `/bin/sh` causes SSH sessions to skip `.zshenv` PATH configuration, breaking npm/claude commands.

#### Patch 2: `src/svr-auth.c` - Skip Shell Validation

HarmonyOS lacks `/etc/shells`, so dropbear's shell validation always fails. Skip the validation:

```c
// In checkusername() function, around line 316
// Replace the shell validation loop with:
/* HarmonyOS: skip shell validation since /etc/shells does not exist */
TRACE(("skipping shell validation for HarmonyOS"))
goto goodshell;
```

**Explanation**: Dropbear validates user shells by checking against `/etc/shells`. HarmonyOS doesn't have this file, causing all shell validations to fail. The patch bypasses this check.

#### Patch 3: `src/svr-authpubkey.c` - Skip Permission Checks

Replace the `checkfileperm()` function to skip strict permission verification:

```c
static int checkfileperm(char * filename) {
    TRACE(("enter checkfileperm(%s)", filename))
    /* HarmonyOS: skip permission checks due to non-standard file ownership */
    /* - File UID (20001006) != Process UID (20020106) */
    /* - Home directory has group-writable permissions (cannot be changed) */
    TRACE(("leave checkfileperm: success (HarmonyOS skip)"))
    return DROPBEAR_SUCCESS;
}
```

**Explanation**: Dropbear normally requires:
1. Home directory, `.ssh`, and `authorized_keys` owned by user or root
2. No group or others write permission

On HarmonyOS:
- File ownership uses UID 20001006 (file_manager)
- Process runs with UID 20020106
- Directories have `drwxrws--x` (group writable) and `chmod g-w` fails

The patch bypasses these checks since HarmonyOS's security model is different from traditional Linux.

#### Patch 4: `src/svr-chansession.c` - PTY Allocation Fallback

When allocating a PTY for an interactive session, dropbear calls `getpwnam()` again. Add fallback:

```c
// In sessionpty() function, around line 611
pw = getpwnam(ses.authstate.pw_name);
if (!pw) {
    /* HarmonyOS fallback: create passwd entry from authstate */
    pw = m_malloc(sizeof(struct passwd));
    pw->pw_uid = ses.authstate.pw_uid;
    pw->pw_gid = ses.authstate.pw_gid;
    pw->pw_name = ses.authstate.pw_name;
    pw->pw_dir = ses.authstate.pw_dir;
    pw->pw_shell = ses.authstate.pw_shell;
    pw->pw_passwd = ses.authstate.pw_passwd;
    if (!pw->pw_dir || !pw->pw_shell)
        dropbear_exit("getpwnam failed: missing passwd fields");
}
pty_setowner(pw, chansess->tty);
```

**Explanation**: During PTY allocation, `svr-chansession.c` calls `getpwnam()` to get user info for setting PTY owner. This fails on HarmonyOS, causing segfault. The patch reuses the authstate data that was already populated by Patch 1.

#### Patch 5: `src/loginrec.c` - Login Record Fallback

When recording login sessions, `login_init_entry()` calls `getpwnam()`. Add fallback that accepts any non-system username:

```c
// In login_init_entry() function, around line 278
pw = getpwnam(li->username);
if (pw == NULL) {
    /* HarmonyOS fallback: use authstate uid if getpwnam fails.
     * On HarmonyOS, the actual device user is not in /etc/passwd,
     * so getpwnam() always fails. We accept any non-system username
     * as the current device user (same logic as common-session.c). */
    long uid_check = strtol(li->username, NULL, 10);
    if (strcmp(li->username, "root") == 0 || strcmp(li->username, "bin") == 0
        || strcmp(li->username, "system") == 0
        || (li->username[0] != '\0' && uid_check > 0 && uid_check < 10000)) {
        dropbear_exit("login_init_entry: Cannot find system user \"%s\"",
                li->username);
    }
    li->uid = ses.authstate.pw_uid;
} else {
    li->uid = pw->pw_uid;
}
```

**Note**: This requires adding `#include "session.h"` or declaring `extern struct sshsession ses;` in loginrec.c.

**Explanation**: Login recording (utmp/wtmp) requires user UID lookup. On HarmonyOS, `getpwnam()` fails for all device user names. The old patch only matched `pw_name` (UID string "20020106") which didn't match SSH usernames like "chenh" or "user", causing `dropbear_exit()` and segfault. The updated patch uses the same logic as common-session.c — accept any non-system username as the device user.

#### After Patching - Rebuild

```bash
cd $HOME/Claude/dropbear-build/dropbear-2024.86
rm -f obj/common-session.o obj/svr-auth.o obj/svr-authpubkey.o obj/svr-chansession.o obj/loginrec.o obj/sshpty.o
make dropbear
# Sign and install as described in step 8
```

## Running the Server

### Manual Start

```bash
# Start server on port 2222 (foreground, with logging)
# IMPORTANT: -e flag passes parent environment to child sessions
# This is critical on HarmonyOS because SSH sessions need LD_LIBRARY_PATH,
# PATH, and other environment variables that .zshenv restores
dropbear -p 2222 -e -F -E

# Start server in background (default port 2222, with -e for env passthrough)
dropbear -p 2222 -e

# Connect as client (use numeric UID as username)
dbclient 20020106@localhost -p 2222
```

**Note**: Port 22 is a privileged port requiring root privileges. Use port 2222 (or any port > 1024) for non-root operation.

### Connecting from Remote Machines

Due to HarmonyOS's single-user device model, any non-system username can be used for SSH login. All usernames map to the same device user:

```bash
# Connect from remote machine - any username works
ssh -p 2222 chenh@<HarmonyOS-IP>
ssh -p 2222 user@<HarmonyOS-IP>
ssh -p 2222 currentUser@<HarmonyOS-IP>

# Numeric UID also works
ssh -p 2222 20020106@<HarmonyOS-IP>
```

**Why any username works**: HarmonyOS `/etc/passwd` has minimal entries. The source code patch (Patch 1) accepts any non-system username as the device user, since there's only one real user on the device. System usernames (root, bin, system) are rejected.

**Setup Steps**:

1. On remote machine, generate SSH key (if not exists):
   ```bash
   ssh-keygen -t ed25519
   ```

2. Copy public key to HarmonyOS:
   ```bash
   # On HarmonyOS, add remote's public key to authorized_keys
   echo "ssh-ed25519 AAAA...your-public-key" >> ~/.ssh/authorized_keys
   ```

3. Test connection:
   ```bash
   ssh -p 2222 20020106@<HarmonyOS-IP>
   ```

### Auto-start on Login

HarmonyOS lacks systemd/cron, but you can auto-start SSH on shell login:

1. **Start/Stop Scripts** are installed at `$HOME/.local/bin/`:
   - `start-ssh.sh [port]` - Start SSH server (default: 2222)
   - `stop-ssh.sh` - Stop SSH server

2. **Auto-start is configured in `.zshrc`**:
   ```bash
   # SSH auto-start (already added to ~/.zshrc, default port 2222)
   if [ -z "$NO_AUTOSTART_SSH" ]; then
       "$HOME/.local/bin/start-ssh.sh"
   fi
   ```

3. **To disable auto-start**, add to `~/.zshenv`:
   ```bash
   export NO_AUTOSTART_SSH=1
   ```

### Notes on Auto-start

- HarmonyOS PC doesn't have traditional init system (no systemd/cron)
- Auto-start only works when you **log into the shell session**
- SSH server runs in background via `nohup`
- PID file: `$HOME/.local/var/run/dropbear.pid`
- Log file: `$HOME/.local/var/log/dropbear.log`

## Known Limitations

1. **No password authentication** - HarmonyOS lacks `crypt()` function
2. **Pubkey auth only** - Users must set up SSH keys manually
3. **Limited locale support** - May affect some functionality
4. **Any non-system username accepted** - All usernames (except root/bin/system) map to the same device user
5. **Source patches required** - Five source files must be modified for HarmonyOS compatibility
6. **PTY controlling tty limitation** - `ioctl(TIOCSCTTY)` fails on HarmonyOS (returns I/O error). Interactive SSH sessions (shell with PTY) may have limited job control. Command execution mode (`ssh user@host command`) works correctly.
7. **Must use `-e` flag** - The `-e` flag (pass parent environment to child) is critical on HarmonyOS because SSH child processes need LD_LIBRARY_PATH, PATH, and other variables. Without `-e`, `clearenv()` wipes all environment variables before setting only a minimal set (PATH=/usr/bin:/bin).

## Troubleshooting

### fake-rfc2553.h redefinition errors

Define `HAVE_STRUCT_*` macros in config.h to prevent dropbear from defining these structures that already exist in HarmonyOS headers.

### getrandom not found

HarmonyOS has `/dev/urandom` but no `getrandom()` syscall. Use `#undef HAVE_GETRANDOM` in config.h.

### svr_ses undeclared

Add `-DDROPBEAR_SERVER=1` to CFLAGS to enable server-specific code paths.

### "Login attempt for nonexistent user"

Log shows: `Login attempt for nonexistent user from ...`

**Cause**: User not found in `/etc/passwd` because HarmonyOS doesn't use traditional user database.

**Solution**: Apply `common-session.c` patch (Patch 1 in Step 10) which accepts any non-system username as the device user. After patching, usernames like `chenh`, `user`, `currentUser`, or numeric UID all work.

### "must be owned by user or root, and not writable by group or others"

Log shows: `$HOME must be owned by user or root...`

**Cause**: HarmonyOS file ownership model differs from Linux:
- Process UID (20020106) != File owner UID (20001006)
- Home directory has group-writable permission (`drwxrws--x`)

**Solution**: Apply `svr-authpubkey.c` patch (Step 10) to skip permission verification.

### Permission denied (publickey) after adding keys

**Check**:
1. Public key format is correct in `~/.ssh/authorized_keys`
2. Using a non-system username (any name works except root/bin/system)
3. All five source patches applied and dropbear rebuilt
4. Key matches one of the entries in `~/.ssh/authorized_keys`

### V8/Node.js Crash in SSH Sessions (errno=ENOMEM)

When running Claude Code or other Node.js applications in SSH sessions, you may encounter:

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
zsh: trace trap (core dumped)  NODE_OPTIONS="--max-old-space-size=12288" claude
```

**Cause**: HarmonyOS PTY system has limitations that affect V8 JIT compiler:
- V8 JIT requires memory-mapped executable pages which fail in SSH PTY environment
- `errno=ENOMEM (12)` indicates memory allocation failure for JIT code pages
- This is a HarmonyOS PTY/kernel limitation, not a Node.js bug

**Solution**: Use `node --jitless` flag + `node-fetch` polyfill:

```bash
# In SSH session, run Claude Code with --jitless and node-fetch polyfill
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /path/to/claude-code/cli.js --dangerously-skip-permissions
```

**Why node-fetch polyfill is needed**:
- `--jitless` disables WebAssembly to avoid JIT crash
- Node.js native `fetch` requires WebAssembly for compression (brotli/gzip)
- `node-fetch` uses `http.request` (no WebAssembly) and works with `--jitless`

**Automatic SSH detection in start-claude.sh**:

The startup script automatically detects SSH environment and uses `--jitless` + polyfill:

```bash
SSH_ENV_INDICATORS="${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}"
SSH_FETCH_POLYFILL="$HOME/.claude/ssh-fetch-polyfill.js"

if [ -n "$SSH_ENV_INDICATORS" ]; then
    exec node --jitless --require "$SSH_FETCH_POLYFILL" "$CLAUDE_ENTRY" "$@"
else
    exec claude "$@"
fi
```

**Setup requirements**:
1. Install node-fetch: `npm install node-fetch@2` in ~/Claude
2. Create polyfill script at `~/.claude/ssh-fetch-polyfill.js` (see below)
3. Update `~/.claude/start-claude.sh` with SSH detection logic

**node-fetch polyfill script** (`~/.claude/ssh-fetch-polyfill.js`):

```javascript
// SSH Environment Fetch Polyfill
// When running in SSH sessions on HarmonyOS, we use --jitless to avoid V8 crash
// But --jitless disables WebAssembly, breaking native fetch
// This script polyfills fetch with node-fetch (based on http.request)
//
// IMPORTANT: In --jitless mode, native fetch exists but is broken (WebAssembly is undefined)
// So we must check WebAssembly, not just fetch existence
//
// COMPATIBILITY FIXES:
// 1. node-fetch@2 Response.body is Node.js Readable stream, lacks cancel() method
// 2. node-fetch@2 Response.body is NOT Web ReadableStream (no pipeThrough/getReader)
// 3. MCP SDK uses Web Streams API: body.pipeThrough(new TextDecoderStream)...
// 4. Readable.toWeb() consumes the original stream, breaking text()/json()
// 5. SSH remote execution doesn't pass shell env vars to Node.js - must load .env directly
// 6. Solution: Override Response prototype methods to handle stream conversion lazily

if (typeof WebAssembly === 'undefined') {
    console.log('[SSH] WebAssembly disabled (--jitless mode), polyfilling fetch with node-fetch...');

    // Load environment variables from .env file (SSH remote execution doesn't pass shell env)
    const fs = require('fs');
    const envPath = process.env.HOME + '/.claude/.env';
    if (fs.existsSync(envPath) && !process.env.ANTHROPIC_API_KEY) {
        const envContent = fs.readFileSync(envPath, 'utf8');
        const lines = envContent.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
                const [key, ...valueParts] = trimmed.split('=');
                const value = valueParts.join('=');
                if (key && value && key.startsWith('ANTHROPIC_')) {
                    process.env[key] = value;
                }
            }
        }
        console.log('[SSH] Environment loaded from .env');
    }

    try {
        const nodeFetch = require(process.env.HOME + '/Claude/node_modules/node-fetch');
        const { Readable } = require('stream');

        // Store original Response class
        const OriginalResponse = nodeFetch.Response;

        // Create a custom Response class that handles stream conversion properly
        class CustomResponse extends OriginalResponse {
            constructor(body, init) {
                super(body, init);
                this._nodeStream = body; // Store original Node stream
                this._webStream = null;  // Lazy-initialized web stream
            }

            // Override body getter to return Web ReadableStream when needed
            get body() {
                // If already converted, return cached web stream
                if (this._webStream) {
                    return this._webStream;
                }

                // If this is a Node stream, convert to Web ReadableStream
                // But DON'T consume it - use a tee/clone approach
                if (this._nodeStream && typeof Readable.toWeb === 'function') {
                    // Clone the stream before conversion to avoid consuming it
                    // Node.js streams can't be cloned, so we buffer the content
                    // Alternative: Create a pass-through that copies data

                    // For MCP SDK compatibility, return web stream
                    // But text()/json() will read from buffer, not from stream
                    this._webStream = Readable.toWeb(this._nodeStream);
                    this._webStream.cancel = async function(reason) {
                        const reader = this._webStream.getReader();
                        await reader.cancel(reason);
                    };
                    return this._webStream;
                }

                // Fallback: return null or original body
                return null;
            }

            // Override text() to use node-fetch's original implementation
            async text() {
                // Use node-fetch's buffer method which handles Node streams correctly
                const buffer = await this.buffer();
                return buffer.toString('utf-8');
            }

            // Override json() to use our text() method
            async json() {
                const text = await this.text();
                return JSON.parse(text);
            }

            // Override buffer() to properly handle Node streams
            async buffer() {
                if (this._nodeStream) {
                    // Read from Node stream directly
                    return new Promise((resolve, reject) => {
                        const chunks = [];
                        this._nodeStream.on('data', chunk => chunks.push(chunk));
                        this._nodeStream.on('end', () => resolve(Buffer.concat(chunks)));
                        this._nodeStream.on('error', reject);
                    });
                }
                return super.buffer();
            }
        }

        // Simple polyfill - just wrap node-fetch and return CustomResponse
        globalThis.fetch = async function(url, opts) {
            const response = await nodeFetch(url, opts);
            // Return a CustomResponse that wraps the original
            return new CustomResponse(response.body, {
                status: response.status,
                statusText: response.statusText,
                headers: response.headers
            });
        };

        globalThis.Headers = nodeFetch.Headers;
        globalThis.Request = nodeFetch.Request;
        globalThis.Response = CustomResponse;

        console.log('[SSH] fetch polyfill loaded successfully (CustomResponse with lazy stream conversion)');
    } catch (e) {
        console.error('[SSH] Failed to load node-fetch:', e.message);
        console.error('[SSH] Stack:', e.stack);
    }
}
```

**Critical bug fixes**:

1. **Polyfill condition**: The original condition `typeof globalThis.fetch === 'undefined' || typeof WebAssembly === 'undefined'` was WRONG. In `--jitless` mode:
   - `globalThis.fetch` EXISTS (it's a function)
   - `WebAssembly` is UNDEFINED
   - Native fetch exists but fails silently when called (returns "fetch failed" TypeError)

   The polyfill must check `WebAssembly === undefined` ONLY, not `fetch === undefined`.

2. **ANTHROPIC_AUTH_TOKEN empty string**: Do NOT set `export ANTHROPIC_AUTH_TOKEN=''` (empty string).
   - SDK checks `if (this.authToken == null)` to decide authentication method
   - Empty string `''` is NOT `null`, so SDK sends `Authorization: Bearer ''`
   - LiteLLM rejects empty Bearer token with 401 Unauthorized
   - Solution: Use `unset ANTHROPIC_AUTH_TOKEN` instead of setting empty string

3. **CustomResponse class for stream conversion** (CRITICAL for MCP, CRITICAL BUG FIX 2026-05-20):
   - `Readable.toWeb()` consumes the original Node stream, breaking `text()`/`json()` calls
   - node-fetch@2 Response.body is a Node.js Readable stream (PassThrough), NOT Web ReadableStream
   - MCP SDK uses Web Streams API: `body.pipeThrough(new TextDecoderStream).pipeThrough(new EventSourceParserStream).getReader()`
   - Node.js stream lacks `pipeThrough` and `getReader` methods
   - Solution: Use `CustomResponse` class that handles stream conversion lazily
   - Override `text()`/`json()`/`buffer()` to read from original Node stream
   - Override `body` getter to return Web ReadableStream when accessed directly
   - This ensures both MCP SDK (Web Streams) and standard `text()/json()` work correctly

4. **Response.body.cancel()**: Web ReadableStream's reader has `cancel()`, but SDK may call `body.cancel()` directly.
   - Add `webStream.cancel = async function() { reader.cancel() }` as fallback

5. **SSH remote execution env vars** (CRITICAL): Shell `source ~/.claude/.env` doesn't pass vars to Node.js.
   - SSH non-interactive shell runs in a separate process
   - `source` sets vars in shell, but Node.js child process doesn't inherit them
   - Result: API calls fail with 401 because `ANTHROPIC_API_KEY` is undefined
   - Solution: Polyfill must read `.env` file directly and set `process.env` before fetch

**Additional notes**:
- `--lite-mode` also disables WebAssembly, same issue as `--jitless`
- Do NOT use `NODE_OPTIONS` in SSH sessions (causes same crash)
- Use hardcoded paths instead of command substitution (`$(...)`)
- LLM API requests may take 30-60 seconds - ensure adequate timeout

## Files Produced

| Binary | Size | Purpose |
|--------|------|---------|
| dropbear | 285KB | SSH server |
| dbclient | 273KB | SSH client |
| dropbearkey | 187KB | Key generation |
| dropbearconvert | 195KB | Key format conversion |

## Comparison with OpenSSH

| Feature | Dropbear | OpenSSH |
|---------|----------|---------|
| Binary size | ~1MB total | ~4MB+ |
| Configure complexity | Manual Makefile | Complex autoconf |
| Password auth | Not supported (no crypt) | Requires crypt |
| Build time | ~5 min | ~15+ min |
| Dependencies | Bundled libtomcrypt | OpenSSL headers |
| HarmonyOS patches | 5 source files | More complex |

Dropbear is recommended for HarmonyOS due to simpler build process and bundled crypto libraries.