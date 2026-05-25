# OpenSSH 9.9p1 Build Guide for HarmonyOS

Step-by-step build instructions and source patches for OpenSSH 9.9p1 on HarmonyOS (HongMeng Kernel 1.12.0, aarch64, musl libc).

## Prerequisites

- OpenSSL 3.0.16 (static, built from source)
- clang 15.0.4 (HarmonyOS SDK)
- ld.bfd wrapper at `$HOME/Claude/lib/linker_wrapper/ld.lld`
- bash (SDK, required for configure — toybox sh fails)
- zlib headers (SDK sysroot)

## Patches Summary

| # | File | Function / Area | Fix |
|---|------|-----------------|-----|
| 1 | loginrec.c | `utmpx_write_direct()` | `&ut` → `&utx` (upstream bug) |
| 2 | openbsd-compat/Makefile | PORTS list | Remove port-net.o (linux/if.h sockaddr_storage conflict) |
| 3 | sshd-session.c | `privsep_preauth_child()` | chroot non-fatal; skip setgroups + permanently_set_uid when chroot fails |
| 4 | uidswap.c | `setegid()` / `seteuid()` | Change `fatal` → `debug` (user-space cannot call these) |
| 5 | sandbox-rlimit.c | `setrlimit(RLIMIT_NPROC)` | Change `fatal` → `debug` + add SANDBOX_SKIP_RLIMIT_FSIZE/NOFILE |
| 6 | platform-misc.c | `platform_sys_dir_uid()` | Accept uid 20001006 (file_manager) as system owner |
| 7 | misc.c | `safe_path()` | Skip mode check (022 bitmask) for system-owned files/dirs |
| 8 | misc.c | `unix_listener()` | EPERM fallback: bind to abstract namespace socket |
| 9 | ssh-agent.c | Post-`unix_listener()` | Detect abstract fallback via stat ENOENT; set `abstract:` prefix |
| 10 | authfd.c | `ssh_get_authentication_socket_path()` | Handle `abstract:` prefix: connect via abstract namespace |
| 11 | passwd_compat.c | `getpwnam()` | Accept chenh/chenjh/currentUser/user → same uid 20020106 |
| 12 | session.c | `do_setup_env()` | Preserve LD_PRELOAD + LD_LIBRARY_PATH in child env |

## Step 1: Build OpenSSL 3.0.16

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

make -j1  # make -j fails on HarmonyOS (mkfifo EPERM)
make install
```

Copy zlib headers from SDK sysroot:
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

### Run configure (must use bash, not toybox sh)

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

HarmonyOS setgid on directories makes mktemp subdirs owned by uid 20001006 (file_manager), not our uid 20020106. Writing fails with "Permission denied".

```bash
mkdir -p $HOME/Claude/openssh-build/openssh-9.9p1/cs_tmp
chmod 777 cs_tmp
```

Edit `config.status` — replace mktemp block (~line 573):
```bash
# From:
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

Remove cleanup trap:
```bash
# From:
{ test ! -d "$ac_tmp" || rm -fr "$ac_tmp"; } && exit $exit_status
# To:
exit $exit_status
```

Run patched config.status:
```bash
/data/service/hnp/bin/bash config.status
```

## Step 3: Post-Configure config.h Fixes

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1

# DISABLE_SHADOW — musl lacks getspnam()
sed -i 's|^/\* #undef DISABLE_SHADOW \*/$|#define DISABLE_SHADOW 1|' config.h

# DISABLE_WTMP — musl lacks logwtmp/updwtmp/logout()
sed -i 's|^/\* #undef DISABLE_WTMP \*/$|#define DISABLE_WTMP 1|' config.h

# Disable SSH_TUN — linux/if.h conflicts with sys/socket.h
sed -i 's|^#define SSH_TUN_LINUX 1$|/* #undef SSH_TUN_LINUX */|' config.h
sed -i 's|^#define SSH_TUN_COMPAT_AF 1$|/* #undef SSH_TUN_COMPAT_AF */|' config.h
sed -i 's|^#define SSH_TUN_PREPEND_AF 1$|/* #undef SSH_TUN_PREPEND_AF */|' config.h

# SANDBOX_RLIMIT instead of SECCOMP_FILTER — linux headers conflict with musl
sed -i 's|^#define SANDBOX_SECCOMP_FILTER 1$|/* #undef SANDBOX_SECCOMP_FILTER */|' config.h
sed -i 's|^/\* #undef SANDBOX_RLIMIT \*/$|#define SANDBOX_RLIMIT 1|' config.h

# Sandbox skip flags
echo '#define SANDBOX_SKIP_RLIMIT_FSIZE 1' >> config.h
echo '#define SANDBOX_SKIP_RLIMIT_NOFILE 1' >> config.h
```

## Step 4: Apply Source Patches

Apply patches 1-12 per the Patches Summary table above. Key details:

**Patch 3** — sshd-session.c `privsep_preauth_child()`: When chroot fails, set `privsep_chroot = 0` and skip `setgroups` + `permanently_set_uid` block entirely.

**Patch 6** — platform-misc.c `platform_sys_dir_uid()`: Add `if (uid == 20001006) return 1;` so file_manager uid is treated as system owner.

**Patch 7** — misc.c `safe_path()`: Wrap mode checks with `!platform_sys_dir_uid()`:
```c
(!platform_sys_dir_uid(stp->st_uid) && (stp->st_mode & 022) != 0)
```

**Patch 8** — misc.c `unix_listener()`: On bind EPERM, close socket, create new PF_UNIX socket, set `sun_path[0] = '\0'`, snprintf name `ssh-agent.<pid>` into `sun_path+1`, bind + listen, return.

**Patch 9** — ssh-agent.c: After `unix_listener()`, if `stat(socket_name)` returns ENOENT, set `socket_name` to `abstract:ssh-agent.<pid>`.

**Patch 10** — authfd.c: If `authsocket` starts with `abstract:`, skip 9 chars, set `sun_path[0] = '\0'`, copy rest into `sun_path+1`.

**Patch 11** — passwd_compat.c `getpwnam()`: Map all username variants to same entry.

**Patch 12** — session.c `do_setup_env()`: After TZ copy, add LD_PRELOAD and LD_LIBRARY_PATH preservation. Also add `SetEnv PATH=...` in sshd_config.

## Step 5: Build

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

## Step 7: Build passwd_compat LD_PRELOAD Library

```c
// passwd_compat.c — save to $HOME/Claude/openssh-build/passwd_compat/passwd_compat.c
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
    if (strcmp(name, "chenh") == 0 || strcmp(name, "chenjh") == 0 ||
        strcmp(name, "currentUser") == 0 || strcmp(name, "user") == 0)
        return &chenh_pw;
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

## sshd_config Example

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
SetEnv PATH=/storage/Users/currentUser/Claude/openssh-build/openssh-prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:/storage/Users/currentUser/.local/bin
```

Key notes:
- `StrictModes yes` works due to patches 6+7 (file_manager uid accepted as system owner, mode check skipped)
- HostKey/PidFile in `$HOME/Claude/tmpdir/` because `/tmp` is read-only on HarmonyOS
- `SetEnv PATH` ensures scp/sftp use our built binaries, not system ones that crash