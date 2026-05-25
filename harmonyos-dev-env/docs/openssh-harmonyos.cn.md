# HarmonyOS 上 OpenSSH 9.9p1 适配指南

## 概述

本文档描述如何在 HarmonyOS PC（鸿蒙内核 1.12.0，aarch64，musl libc）上构建和运行 OpenSSH 9.9p1。

**构建状态**：完全可用。全部 12 个二进制文件已编译、代码签名并测试。sshd 可接受 SSH 连接（公钥认证，StrictModes=yes）。ssh-agent 通过抽象命名空间 socket 回退机制正常工作。此前三个失败问题（privsep、ssh-agent socket、authorized_keys 所有权）均已通过 HarmonyOS 特定补丁修复。

## 前置条件

- OpenSSL 3.0.16（从源码构建，静态库）
- clang 15.0.4（来自 HarmonyOS SDK）
- ld.bfd 包装器（SDK 的 lld 链接器已损坏）
- bash（来自 SDK，configure 需要它 — toybox sh 会失败）
- zlib 头文件（来自 SDK sysroot）

## 步骤 1：构建 OpenSSL 3.0.16

OpenSSH 需要 OpenSSL。系统的 `libcrypto_openssl.z.so` 命名不兼容且没有公共头文件。

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

make -j1  # 单线程构建（HarmonyOS 上 make -j 会失败）
make install
```

构建完成后，从 SDK sysroot 复制 zlib 头文件：
```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot/usr/include
cp $SYSROOT/zlib.h $SYSROOT/zconf.h $HOME/Claude/openssh-build/openssl-prefix/include/
ln -sf /system/lib64/platformsdk/libz.so $HOME/Claude/openssh-build/openssl-prefix/lib/libz.so
```

## 步骤 2：配置 OpenSSH

### 修复 config.guess

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
echo '#!/bin/sh
echo "aarch64-unknown-linux-gnu"' > config.guess
chmod +x config.guess
```

### 用 bash 运行 configure（不能用 toybox sh）

Toybox sh 会导致 conftest.c 创建失败。必须使用 bash：

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

### 修复 config.status mktemp 问题（关键）

**根本原因**：HarmonyOS 文件系统目录上的 setgid 标志导致 mktemp 创建的子目录被 uid 20001006（file_manager）拥有，但我们的进程以 uid 20020106（chenjh）运行。向这些目录写入会失败并报 "Permission denied"。

**修复**：创建一个预先存在的可写目录并修补 config.status：

```bash
mkdir -p $HOME/Claude/openssh-build/openssh-9.9p1/cs_tmp
chmod 777 cs_tmp
```

编辑 `config.status` — 替换 mktemp 块（大约第 573 行）：
```bash
# 从：
{
  tmp=`(umask 077 && mktemp -d "./confXXXXXX") 2>/dev/null` &&
  test -d "$tmp"
}  ||
{
  tmp=./conf$$-$RANDOM
  (umask 077 && mkdir "$tmp")
} || as_fn_error $? "cannot create a temporary directory in ." "$LINENO" 5

# 改为：
{
  tmp=cs_tmp
  test -d "$tmp" || mkdir "$tmp"
} || as_fn_error $? "cannot create a temporary directory in ." "$LINENO" 5
```

同时移除尝试删除临时目录的清理陷阱：
```bash
# 从：
{ test ! -d "$ac_tmp" || rm -fr "$ac_tmp"; } && exit $exit_status
# 改为：
exit $exit_status
```

然后运行 config.status：
```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
/data/service/hnp/bin/bash config.status
```

## 步骤 3：configure 后 config.h 修复

为了兼容 HarmonyOS，需要对 config.h 进行多处修改：

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1

# 1. DISABLE_SHADOW — musl 缺少 getspnam()
sed -i 's|^/\* #undef DISABLE_SHADOW \*/$|#define DISABLE_SHADOW 1|' config.h

# 2. DISABLE_WTMP — musl 缺少 logwtmp/updwtmp/logout()
sed -i 's|^/\* #undef DISABLE_WTMP \*/$|#define DISABLE_WTMP 1|' config.h

