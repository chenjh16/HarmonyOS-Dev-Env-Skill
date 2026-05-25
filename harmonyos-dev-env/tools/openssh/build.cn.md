# HarmonyOS 上 OpenSSH 9.9p1 构建指南

HarmonyOS（鸿蒙内核 1.12.0，aarch64，musl libc）上 OpenSSH 9.9p1 的逐步构建说明和源码补丁。

## 前置条件

- OpenSSL 3.0.16（静态库，从源码构建）
- clang 15.0.4（HarmonyOS SDK）
- ld.bfd 包装器，位于 `$HOME/Claude/lib/linker_wrapper/ld.lld`
- bash（SDK，configure 需要它 — toybox sh 会失败）
- zlib 头文件（SDK sysroot）

## 补丁汇总

| # | 文件 | 函数 / 区域 | 修复内容 |
|---|------|-------------|----------|
| 1 | loginrec.c | `utmpx_write_direct()` | `&ut` → `&utx`（上游缺陷） |
| 2 | openbsd-compat/Makefile | PORTS 列表 | 移除 port-net.o（linux/if.h sockaddr_storage 冲突） |
| 3 | sshd-session.c | `privsep_preauth_child()` | chroot 非致命；chroot 失败时跳过 setgroups + permanently_set_uid |
| 4 | uidswap.c | `setegid()` / `seteuid()` | `fatal` → `debug`（用户空间无法调用这些函数） |
| 5 | sandbox-rlimit.c | `setrlimit(RLIMIT_NPROC)` | `fatal` → `debug` + 添加 SANDBOX_SKIP_RLIMIT_FSIZE/NOFILE |
| 6 | platform-misc.c | `platform_sys_dir_uid()` | 接受 uid 20001006（file_manager）作为系统所有者 |
| 7 | misc.c | `safe_path()` | 对系统所有文件跳过模式检查（022 位掩码） |
| 8 | misc.c | `unix_listener()` | EPERM 回退：绑定到抽象命名空间 socket |
| 9 | ssh-agent.c | `unix_listener()` 返回后 | 通过 stat ENOENT 检测抽象回退；设置 `abstract:` 前缀 |
| 10 | authfd.c | `ssh_get_authentication_socket_path()` | 处理 `abstract:` 前缀：通过抽象命名空间连接 |
| 11 | passwd_compat.c | `getpwnam()` | 接受 chenh/chenjh/currentUser/user → 同一 uid 20020106 |
| 12 | session.c | `do_setup_env()` | 在子进程环境中保留 LD_PRELOAD + LD_LIBRARY_PATH |

## 步骤 1：构建 OpenSSL 3.0.16

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

make -j1  # HarmonyOS 上 make -j 会失败（mkfifo EPERM）
make install
```

从 SDK sysroot 复制 zlib 头文件：
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

### 运行 configure（必须用 bash，不能用 toybox sh）

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

HarmonyOS 目录上的 setgid 使 mktemp 子目录被 uid 20001006（file_manager）拥有，而非我们的 uid 20020106。写入失败报 "Permission denied"。

```bash
mkdir -p $HOME/Claude/openssh-build/openssh-9.9p1/cs_tmp
chmod 777 cs_tmp
```

编辑 `config.status` — 替换 mktemp 块（约第 573 行）：
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

移除清理陷阱：
```bash
# 从：
{ test ! -d "$ac_tmp" || rm -fr "$ac_tmp"; } && exit $exit_status
# 改为：
exit $exit_status
```

运行修补后的 config.status：
```bash
/data/service/hnp/bin/bash config.status
```

## 步骤 3：configure 后 config.h 修复

```bash
cd $HOME/Claude/openssh-build/openssh-9.9p1

# DISABLE_SHADOW — musl 缺少 getspnam()
sed -i 's|^/\* #undef DISABLE_SHADOW \*/$|#define DISABLE_SHADOW 1|' config.h

