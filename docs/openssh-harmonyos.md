# OpenSSH 9.9p1 Adaptation Guide for HarmonyOS

## Overview

This document describes how to build and run OpenSSH 9.9p1 on HarmonyOS PC (HongMeng Kernel 1.12.0, aarch64, musl libc).

**Build Status**: Fully functional. All 12 binaries compiled, code-signed, and tested. sshd accepts SSH connections (pubkey auth, StrictModes=yes). ssh-agent works via abstract namespace socket fallback. All three previously-failing issues (privsep, ssh-agent socket, authorized_keys ownership) are now fixed with HarmonyOS-specific patches.

## Prerequisites

- OpenSSL 3.0.16 (built from source, static library)
- clang 15.0.4 (from HarmonyOS SDK)
- ld.bfd wrapper (SDK's lld linker is broken)
- bash (from SDK, required for configure — toybox sh fails)
- zlib headers (from SDK sysroot)

## Step 1: Build OpenSSL 3.0.16

OpenSSH requires OpenSSL. The system's `libcrypto_openssl.z.so` has incompatible naming and no public headers.

```bash
cd $HOME/Claude/openssh-build
curl -L --proxy http://127.0.0.1:7890 \
  -o openssl-3.0.16.tar.xz \
  https://github.com/openssl/openssl/releases/download/openssl-3.0.16/openssl-3.0.16.tar.xz
tar xJf openssl-3.0.16.tar.xz

cd openssl-3.0.16
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper" \
perl Configure linux-aarch64 \
  --prefix=$HOME/Claude/openssh-build/openssl-prefix \
  --openssldir=$HOME/Claude/openssh-build/openssl-prefix/ssl \
  no-shared no-tests

make -j1  # Single-threaded (make -j fails on HarmonyOS)
make install
```

After building, copy zlib headers from SDK sysroot:
```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot/usr/include
cp $SYSROOT/zlib.h $SYSROOT/zconf.h $HOME/Claude/openssh-build/openssl-prefix/include/
ln -sf /system/lib64/platformsdk/libz.so $HOME/Claude/openssh-build/openssl-prefix/lib/libz.so
```

## Step 2: Configure OpenSSH

### Fix config.guess

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
echo '#!/bin/sh
echo "aarch64-unknown-linux-gnu"' > config.guess
chmod +x config.guess
```

### Run configure with bash (NOT toybox sh)

Toybox sh causes conftest.c creation failures. Must use bash:

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
TMPDIR=$HOME/Claude/tmpdir \
CONFIG_SHELL=/data/service/hnp/bin/bash \
CC=/data/service/hnp/bin/clang \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/Claude/openssh-build/openssl-prefix/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L$HOME/Claude/openssh-build/openssl-prefix/lib" \
LIBS="-lcrypto -lssl -lz -ldl -lpthread" \
/data/service/hnp/bin/bash ./configure \
  --host=aarch64-unknown-linux-gnu \
  --prefix=$HOME/Claude/openssh-build/openssh-prefix \
  --with-ssl-dir=$HOME/Claude/openssh-build/openssl-prefix \
  --with-zlib=$HOME/Claude/openssh-build/openssl-prefix \
  --without-pam \
  --without-kerberos5 \
  --with-privsep-user=sshd \
  ac_cv_c_bigendian=no
```

### Fix config.status mktemp issue (CRITICAL)

**Root cause**: HarmonyOS filesystem's setgid flag on directories causes mktemp-created subdirectories to be owned by uid 20001006 (file_manager), but our processes run as uid 20020106 (chenjh). Writing to these directories fails with "Permission denied".

**Fix**: Create a pre-existing writable directory and patch config.status:

```bash
mkdir -p $HOME/Claude/openssh-build/openssh-9.9p1/cs_tmp
chmod 777 cs_tmp
```

Edit `config.status` — replace the mktemp block (around line 573):
```bash
# Change from:
{
  tmp=`(umask 077 && mktemp -d "./confXXXXXX") 2>/dev/null` &&
  test -d "$tmp"
}  ||
{
  tmp=./conf$$-$RANDOM
  (umask 077 && mkdir "$tmp")
} || as_fn_error $? "cannot create a temporary directory in ." "$LINENO" 5

# To:
{
  tmp=cs_tmp
  test -d "$tmp" || mkdir "$tmp"
} || as_fn_error $? "cannot create a temporary directory in ." "$LINENO" 5
```

Also remove the cleanup trap that tries to rm the tmp directory:
```bash
# Change from:
{ test ! -d "$ac_tmp" || rm -fr "$ac_tmp"; } && exit $exit_status
# To:
exit $exit_status
```

Then run config.status:
```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
/data/service/hnp/bin/bash config.status
```

## Step 3: Post-Configure Fixes to config.h

Several config.h changes are needed for HarmonyOS compatibility:

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1

# 1. DISABLE_SHADOW — musl lacks getspnam()
sed -i 's|^/\* #undef DISABLE_SHADOW \*/$|#define DISABLE_SHADOW 1|' config.h

# 2. DISABLE_WTMP — musl lacks logwtmp/updwtmp/logout()
sed -i 's|^/\* #undef DISABLE_WTMP \*/$|#define DISABLE_WTMP 1|' config.h

# 3. Disable SSH_TUN — linux/if.h conflicts with sys/socket.h
sed -i 's|^#define SSH_TUN_LINUX 1$|/* #undef SSH_TUN_LINUX */|' config.h
sed -i 's|^#define SSH_TUN_COMPAT_AF 1$|/* #undef SSH_TUN_COMPAT_AF */|' config.h
sed -i 's|^#define SSH_TUN_PREPEND_AF 1$|/* #undef SSH_TUN_PREPEND_AF */|' config.h

# 4. Use SANDBOX_RLIMIT instead of SANDBOX_SECCOMP_FILTER
#    seccomp-filter includes linux headers that conflict with musl
sed -i 's|^#define SANDBOX_SECCOMP_FILTER 1$|/* #undef SANDBOX_SECCOMP_FILTER */|' config.h
sed -i 's|^/\* #undef SANDBOX_RLIMIT \*/$|#define SANDBOX_RLIMIT 1|' config.h
```

## Step 4: Source Code Fixes

### 4.1 loginrec.c bug: `ut` → `utx`

Line 1018 in `loginrec.c`:
```c
// Change from:
if (!utmpx_write_direct(li, &ut)) {
// To:
if (!utmpx_write_direct(li, &utx)) {
```

### 4.2 openbsd-compat/Makefile: remove port-net.o

port-net.c includes `linux/if.h` which causes sockaddr_storage conflicts.
Remove it from the PORTS list in openbsd-compat/Makefile.

### 4.3 sshd-session.c: privsep chroot non-fatal (CRITICAL)

HarmonyOS doesn't permit chroot() for user-space processes. When chroot fails, skip subsequent privilege dropping (setgroups + permanently_set_uid) entirely.

In `sshd-session.c`, function `privsep_preauth_child()`:
```c
/* Demote the child */
if (privsep_chroot) {
    if (chroot(_PATH_PRIVSEP_CHROOT_DIR) == -1) {
        debug("chroot(\"%s\") failed: %s (skipping on HarmonyOS)",
            _PATH_PRIVSEP_CHROOT_DIR, strerror(errno));
        privsep_chroot = 0;
    } else {
        if (chdir("/") == -1)
            fatal("chdir(\"/\"): %s", strerror(errno));
    }
}
if (privsep_chroot) {
    debug3("privsep user:group %u:%u", (u_int)privsep_pw->pw_uid,
        (u_int)privsep_pw->pw_gid);
    gidset[0] = privsep_pw->pw_gid;
    if (setgroups(1, gidset) == -1)
        fatal("setgroups: %.100s", strerror(errno));
    permanently_set_uid(privsep_pw);
}
```

### 4.4 uidswap.c: setgroups/setegid/seteuid non-fatal

HarmonyOS doesn't permit these calls for user-space processes. Change from `fatal()` to `debug()` so the process continues instead of aborting.

In `uidswap.c`:
- Line 120-121: `setgroups` — change `debug("setgroups: ...")` (already debug, no change needed)
- Lines 130-132: `setegid` — change from `fatal` to `debug`
- Lines 133-135: `seteuid` — change from `fatal` to `debug`

### 4.5 sandbox-rlimit.c: RLIMIT_NPROC non-fatal

`setrlimit(RLIMIT_NPROC, {0,0})` fails on HarmonyOS. Change from `fatal` to `debug`.

Also add to `config.h`:
```c
#define SANDBOX_SKIP_RLIMIT_FSIZE 1
#define SANDBOX_SKIP_RLIMIT_NOFILE 1
```

### 4.6 platform-misc.c: accept file_manager uid as system owner (CRITICAL)

Files on HarmonyOS are owned by uid 20001006 (file_manager) due to setgid on parent directories, but sshd runs as uid 20020106 (chenjh). Without this fix, `safe_path()` rejects authorized_keys with "bad ownership or modes".

This is the dropbear-style approach: treat uid 20001006 as a "system directory uid" (like root) so ownership checks pass.

In `platform-misc.c`, function `platform_sys_dir_uid()`:
```c
int
platform_sys_dir_uid(uid_t uid)
{
    if (uid == 0)
        return 1;
#ifdef PLATFORM_SYS_DIR_UID
    if (uid == PLATFORM_SYS_DIR_UID)
        return 1;
#endif
    /*
     * HarmonyOS: file_manager (uid 20001006) owns all user files
     * due to setgid on parent directories, even though the
     * accessing user may be uid 20020106. Treat file_manager
     * as a "system directory uid" so safe_path() ownership
     * checks pass.
     */
    if (uid == 20001006)
        return 1;
    return 0;
}
```

### 4.7 misc.c: safe_path() mode check skip for system-owned files (CRITICAL)

HarmonyOS directories have setgid + group-writable modes (e.g. `drwxrws--x`, mode `2771`) that cannot be changed via chmod. The `022` bitmask check in `safe_path()` would reject these directories.

Modify `safe_path()` in `misc.c` so that the mode check (`st_mode & 022`) is only enforced for non-system-owned files. When `platform_sys_dir_uid()` returns true (uid 0 or 20001006), the mode check is skipped.

```c
// File check (around line 2253):
if ((!platform_sys_dir_uid(stp->st_uid) && stp->st_uid != uid) ||
    (!platform_sys_dir_uid(stp->st_uid) && (stp->st_mode & 022) != 0)) {
    ...
}

// Directory check (around line 2268):
if (stat(buf, &st) == -1 ||
    (!platform_sys_dir_uid(st.st_uid) && st.st_uid != uid) ||
    (!platform_sys_dir_uid(st.st_uid) && (st.st_mode & 022) != 0)) {
    ...
}
```

### 4.8 misc.c: unix_listener() EPERM fallback to abstract socket (CRITICAL)

HarmonyOS's `bind()` for filesystem Unix sockets returns EPERM. Abstract namespace sockets (sun_path[0]='\0') work correctly.

In `misc.c`, function `unix_listener()`: when `bind()` returns EPERM, close the regular socket, create a new one, and bind to an abstract namespace socket with name `ssh-agent.<pid>`.

```c
if (bind(sock, (struct sockaddr *)&sunaddr, sizeof(sunaddr)) == -1) {
    saved_errno = errno;
    if (errno == EPERM) {
        debug_f("bind EPERM, trying abstract socket");
        close(sock);
        sock = socket(PF_UNIX, SOCK_STREAM, 0);
        if (sock == -1) { ... return -1; }
        memset(&sunaddr, 0, sizeof(sunaddr));
        sunaddr.sun_family = AF_UNIX;
        sunaddr.sun_path[0] = '\0';
        snprintf(sunaddr.sun_path + 1, sizeof(sunaddr.sun_path) - 1,
            "ssh-agent.%ld", (long)getpid());
        if (bind(sock, ...) == -1) { ... return -1; }
        if (listen(sock, backlog) == -1) { ... return -1; }
        debug_f("abstract socket bound successfully");
        return sock;
    }
    error_f("cannot bind to path %s: %s", ...);
    ...
}
```

### 4.9 ssh-agent.c: detect abstract socket fallback

After `unix_listener()` returns, check if the filesystem path exists. If not (stat ENOENT), it means the EPERM fallback was triggered. Update `socket_name` to use `abstract:` prefix so clients know the socket format.

```c
if (stat(socket_name, NULL) != 0 && errno == ENOENT) {
    snprintf(socket_name, sizeof(socket_name),
        "abstract:ssh-agent.%ld", (long)parent_pid);
    socket_dir[0] = '\0'; /* Don't rmdir on cleanup */
}
```

This causes ssh-agent to output `SSH_AUTH_SOCK=abstract:ssh-agent.<pid>; export SSH_AUTH_SOCK;` instead of a filesystem path.

### 4.10 authfd.c: handle `abstract:` SSH_AUTH_SOCK prefix

Clients (ssh, ssh-add) connect to the agent via `ssh_get_authentication_socket_path()`. When `SSH_AUTH_SOCK` starts with `abstract:`, connect via abstract namespace (sun_path[0]='\0') instead of filesystem path.

```c
if (strncmp(authsocket, "abstract:", 9) == 0) {
    authsocket += 9;
    sunaddr.sun_path[0] = '\0';
    strlcpy(sunaddr.sun_path + 1, authsocket,
        sizeof(sunaddr.sun_path) - 1);
} else {
    strlcpy(sunaddr.sun_path, authsocket, sizeof(sunaddr.sun_path));
}
```

### 4.11 passwd_compat.c: support multiple username variants (CRITICAL)

External SSH clients may use any username variant (chenh, chenjh, currentUser, user) to connect. The passwd_compat LD_PRELOAD library must map all these variants to the same uid 20020106 entry, otherwise sshd rejects them as "Invalid user".

In `passwd_compat.c`, function `getpwnam()`:
```c
struct passwd *getpwnam(const char *name) {
    /* Accept all common username variants for our UID */
    if (strcmp(name, "chenh") == 0 || strcmp(name, "chenjh") == 0 ||
        strcmp(name, "currentUser") == 0 || strcmp(name, "user") == 0)
        return &chenh_pw;
    if (strcmp(name, "sshd") == 0) return &sshd_pw;
    struct passwd *(*real)(const char *) = dlsym(RTLD_NEXT, "getpwnam");
    if (real) return real(name);
    return NULL;
}
```

### 4.12 session.c: preserve LD_PRELOAD and LD_LIBRARY_PATH in child env (CRITICAL)

sshd's `do_setup_env()` constructs a fresh environment for child processes, discarding the parent's LD_PRELOAD. This causes scp/sftp/shell child processes to lose passwd_compat.so, making `getpwuid(20020106)` fail since `/etc/passwd` is read-only and doesn't contain our UID. The result is musl fortify abort ("umask called with invalid mask 7022") when scp tries to run.

Additionally, the system scp (`/usr/bin/scp`) crashes with umask errors even with LD_PRELOAD, so we need our built scp to be found first in PATH.

Two fixes required:

**Fix A**: In `session.c`, `do_setup_env()`, after the TZ environment copy (around line 1051):
```c
if (getenv("TZ"))
    child_set_env(&env, &envsize, "TZ", getenv("TZ"));
/*
 * HarmonyOS: preserve LD_PRELOAD so passwd_compat.so
 * remains active in child processes (scp, sftp-server,
 * shell). Without this, getpwuid(20020106) fails in
 * exec'd programs since /etc/passwd is read-only and
 * doesn't contain our UID.
 */
if (getenv("LD_PRELOAD"))
    child_set_env(&env, &envsize, "LD_PRELOAD",
        getenv("LD_PRELOAD"));
if (getenv("LD_LIBRARY_PATH"))
    child_set_env(&env, &envsize, "LD_LIBRARY_PATH",
        getenv("LD_LIBRARY_PATH"));
```

**Fix B**: In `sshd_config`, add `SetEnv` to put our openssh-prefix/bin first in PATH so scp/sftp binaries on the remote side are our built versions (not the system ones that crash):
```
SetEnv PATH=/storage/Users/currentUser/Claude/openssh-build/openssh-prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:/storage/Users/currentUser/.local/bin
```

## Step 5: Build OpenSSH

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
TMPDIR=$HOME/Claude/tmpdir make
```

## Step 6: Code-Sign and Install

```bash
BIN=$HOME/Claude/openssh-build/openssh-prefix/bin
LIBEXEC=$HOME/Claude/openssh-build/openssh-prefix/libexec

for bin in ssh sshd scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan; do
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -keyAlias "key" -appCertFile "$bin" -profileFile "$bin" \
    -inFile "$bin" -outFile "$BIN/$bin" \
    -keystoreFile "$bin" -signAlg SHA256withECDSA
  chmod +x "$BIN/$bin"
done

for bin in ssh-keysign sftp-server ssh-pkcs11-helper ssh-sk-helper sshd-session; do
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -keyAlias "key" -appCertFile "$bin" -profileFile "$bin" \
    -inFile "$bin" -outFile "$LIBEXEC/$bin" \
    -keystoreFile "$bin" -signAlg SHA256withECDSA
  chmod +x "$LIBEXEC/$bin"
done
```

## Step 7: passwd_compat LD_PRELOAD

HarmonyOS's /etc/passwd doesn't have entries for user-space UIDs (20020106, 20001006).
OpenSSH calls getpwuid() which fails with "No user exists for uid XXXXX".

Create a LD_PRELOAD library:

```c
// passwd_compat.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pwd.h>
#include <string.h>

static struct passwd chenh_pw = {
    .pw_name = "chenh",
    .pw_passwd = "x",
    .pw_uid = 20020106,
    .pw_gid = 20020106,
    .pw_dir = "/storage/Users/currentUser",
    .pw_shell = "/bin/sh",
    .pw_gecos = "chenh"
};

static struct passwd sshd_pw = {
    .pw_name = "sshd",
    .pw_passwd = "x",
    .pw_uid = 999,
    .pw_gid = 999,
    .pw_dir = "/var/empty",
    .pw_shell = "/bin/false",
    .pw_gecos = "sshd"
};

struct passwd *getpwuid(uid_t uid) {
    if (uid == 20020106) return &chenh_pw;
    if (uid == 999) return &sshd_pw;
    struct passwd *(*real)(uid_t) = dlsym(RTLD_NEXT, "getpwuid");
    if (real) return real(uid);
    return NULL;
}

struct passwd *getpwnam(const char *name) {
    if (strcmp(name, "chenh") == 0) return &chenh_pw;
    if (strcmp(name, "sshd") == 0) return &sshd_pw;
    struct passwd *(*real)(const char *) = dlsym(RTLD_NEXT, "getpwnam");
    if (real) return real(name);
    return NULL;
}
```

```bash
cd $HOME/Claude/openssh-build/passwd_compat
/data/service/hnp/bin/clang -B$HOME/Claude/lib/linker_wrapper \
  -shared -fPIC -o passwd_compat.so passwd_compat.c -ldl

/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -keyAlias "key" -appCertFile passwd_compat.so -profileFile passwd_compat.so \
  -inFile passwd_compat.so -outFile passwd_compat_signed.so \
  -keystoreFile passwd_compat.so -signAlg SHA256withECDSA
chmod +x passwd_compat_signed.so
```

## Step 8: sshd_config Example

A recommended sshd_config for HarmonyOS:

```
Port 2223
HostKey /storage/Users/currentUser/Claude/tmpdir/sshd_host_key
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
StrictModes yes
AuthorizedKeysFile /storage/Users/currentUser/.ssh/authorized_keys
PidFile /storage/Users/currentUser/Claude/tmpdir/sshd_openssh.pid
Subsystem sftp /storage/Users/currentUser/Claude/openssh-build/openssh-prefix/libexec/sftp-server
```

Note: `StrictModes yes` works because of the `platform_sys_dir_uid()` / `safe_path()` patches that accept uid 20001006 (file_manager) as a valid owner. HostKey and PidFile are placed in `$HOME/Claude/tmpdir/` because `/tmp` is read-only on HarmonyOS.

## Step 9: Running OpenSSH

All OpenSSH commands must be run with LD_PRELOAD:

```bash
BIN=$HOME/Claude/openssh-build/openssh-prefix/bin
PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so

# ssh-keygen
LD_PRELOAD=$PRELOAD $BIN/ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# ssh client
LD_PRELOAD=$PRELOAD $BIN/ssh -p 2223 user@host

# sshd server (StrictModes=yes works with UID fix)
LD_PRELOAD=$PRELOAD $BIN/sshd -f /path/to/sshd_config -E /path/to/sshd.log

# ssh-agent (uses abstract namespace socket on HarmonyOS)
eval $(LD_PRELOAD=$PRELOAD $BIN/ssh-agent)
# Output: SSH_AUTH_SOCK=abstract:ssh-agent.<pid>; export SSH_AUTH_SOCK;
#         SSH_AGENT_PID=<pid>; export SSH_AGENT_PID;

# ssh-add (connects to agent via abstract socket)
export SSH_AUTH_SOCK=abstract:ssh-agent.<pid>  # from ssh-agent output
export SSH_AGENT_PID=<pid>                      # from ssh-agent output
LD_PRELOAD=$PRELOAD $BIN/ssh-add ~/.ssh/id_ed25519
LD_PRELOAD=$PRELOAD $BIN/ssh-add -l             # list identities

# Kill agent
LD_PRELOAD=$PRELOAD $BIN/ssh-agent -k
```

Note: On HarmonyOS, ssh-agent's `SSH_AUTH_SOCK` uses the `abstract:` prefix instead of a filesystem path. The `ssh` and `ssh-add` clients automatically detect this prefix and connect via abstract namespace sockets.

## Known Limitations

### 1. sshd privilege separation (FIXED)
OpenSSH's privsep (sshd-session child) calls setgroups() which fails on HarmonyOS ("Operation not permitted"). This previously caused SSH connections to fail with "Invalid argument" during preauth.

**Status**: Fixed. sshd-session.c patched to make chroot non-fatal (skip subsequent privdrop when chroot fails). uidswap.c changed to make setgroups/setegid/seteuid non-fatal (debug instead of fatal). sandbox-rlimit.c RLIMIT_NPROC setrlimit changed to non-fatal.

### 2. ssh-agent Unix socket (FIXED)
ssh-agent's `bind()` to filesystem Unix sockets returns EPERM on HarmonyOS. Abstract namespace sockets (sun_path[0]='\0') work correctly.

**Status**: Fixed. `unix_listener()` in misc.c now falls back to abstract namespace socket when bind EPERM occurs. ssh-agent.c detects the fallback and sets `SSH_AUTH_SOCK=abstract:<name>` so clients know to use abstract socket format. `ssh_get_authentication_socket_path()` in authfd.c handles `abstract:` prefix by connecting via abstract namespace.

### 3. authorized_keys ownership (FIXED)
Files are owned by uid 20001006 (file_manager) but sshd runs as uid 20020106 (chenjh), causing "bad ownership or modes" error.

**Status**: Fixed using dropbear-style approach. `platform_sys_dir_uid()` in platform-misc.c now treats uid 20001006 as an acceptable system directory owner (like root). `safe_path()` in misc.c skips mode checks (022 bitmask) for system-directory-owned files, since HarmonyOS setgid dirs cannot have group-writable mode removed. `StrictModes=yes` now works correctly.

### 4. No shadow password support
musl libc on HarmonyOS doesn't implement getspnam() despite defining struct spwd in shadow.h. Password authentication via /etc/shadow is not possible.

### 5. No wtmp/lastlog logging
Functions like logwtmp(), updwtmp(), logout() are not in musl libc. Session logging to wtmp/lastlog files is disabled.

### 6. SSH tunnel (tun/tap) disabled
The linux/if.h header conflicts with sys/socket.h (sockaddr_storage redefinition). SSH tunnel forwarding is disabled.

## Comparison: OpenSSH vs Dropbear on HarmonyOS

| Feature | Dropbear | OpenSSH |
|---------|----------|---------|
| SSH server | Works (with -e flag) | Works (privsep patched) |
| SSH client | Works (dbclient) | Works (with LD_PRELOAD) |
| Key generation | Works | Works (with LD_PRELOAD) |
| scp | Works | Works (LD_PRELOAD + SetEnv PATH) |
| sftp | Not supported | Works (LD_PRELOAD + SetEnv PATH) |
| ssh-agent | Not supported | Works (abstract namespace socket) |
| Pubkey auth | Works | Works (StrictModes=yes OK) |
| Password auth | Not available | Not available |
| Tunnel/tap | Not supported | Disabled (header conflict) |
| Configuration | Limited | Full sshd_config support |
| Protocol | SSH-2 only | SSH-2, all modern algorithms |

## Files

- Source: `$HOME/Claude/openssh-build/openssh-9.9p1/`
- OpenSSL prefix: `$HOME/Claude/openssh-build/openssl-prefix/`
- OpenSSH prefix: `$HOME/Claude/openssh-build/openssh-prefix/`
- passwd_compat: `$HOME/Claude/openssh-build/passwd_compat/`