# 3. 禁用 SSH_TUN — linux/if.h 与 sys/socket.h 冲突
sed -i 's|^#define SSH_TUN_LINUX 1$|/* #undef SSH_TUN_LINUX */|' config.h
sed -i 's|^#define SSH_TUN_COMPAT_AF 1$|/* #undef SSH_TUN_COMPAT_AF */|' config.h
sed -i 's|^#define SSH_TUN_PREPEND_AF 1$|/* #undef SSH_TUN_PREPEND_AF */|' config.h

# 4. 使用 SANDBOX_RLIMIT 替代 SANDBOX_SECCOMP_FILTER
#    seccomp-filter 包含与 musl 冲突的 linux 头文件
sed -i 's|^#define SANDBOX_SECCOMP_FILTER 1$|/* #undef SANDBOX_SECCOMP_FILTER */|' config.h
sed -i 's|^/\* #undef SANDBOX_RLIMIT \*/$|#define SANDBOX_RLIMIT 1|' config.h
```

## 步骤 4：源码修复

### 4.1 loginrec.c 缺陷：`ut` → `utx`

`loginrec.c` 第 1018 行：
```c
// 从：
if (!utmpx_write_direct(li, &ut)) {
// 改为：
if (!utmpx_write_direct(li, &utx)) {
```

### 4.2 openbsd-compat/Makefile：移除 port-net.o

port-net.c 包含 `linux/if.h`，导致 sockaddr_storage 冲突。
从 openbsd-compat/Makefile 的 PORTS 列表中移除它。

### 4.3 sshd-session.c：privsep chroot 非致命（关键）

HarmonyOS 不允许用户空间进程调用 chroot()。当 chroot 失败时，跳过后续的权限降级（setgroups + permanently_set_uid）。

在 `sshd-session.c` 的 `privsep_preauth_child()` 函数中：
```c
/* 降低子进程权限 */
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

### 4.4 uidswap.c：setgroups/setegid/seteuid 非致命

HarmonyOS 不允许用户空间进程调用这些函数。从 `fatal()` 改为 `debug()`，使进程继续运行而非中止。

在 `uidswap.c` 中：
- 第 120-121 行：`setgroups` — 已经是 `debug("setgroups: ...")`，无需修改
- 第 130-132 行：`setegid` — 从 `fatal` 改为 `debug`
- 第 133-135 行：`seteuid` — 从 `fatal` 改为 `debug`

### 4.5 sandbox-rlimit.c：RLIMIT_NPROC 非致命

`setrlimit(RLIMIT_NPROC, {0,0})` 在 HarmonyOS 上失败。从 `fatal` 改为 `debug`。

同时添加到 `config.h`：
```c
#define SANDBOX_SKIP_RLIMIT_FSIZE 1
#define SANDBOX_SKIP_RLIMIT_NOFILE 1
```

### 4.6 platform-misc.c：接受 file_manager uid 作为系统所有者（关键）

由于父目录上的 setgid，HarmonyOS 上的文件由 uid 20001006（file_manager）拥有，但 sshd 以 uid 20020106（chenjh）运行。没有此修复，`safe_path()` 会拒绝 authorized_keys 并报 "bad ownership or modes"。

这是 dropbear 式方案：将 uid 20001006 视为"系统目录 uid"（类似 root），使所有权检查通过。

在 `platform-misc.c` 的 `platform_sys_dir_uid()` 函数中：
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
     * HarmonyOS：file_manager（uid 20001006）拥有所有用户文件，
     * 因为父目录有 setgid 属性，即使访问用户可能是
     * uid 20020106。将 file_manager 视为"系统目录 uid"，
     * 使 safe_path() 所有权检查通过。
     */
    if (uid == 20001006)
        return 1;
    return 0;
}
```

### 4.7 misc.c：safe_path() 对系统所有文件跳过模式检查（关键）

HarmonyOS 目录具有 setgid + 组可写模式（例如 `drwxrws--x`，模式 `2771`），无法通过 chmod 修改。`safe_path()` 中的 `022` 位掩码检查会拒绝这些目录。

修改 `misc.c` 中的 `safe_path()`，使模式检查（`st_mode & 022`）仅对非系统所有的文件生效。当 `platform_sys_dir_uid()` 返回 true（uid 0 或 20001006）时，跳过模式检查。

```c
// 文件检查（大约第 2253 行）：
if ((!platform_sys_dir_uid(stp->st_uid) && stp->st_uid != uid) ||
    (!platform_sys_dir_uid(stp->st_uid) && (stp->st_mode & 022) != 0)) {
    ...
}

// 目录检查（大约第 2268 行）：
if (stat(buf, &st) == -1 ||
    (!platform_sys_dir_uid(st.st_uid) && st.st_uid != uid) ||
    (!platform_sys_dir_uid(st.st_uid) && (st.st_mode & 022) != 0)) {
    ...
}
```

### 4.8 misc.c：unix_listener() EPERM 回退到抽象 socket（关键）

HarmonyOS 的 `bind()` 对文件系统 Unix socket 返回 EPERM。抽象命名空间 socket（sun_path[0]='\0'）正常工作。

在 `misc.c` 的 `unix_listener()` 函数中：当 `bind()` 返回 EPERM 时，关闭常规 socket，创建新 socket，并绑定到名为 `ssh-agent.<pid>` 的抽象命名空间 socket。

```c
if (bind(sock, (struct sockaddr *)&sunaddr, sizeof(sunaddr)) == -1) {
    saved_errno = errno;
    if (errno == EPERM) {
        debug_f("bind EPERM, 尝试抽象 socket");
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
        debug_f("抽象 socket 绑定成功");
        return sock;
    }
    error_f("cannot bind to path %s: %s", ...);
    ...
}
```

### 4.9 ssh-agent.c：检测抽象 socket 回退

`unix_listener()` 返回后，检查文件系统路径是否存在。如果不存在（stat ENOENT），说明 EPERM 回退已触发。将 `socket_name` 更新为使用 `abstract:` 前缀，让客户端知道 socket 格式。

```c
if (stat(socket_name, NULL) != 0 && errno == ENOENT) {
    snprintf(socket_name, sizeof(socket_name),
        "abstract:ssh-agent.%ld", (long)parent_pid);
    socket_dir[0] = '\0'; /* 不要在清理时 rmdir */
}
```

这使 ssh-agent 输出 `SSH_AUTH_SOCK=abstract:ssh-agent.<pid>; export SSH_AUTH_SOCK;` 而非文件系统路径。

### 4.10 authfd.c：处理 `abstract:` SSH_AUTH_SOCK 前缀

客户端（ssh、ssh-add）通过 `ssh_get_authentication_socket_path()` 连接到 agent。当 `SSH_AUTH_SOCK` 以 `abstract:` 开头时，通过抽象命名空间（sun_path[0]='\0'）而非文件系统路径连接。

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

### 4.11 passwd_compat.c：支持多种用户名变体（关键）

外部 SSH 客户端可能使用任何用户名变体（chenh、chenjh、currentUser、user）连接。passwd_compat LD_PRELOAD 库必须将所有这些变体映射到同一个 uid 20020106 条目，否则 sshd 会将它们视为"无效用户"而拒绝。

在 `passwd_compat.c` 的 `getpwnam()` 函数中：
```c
struct passwd *getpwnam(const char *name) {
    /* 接受所有常见的用户名变体 */
    if (strcmp(name, "chenh") == 0 || strcmp(name, "chenjh") == 0 ||
        strcmp(name, "currentUser") == 0 || strcmp(name, "user") == 0)
        return &chenh_pw;
    if (strcmp(name, "sshd") == 0) return &sshd_pw;
    struct passwd *(*real)(const char *) = dlsym(RTLD_NEXT, "getpwnam");
    if (real) return real(name);
    return NULL;
}
```

### 4.12 session.c：在子进程环境中保留 LD_PRELOAD 和 LD_LIBRARY_PATH（关键）

sshd 的 `do_setup_env()` 为子进程构建全新环境，丢弃了父进程的 LD_PRELOAD。这导致 scp/sftp/shell 子进程失去 passwd_compat.so，使得 `getpwuid(20020106)` 失败，因为 `/etc/passwd` 是只读的且不包含我们的 UID。结果是 scp 运行时 musl fortify 中止（"umask called with invalid mask 7022"）。

此外，系统 scp（`/usr/bin/scp`）即使使用 LD_PRELOAD 也会因 umask 错误崩溃，所以需要让 PATH 中优先找到我们构建的 scp。

需要两个修复：

**修复 A**：在 `session.c` 的 `do_setup_env()` 中，在 TZ 环境变量复制之后（大约第 1051 行）：
```c
if (getenv("TZ"))
    child_set_env(&env, &envsize, "TZ", getenv("TZ"));
/*
 * HarmonyOS：保留 LD_PRELOAD，使 passwd_compat.so
 * 在子进程（scp、sftp-server、shell）中保持活跃。
 * 没有此修改，getpwuid(20020106) 在 exec 的程序中
 * 会失败，因为 /etc/passwd 是只读的且不包含我们的 UID。
 */
if (getenv("LD_PRELOAD"))
    child_set_env(&env, &envsize, "LD_PRELOAD",
        getenv("LD_PRELOAD"));
if (getenv("LD_LIBRARY_PATH"))
    child_set_env(&env, &envsize, "LD_LIBRARY_PATH",
        getenv("LD_LIBRARY_PATH"));
```

**修复 B**：在 `sshd_config` 中，添加 `SetEnv` 将我们的 openssh-prefix/bin 放在 PATH 最前面，这样远程端的 scp/sftp 二进制文件使用我们构建的版本（而非会崩溃的系统版本）：
```
SetEnv PATH=$HOME/Claude/openssh-build/openssh-prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin
```

## 步骤 5：构建 OpenSSH

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1
TMPDIR=$HOME/Claude/tmpdir make
```

## 步骤 6：代码签名和安装

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

## 步骤 7：passwd_compat LD_PRELOAD

HarmonyOS 的 /etc/passwd 没有用户空间 UID（20020106、20001006）的条目。
OpenSSH 调用 getpwuid() 会失败并报 "No user exists for uid XXXXX"。

创建 LD_PRELOAD 库：

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
    .pw_dir = getenv("HOME") ? getenv("HOME") : "/",
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

## 步骤 8：sshd_config 示例

HarmonyOS 推荐的 sshd_config：

```
Port 2223
HostKey $HOME/Claude/tmpdir/sshd_host_key
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
StrictModes yes
AuthorizedKeysFile $HOME/.ssh/authorized_keys
PidFile $HOME/Claude/tmpdir/sshd_openssh.pid
Subsystem sftp $HOME/Claude/openssh-build/openssh-prefix/libexec/sftp-server
```

> **注意**: sshd_config 不展开 `$HOME`。使用此配置前，请将 `$HOME` 替换为实际的主目录路径。

注意：`StrictModes yes` 可以工作，因为 `platform_sys_dir_uid()` / `safe_path()` 补丁接受 uid 20001006（file_manager）作为有效所有者。HostKey 和 PidFile 放在 `$HOME/Claude/tmpdir/` 中，因为 HarmonyOS 上 `/tmp` 是只读的。

## 步骤 9：运行 OpenSSH

所有 OpenSSH 命令必须使用 LD_PRELOAD 运行：

```bash
BIN=$HOME/Claude/openssh-build/openssh-prefix/bin
PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so

# ssh-keygen
LD_PRELOAD=$PRELOAD $BIN/ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# ssh 客户端
LD_PRELOAD=$PRELOAD $BIN/ssh -p 2223 user@host

# sshd 服务端（StrictModes=yes 在 UID 修复后可用）
LD_PRELOAD=$PRELOAD $BIN/sshd -f /path/to/sshd_config -E /path/to/sshd.log

# ssh-agent（在 HarmonyOS 上使用抽象命名空间 socket）
eval $(LD_PRELOAD=$PRELOAD $BIN/ssh-agent)
# 输出：SSH_AUTH_SOCK=abstract:ssh-agent.<pid>; export SSH_AUTH_SOCK;
#       SSH_AGENT_PID=<pid>; export SSH_AGENT_PID;

# ssh-add（通过抽象 socket 连接到 agent）
export SSH_AUTH_SOCK=abstract:ssh-agent.<pid>  # 来自 ssh-agent 输出
export SSH_AGENT_PID=<pid>                      # 来自 ssh-agent 输出
LD_PRELOAD=$PRELOAD $BIN/ssh-add ~/.ssh/id_ed25519
LD_PRELOAD=$PRELOAD $BIN/ssh-add -l             # 列出身份

# 终止 agent
LD_PRELOAD=$PRELOAD $BIN/ssh-agent -k
```

注意：在 HarmonyOS 上，ssh-agent 的 `SSH_AUTH_SOCK` 使用 `abstract:` 前缀而非文件系统路径。`ssh` 和 `ssh-add` 客户端自动检测此前缀并通过抽象命名空间 socket 连接。

## 已知限制

### 1. sshd 权限分离（已修复）
OpenSSH 的 privsep（sshd-session 子进程）调用 setgroups()，在 HarmonyOS 上失败（"Operation not permitted"）。此前导致 SSH 连接在 preauth 期间失败并报 "Invalid argument"。

**状态**：已修复。sshd-session.c 补丁使 chroot 非致命（chroot 失败时跳过后续权限降级）。uidswap.c 将 setgroups/setegid/seteuid 改为非致命（debug 而非 fatal）。sandbox-rlimit.c RLIMIT_NPROC setrlimit 改为非致命。

### 2. ssh-agent Unix socket（已修复）
ssh-agent 的 `bind()` 对文件系统 Unix socket 在 HarmonyOS 上返回 EPERM。抽象命名空间 socket（sun_path[0]='\0'）正常工作。

**状态**：已修复。`unix_listener()` 在 misc.c 中当 bind EPERM 时回退到抽象命名空间 socket。ssh-agent.c 检测回退并设置 `SSH_AUTH_SOCK=abstract:<name>`，让客户端知道使用抽象 socket 格式。`ssh_get_authentication_socket_path()` 在 authfd.c 中处理 `abstract:` 前缀，通过抽象命名空间连接。

### 3. authorized_keys 所有权（已修复）
文件由 uid 20001006（file_manager）拥有，但 sshd 以 uid 20020106（chenjh）运行，导致 "bad ownership or modes" 错误。

**状态**：已修复，使用 dropbear 式方案。`platform_sys_dir_uid()` 在 platform-misc.c 中将 uid 20001006 视为可接受的系统目录所有者（类似 root）。`safe_path()` 在 misc.c 中对系统目录所有的文件跳过模式检查（022 位掩码），因为 HarmonyOS 的 setgid 目录无法移除组可写模式。`StrictModes=yes` 现在可正常工作。

### 4. 无 shadow 密码支持
HarmonyOS 上的 musl libc 虽在 shadow.h 中定义了 struct spwd，但未实现 getspnam()。通过 /etc/shadow 的密码认证不可用。

### 5. 无 wtmp/lastlog 日志
musl libc 中没有 logwtmp()、updwtmp()、logout() 等函数。会话日志写入 wtmp/lastlog 文件已禁用。

### 6. SSH 隧道（tun/tap）已禁用
linux/if.h 头文件与 sys/socket.h 冲突（sockaddr_storage 重定义）。SSH 隧道转发已禁用。

## 对比：HarmonyOS 上 OpenSSH vs Dropbear

| 功能 | Dropbear | OpenSSH |
|------|----------|---------|
| SSH 服务端 | 可用（需 -e 标志） | 可用（privsep 已修补） |
| SSH 客户端 | 可用（dbclient） | 可用（需 LD_PRELOAD） |
| 密钥生成 | 可用 | 可用（需 LD_PRELOAD） |
| scp | 可用 | 可用（LD_PRELOAD + SetEnv PATH） |
| sftp | 不支持 | 可用（LD_PRELOAD + SetEnv PATH） |
| ssh-agent | 不支持 | 可用（抽象命名空间 socket） |
| 公钥认证 | 可用 | 可用（StrictModes=yes 可用） |
| 密码认证 | 不可用 | 不可用 |
| 隧道/tap | 不支持 | 已禁用（头文件冲突） |
| 配置 | 有限 | 完整 sshd_config 支持 |
| 协议 | 仅 SSH-2 | SSH-2，所有现代算法 |

## 文件路径

- 源码：`$HOME/Claude/openssh-build/openssh-9.9p1/`
- OpenSSL prefix：`$HOME/Claude/openssh-build/openssl-prefix/`
- OpenSSH prefix：`$HOME/Claude/openssh-build/openssh-prefix/`
- passwd_compat：`$HOME/Claude/openssh-build/passwd_compat/`