# DISABLE_WTMP — musl 缺少 logwtmp/updwtmp/logout()
sed -i 's|^/\* #undef DISABLE_WTMP \*/$|#define DISABLE_WTMP 1|' config.h

# 禁用 SSH_TUN — linux/if.h 与 sys/socket.h 冲突
sed -i 's|^#define SSH_TUN_LINUX 1$|/* #undef SSH_TUN_LINUX */|' config.h
sed -i 's|^#define SSH_TUN_COMPAT_AF 1$|/* #undef SSH_TUN_COMPAT_AF */|' config.h
sed -i 's|^#define SSH_TUN_PREPEND_AF 1$|/* #undef SSH_TUN_PREPEND_AF */|' config.h

# SANDBOX_RLIMIT 替代 SECCOMP_FILTER — linux 头文件与 musl 冲突
sed -i 's|^#define SANDBOX_SECCOMP_FILTER 1$|/* #undef SANDBOX_SECCOMP_FILTER */|' config.h
sed -i 's|^/\* #undef SANDBOX_RLIMIT \*/$|#define SANDBOX_RLIMIT 1|' config.h

# 沙箱跳过标志
echo '#define SANDBOX_SKIP_RLIMIT_FSIZE 1' >> config.h
echo '#define SANDBOX_SKIP_RLIMIT_NOFILE 1' >> config.h
```

## 步骤 4：应用源码补丁

按照补丁汇总表应用补丁 1-12。关键细节：

**补丁 3** — sshd-session.c `privsep_preauth_child()`：chroot 失败时，设置 `privsep_chroot = 0` 并完全跳过 `setgroups` + `permanently_set_uid` 块。

**补丁 6** — platform-misc.c `platform_sys_dir_uid()`：添加 `if (uid == 20001006) return 1;` 使 file_manager uid 被视为系统所有者。

**补丁 7** — misc.c `safe_path()`：用 `!platform_sys_dir_uid()` 包裹模式检查：
```c
(!platform_sys_dir_uid(stp->st_uid) && (stp->st_mode & 022) != 0)
```

**补丁 8** — misc.c `unix_listener()`：bind EPERM 时，关闭 socket，创建新 PF_UNIX socket，设置 `sun_path[0] = '\0'`，将名称 `ssh-agent.<pid>` snprintf 到 `sun_path+1`，bind + listen，返回。

**补丁 9** — ssh-agent.c：`unix_listener()` 返回后，若 `stat(socket_name)` 返回 ENOENT，设置 `socket_name` 为 `abstract:ssh-agent.<pid>`。

**补丁 10** — authfd.c：若 `authsocket` 以 `abstract:` 开头，跳过 9 个字符，设置 `sun_path[0] = '\0'`，将剩余部分复制到 `sun_path+1`。

**补丁 11** — passwd_compat.c `getpwnam()`：将所有用户名变体映射到同一条目。

**补丁 12** — session.c `do_setup_env()`：TZ 复制之后，添加 LD_PRELOAD 和 LD_LIBRARY_PATH 保留。同时在 sshd_config 中添加 `SetEnv PATH=...`。

## 步骤 5：构建

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

## 步骤 7：构建 passwd_compat LD_PRELOAD 库

```c
// passwd_compat.c — 保存到 $HOME/Claude/openssh-build/passwd_compat/passwd_compat.c
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

## sshd_config 示例

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
SetEnv PATH=$HOME/Claude/openssh-build/openssh-prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin
```

> **注意**: sshd_config 不展开 `$HOME`。使用此配置前，请将 `$HOME` 替换为实际的主目录路径。

关键说明：
- `StrictModes yes` 可用，因为补丁 6+7 使 file_manager uid 被视为系统所有者，并跳过模式检查
- HostKey/PidFile 放在 `$HOME/Claude/tmpdir/` 中，因为 HarmonyOS 上 `/tmp` 是只读的
- `SetEnv PATH` 确保 scp/sftp 使用我们构建的二进制文件，而非会崩溃的系统版本