# Dropbear SSH 服务器 on HarmonyOS (aarch64) - 完整构建指南

> **English version: [build.md](build.md)**

## 概述

Dropbear 是一个轻量级的 SSH 服务器/客户端，相比 OpenSSH 更容易在 HarmonyOS 上编译。本文档记录完整的构建过程。

**主要挑战**：
1. HarmonyOS 缺少 `crypt()` 函数 - 必须禁用密码认证
2. `configure` 脚本因交叉编译检测问题失败
3. `fake-rfc2553.h` 导致结构体重定义冲突
4. `HAVE_GETRANDOM` 应该取消定义 - HarmonyOS 使用 `/dev/urandom` 替代
5. **非标准用户系统** - 用户不在 `/etc/passwd` 中，必须修改源码
6. **文件所有权不匹配** - 进程 UID 与文件所属 UID 不同

## 构建摘要

**结果**：成功编译 Dropbear 2024.86，包含：
- 服务器：`dropbear` (285KB)
- 客户端：`dbclient` (273KB)
- 密钥生成：`dropbearkey` (187KB)
- 密钥转换：`dropbearconvert` (195KB)

**认证方式**：仅公钥认证（因缺少 `crypt()` 无法使用密码认证）

## 前置要求

- HarmonyOS SDK，包含 clang 15.0.4
- ld.bfd 包装器（SDK 的 lld 需要不存在的 libxml2.so.16）
- SDK 的 sysroot

## 构建步骤

### 1. 下载源码

```bash
cd $HOME/Claude/dropbear-build
curl -L --connect-timeout 30 -o dropbear-2024.86.tar.bz2 \
  "https://matt.ucc.asn.au/dropbear/releases/dropbear-2024.86.tar.bz2"
tar xjf dropbear-2024.86.tar.bz2
cd dropbear-2024.86
```

### 2. 创建 ld.bfd 包装器

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

### 3. 构建 libtommath

```bash
cd libtommath
make -f Makefile.in \
  CC=/data/service/hnp/bin/clang \
  AR=/data/service/hnp/bin/ar \
  RANLIB=/data/service/hnp/bin/ranlib \
  CFLAGS="-O2 -I. -I../src -I../libtomcrypt/src/headers -I.. -Wno-deprecated" \
  IGNORE_SPEED=1
cd ..
```

### 4. 构建 libtomcrypt

```bash
cd libtomcrypt
make -f makefile.unix \
  CC=/data/service/hnp/bin/clang \
  AR=/data/service/hnp/bin/ar \
  RANLIB=/data/service/hnp/bin/ranlib \
  CFLAGS="-O2 -Isrc/headers -I../libtommath -I.. -I../src -DLTC_SOURCE -DUSE_LTM -DLTM_DESC -DDROPBEAR_BUNDLED_LIBTOM --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot" \
  EXTRALIBS="../libtommath/libtommath.a"
cd ..
```

### 5. 创建 config.h

```c
/* config.h for HarmonyOS */
#ifndef DROPBEAR_CONFIG_H
#define DROPBEAR_CONFIG_H

#undef HAVE_GETRANDOM  /* HarmonyOS 使用 /dev/urandom */

/* 使用内置 libtomcrypt/libtommath */
#define BUNDLED_LIBTOM 1

#define HAVE_CLOCK_GETTIME 1
#define HAVE_DAEMON 1
#define HAVE_GETADDRINFO 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_WRITEV 1

/* PTY 支持 - HarmonyOS 使用 Unix98 PTY (/dev/ptmx + /dev/pts/) */
#define HAVE_OPENPTY 1
#define HAVE_PTY_H 1

/* HarmonyOS 上存在这些网络结构体 */
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_IN6_ADDR 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_IPV6 1

#endif
```

### 6. 创建 options.h

**重要**：include 顺序很重要！必须先包含 `default_options.h`，然后用 `#undef` 和 `#define` 覆盖宏。

此外，`config.h` 必须在最开头包含，这样 `HAVE_STRUCT_*` 定义才能用于 `fake-rfc2553.h` 的检查（防止结构与系统头文件重复定义冲突）。

```bash
cat > src/options.h << 'EOF'
#ifndef DROPBEAR_OPTIONS_H
#define DROPBEAR_OPTIONS_H

/* 先包含 config.h 以获取 HAVE_* 定义 */
#include "config.h"

/* 先包含默认选项 */
#include "default_options.h"

/* HarmonyOS 覆盖 - 禁用密码认证（无 crypt()）*/
#undef DROPBEAR_SVR_PASSWORD_AUTH
#define DROPBEAR_SVR_PASSWORD_AUTH 0

#undef DROPBEAR_CLI_PASSWORD_AUTH  
#define DROPBEAR_CLI_PASSWORD_AUTH 0

/* 密钥路径 */
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

### 7. 创建 Makefile

使用项目中的 Makefile 或手动创建。完整 Makefile 参考 `tools/dropbear/build.md` 附录。

### 8. 签名二进制文件

所有 ELF 二进制文件必须签名：

```bash
for binary in dropbear dbclient dropbearkey dropbearconvert; do
  llvm-objcopy --remove-section=.codesign $binary ${binary}.unsigned
  binary-sign-tool sign -selfSign 1 -inFile ${binary}.unsigned -outFile ${binary}.signed -signAlg SHA256withECDSA
  mv ${binary}.signed $binary
  chmod +x $binary
done
```

### 9. 生成主机密钥

```bash
mkdir -p $HOME/.local/etc/dropbear
dropbearkey -t rsa -f ~/.local/etc/dropbear/dropbear_rsa_host_key -s 2048
dropbearkey -t ecdsa -f ~/.local/etc/dropbear/dropbear_ecdsa_host_key -s 256
dropbearkey -t ed25519 -f ~/.local/etc/dropbear/dropbear_ed25519_host_key
```

### 10. HarmonyOS 用户系统源码补丁

HarmonyOS 使用非传统的用户管理系统：
- 用户不在 `/etc/passwd` 中注册
- 进程 UID（如 20020106）与文件所属 UID（如 20001006）不同
- 主目录有 group writable 权限且无法修改

需要修改五个源文件：

#### 补丁 1：`src/common-session.c` - 用户查找 Fallback

为 `getpwnam()` 失败添加 fallback，接受任何非系统用户名作为设备用户：

```c
// 在 fill_passwd() 函数中，"pw = getpwnam(username);" 之后添加
pw = getpwnam(username);
if (!pw) {
    /* HarmonyOS fallback: /etc/passwd 只有最少的条目（root, bin,
     * 系统服务）。实际设备用户使用数字 UID，不在 passwd 中。
     * 由于是单用户设备，接受任何不在系统 UID 范围（0-9999）
     * 内的用户名作为当前设备用户。 */
    char uid_str[32];
    snprintf(uid_str, sizeof(uid_str), "%u", getuid());
    /* 拒绝系统用户名（root, bin, system 等）——
     * 这些 UID < 10000，不应获得设备用户访问权限 */
    long uid_check = strtol(username, NULL, 10);
    if (strcmp(username, "root") == 0 || strcmp(username, "bin") == 0
        || strcmp(username, "system") == 0
        || (username[0] != '\0' && uid_check > 0 && uid_check < 10000)) {
        /* 这是已知系统用户但不存在——拒绝 */
        return;
    }
    /* 接受任何其他用户名作为设备用户 */
    ses.authstate.pw_uid = getuid();
    ses.authstate.pw_gid = getgid();
    ses.authstate.pw_name = m_strdup(uid_str);
    ses.authstate.pw_dir = m_strdup(getenv("HOME") ? getenv("HOME") : "/");
    ses.authstate.pw_shell = m_strdup(getenv("SHELL") ? getenv("SHELL") : "/usr/bin/zsh");
    ses.authstate.pw_passwd = m_strdup("!!");
    return;
}
```

**解释**：HarmonyOS `/etc/passwd` 只有极少的条目（root, bin, 系统服务）。实际设备用户使用数字 UID（如 20020106），没有任何人类可读的用户名。由于 HarmonyOS 是单用户设备，补丁接受任何不匹配系统账户的用户名作为当前设备用户。这意味着 SSH 客户端可以使用任意用户名（如 `chenh`、`user`、`currentUser`、`20020106`）连接——所有都会被视为同一个设备用户。

**安全说明**：系统用户名（root, bin, system）和数字 UID < 10000 被明确拒绝，以防止对不应存在的系统账户的未授权访问。

**重要**：Shell 必须设置为 `$SHELL`（HarmonyOS 上通常是 `/usr/bin/zsh`），而不是 `/bin/sh`。使用 `/bin/sh` 会导致 SSH 会话跳过 `.zshenv` 的 PATH 配置，导致 npm/claude 命令无法使用。

#### 补丁 2：`src/svr-auth.c` - 跳过 Shell 验证

HarmonyOS 没有 `/etc/shells` 文件，导致 dropbear 的 shell 验证总是失败。跳过验证：

```c
// 在 checkusername() 函数中，约第 316 行
// 将 shell 验证循环替换为：
/* HarmonyOS: 跳过 shell 验证，因为 /etc/shells 不存在 */
TRACE(("skipping shell validation for HarmonyOS"))
goto goodshell;
```

**解释**：Dropbear 通过检查 `/etc/shells` 来验证用户 shell。HarmonyOS 没有这个文件，导致所有 shell 验证失败。补丁跳过此检查。

#### 补丁 3：`src/svr-authpubkey.c` - 跳过权限检查

替换 `checkfileperm()` 函数以跳过严格的权限验证：

```c
static int checkfileperm(char * filename) {
    TRACE(("enter checkfileperm(%s)", filename))
    /* HarmonyOS: 跳过权限检查，因为文件所有权非标准 */
    /* - 文件 UID (20001006) != 进程 UID (20020106) */
    /* - 主目录有 group writable 权限（无法修改） */
    TRACE(("leave checkfileperm: success (HarmonyOS skip)"))
    return DROPBEAR_SUCCESS;
}
```

**解释**：Dropbear 通常要求：
1. 主目录、`.ssh` 和 `authorized_keys` 由用户或 root 拥有
2. 没有 group 或 others 写权限

在 HarmonyOS 上：
- 文件所有权使用 UID 20001006（file_manager）
- 进程以 UID 20020106 运行
- 目录有 `drwxrws--x`（group writable），且 `chmod g-w` 失败

补丁绕过这些检查，因为 HarmonyOS 的安全模型与传统 Linux 不同。

#### 补丁 4：`src/svr-chansession.c` - PTY 分配 Fallback

分配 PTY 时，dropbear 再次调用 `getpwnam()`。添加 fallback：

```c
// 在 sessionpty() 函数中，约第 611 行
pw = getpwnam(ses.authstate.pw_name);
if (!pw) {
    /* HarmonyOS fallback: 从 authstate 创建 passwd entry */
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

**解释**：PTY 分配时，`svr-chansession.c` 调用 `getpwnam()` 获取用户信息以设置 PTY 所有者。这在 HarmonyOS 上失败，导致 segfault。补丁复用补丁 1 已填充的 authstate 数据。

#### 补丁 5：`src/loginrec.c` - 登录记录 Fallback

记录登录会话时，`login_init_entry()` 调用 `getpwnam()`。添加接受任何非系统用户名的 fallback：

```c
// 在 login_init_entry() 函数中，约第 278 行
pw = getpwnam(li->username);
if (pw == NULL) {
    /* HarmonyOS fallback: 如果 getpwnam 失败，接受任何非系统用户名。
     * HarmonyOS 的实际设备用户不在 /etc/passwd 中，所以 getpwnam()
     * 总是失败。我们接受任何非系统用户名作为当前设备用户
     * （与 common-session.c 使用相同逻辑）。 */
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

**注意**：需要在 loginrec.c 中添加 `#include "session.h"` 或声明 `extern struct sshsession ses;`。

**解释**：登录记录（utmp/wtmp）需要用户 UID 查找。在 HarmonyOS 上，`getpwnam()` 对所有设备用户名都会失败。旧补丁只匹配 `pw_name`（UID 字符串 "20020106"），不匹配 SSH 用户名如 "chenh" 或 "user"，导致 `dropbear_exit()` 和段错误。更新后的补丁使用与 common-session.c 相同的逻辑——接受任何非系统用户名作为设备用户。

#### 补丁后重新编译

```bash
cd $HOME/Claude/dropbear-build/dropbear-2024.86
rm -f obj/common-session.o obj/svr-auth.o obj/svr-authpubkey.o obj/svr-chansession.o obj/loginrec.o obj/sshpty.o
make dropbear
# 按第 8 步签名并安装
```

## 运行服务器

### 手动启动

```bash
# 在端口 2222 启动服务器（前台运行，带日志）
dropbear -p 2222 -F -E

# 后台启动服务器（默认端口 2222）
dropbear -p 2222

# 作为客户端连接（使用数字 UID 作为用户名）
dbclient 20020106@localhost -p 2222
```

**注意**：端口 22 是特权端口，需要 root 权限。普通用户请使用端口 2222（或其他 > 1024 的端口）。

### 从远程机器连接

由于 HarmonyOS 的单用户设备模型，任何非系统用户名都可以用于 SSH 登录。所有用户名映射到同一个设备用户：

```bash
# 从远程机器连接 - 任何用户名都可以
ssh -p 2222 chenh@<HarmonyOS-IP>
ssh -p 2222 user@<HarmonyOS-IP>
ssh -p 2222 currentUser@<HarmonyOS-IP>

# 数字 UID 也可以
ssh -p 2222 20020106@<HarmonyOS-IP>
```

**为什么任何用户名都可以**：HarmonyOS `/etc/passwd` 只有极少的条目。源代码补丁（补丁 1）接受任何非系统用户名作为设备用户，因为设备上只有一个真实用户。系统用户名（root, bin, system）会被拒绝。

**设置步骤**：

1. 在远程机器上生成 SSH 密钥（如果不存在）：
   ```bash
   ssh-keygen -t ed25519
   ```

2. 将公钥复制到 HarmonyOS：
   ```bash
   # 在 HarmonyOS 上，将远程机器的公钥添加到 authorized_keys
   echo "ssh-ed25519 AAAA...你的公钥" >> ~/.ssh/authorized_keys
   ```

3. 测试连接：
   ```bash
   ssh -p 2222 20020106@<HarmonyOS-IP>
   ```

### 登录时自动启动

HarmonyOS 没有 systemd/cron，但可以在 shell 登录时自动启动 SSH：

1. **启动/停止脚本** 安装在 `$HOME/.local/bin/`：
   - `start-ssh.sh [port]` - 启动 SSH 服务器（默认端口：2222）
   - `stop-ssh.sh` - 停止 SSH 服务器

2. **自动启动配置在 `.zshrc`**：
   ```bash
   # SSH 自动启动（已添加到 ~/.zshrc，默认端口 2222）
   if [ -z "$NO_AUTOSTART_SSH" ]; then
       "$HOME/.local/bin/start-ssh.sh"
   fi
   ```

3. **禁用自动启动**，添加到 `~/.zshenv`：
   ```bash
   export NO_AUTOSTART_SSH=1
   ```

### 自动启动说明

- HarmonyOS PC 没有传统的 init 系统（无 systemd/cron）
- 自动启动仅在**登录到 shell 会话时**生效
- SSH 服务器通过 `nohup` 在后台运行
- PID 文件：`$HOME/.local/var/run/dropbear.pid`
- 日志文件：`$HOME/.local/var/log/dropbear.log`

## 已知限制

1. **无密码认证** - HarmonyOS 缺少 `crypt()` 函数
2. **仅公钥认证** - 用户必须手动设置 SSH 密钥
3. **有限的 locale 支持** - 可能影响某些功能
4. **接受任何非系统用户名** - 所有用户名（除了 root/bin/system）映射到同一个设备用户
5. **需要源码补丁** - 必须修改五个源文件以支持 HarmonyOS
6. **PTY 控制终端限制** - `ioctl(TIOCSCTTY)` 在 HarmonyOS 上失败（返回 I/O 错误）。交互式 SSH 会话（带 PTY 的 shell）可能没有完整的作业控制。命令执行模式（`ssh user@host command`）正常工作。
7. **必须使用 `-e` 参数** - `-e` 参数（传递父进程环境到子进程）在 HarmonyOS 上非常关键，因为 SSH 子进程需要 LD_LIBRARY_PATH、PATH 等变量。没有 `-e` 时，`clearenv()` 会在设置最小环境前清除所有环境变量（PATH=/usr/bin:/bin）。

## 故障排除

### fake-rfc2553.h 重定义错误

在 config.h 中定义 `HAVE_STRUCT_*` 宏，防止 dropbear 定义 HarmonyOS 头文件中已存在的结构体。

### getrandom 未找到

HarmonyOS 有 `/dev/urandom` 但没有 `getrandom()` 系用调用。在 config.h 中使用 `#undef HAVE_GETRANDOM`。

### svr_ses 未声明

在 CFLAGS 中添加 `-DDROPBEAR_SERVER=1` 以启用服务器特定代码路径。

### "Login attempt for nonexistent user"

日志显示：`Login attempt for nonexistent user from ...`

**原因**：用户在 `/etc/passwd` 中找不到，因为 HarmonyOS 不使用传统用户数据库。

**解决方案**：应用 `common-session.c` 补丁（补丁 1，第 10 步），该补丁接受任何非系统用户名作为设备用户。补丁后，`chenh`、`user`、`currentUser` 或数字 UID 等用户名均可使用。

### "must be owned by user or root, and not writable by group or others"

日志显示：`$HOME must be owned by user or root...`

**原因**：HarmonyOS 文件所有权模型与 Linux 不同：
- 进程 UID (20020106) != 文件所属 UID (20001006)
- 主目录有 group writable 权限 (`drwxrws--x`)

**解决方案**：应用 `svr-authpubkey.c` 补丁（第 10 步）以跳过权限验证。

### Permission denied (publickey) 添加密钥后

**检查**：
1. `~/.ssh/authorized_keys` 中的公钥格式正确
2. 使用非系统用户名（任何名称都可以，除了 root/bin/system）
3. 所有五个源码补丁已应用且 dropbear 已重新编译
4. 密钥与 `~/.ssh/authorized_keys` 中的某一条匹配

### PTY allocation request failed / shell request failed

**原因**：PTY 分配时 `getpwnam()` 失败导致 segfault。

**解决方案**：应用 `svr-chansession.c` 和 `loginrec.c` 补丁（第 10 步）。

### SSH 会话中 V8/Node.js 崩溃 (errno=ENOMEM)

在 SSH 会话中运行 Claude Code 或其他 Node.js 应用时，可能会遇到：

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
zsh: trace trap (core dumped)  NODE_OPTIONS="--max-old-space-size=12288" claude
```

**原因**：HarmonyOS PTY 系统限制 V8 JIT 编译器：
- V8 JIT 需要内存映射的可执行页面，在 SSH PTY 环境下会失败
- `errno=ENOMEM (12)` 表示 JIT 代码页面的内存分配失败
- 这是 HarmonyOS PTY/kernel 的限制，不是 Node.js 的 bug

**解决方案**：使用 `node --jitless` + `node-fetch` polyfill：

```bash
# 在 SSH 会话中，使用 --jitless 和 node-fetch polyfill 运行 Claude Code
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /path/to/claude-code/cli.js --dangerously-skip-permissions
```

**为什么需要 node-fetch polyfill**：
- `--jitless` 禁用 WebAssembly 以避免 JIT 崩溃
- Node.js 原生 `fetch` 需要 WebAssembly 用于压缩（brotli/gzip）
- `node-fetch` 使用 `http.request`（不需要 WebAssembly），在 `--jitless` 下可工作

**start-claude.sh 自动检测 SSH 环境**：

启动脚本自动检测 SSH 环境并使用 `--jitless` + polyfill：

```bash
SSH_ENV_INDICATORS="${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}"
SSH_FETCH_POLYFILL="$HOME/.claude/ssh-fetch-polyfill.js"

if [ -n "$SSH_ENV_INDICATORS" ]; then
    exec node --jitless --require "$SSH_FETCH_POLYFILL" "$CLAUDE_ENTRY" "$@"
else
    exec claude "$@"
fi
```

**安装要求**：
1. 安装 node-fetch：在 ~/Claude 目录执行 `npm install node-fetch@2`
2. 创建 polyfill 脚本：`~/.claude/ssh-fetch-polyfill.js`（见下方）
3. 更新 `~/.claude/start-claude.sh` 的 SSH 检测逻辑

**node-fetch polyfill 脚本** (`~/.claude/ssh-fetch-polyfill.js`):

```javascript
// SSH 环境 fetch polyfill
// HarmonyOS SSH 会话使用 --jitless 避免 V8 JIT 崩溃
// 但 --jitless 禁用 WebAssembly，导致原生 fetch 失效
// 本脚本用 node-fetch（基于 http.request）替代原生 fetch
//
// 重要：在 --jitless 模式下，原生 fetch 存在但已损坏（WebAssembly 为 undefined）
// 因此必须检查 WebAssembly，不能只检查 fetch 是否存在
//
// 兼容性修复：
// 1. node-fetch@2 Response.body 是 Node.js Readable stream，没有 cancel() 方法
// 2. node-fetch@2 Response.body 不是 Web ReadableStream（没有 pipeThrough/getReader）
// 3. MCP SDK 使用 Web Streams API: body.pipeThrough(new TextDecoderStream)...
// 4. Readable.toWeb() 会消费原始 stream，导致 text()/json() 失败
// 5. SSH 远程执行不传递 shell 环境变量到 Node.js - 必须直接加载 .env
// 6. 解决方案：使用 CustomResponse 类延迟处理 stream 转换

if (typeof WebAssembly === 'undefined') {
    console.log('[SSH] WebAssembly 禁用 (--jitless 模式)，使用 node-fetch 替代 fetch...');

    // 从 .env 文件加载环境变量（SSH 远程执行不传递 shell 环境变量）
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
        console.log('[SSH] 环境变量已从 .env 加载');
    }

    try {
        const nodeFetch = require(process.env.HOME + '/Claude/node_modules/node-fetch');
        const { Readable } = require('stream');

        // 存储原始 Response 类
        const OriginalResponse = nodeFetch.Response;

        // 创建自定义 Response 类，正确处理 stream 转换
        class CustomResponse extends OriginalResponse {
            constructor(body, init) {
                super(body, init);
                this._nodeStream = body; // 存储原始 Node stream
                this._webStream = null;  // 延迟初始化的 web stream
            }

            // 覆盖 body getter，需要时返回 Web ReadableStream
            get body() {
                // 已转换则返回缓存的 web stream
                if (this._webStream) {
                    return this._webStream;
                }

                // 如果是 Node stream，转换为 Web ReadableStream
                // 但不要消费它 - 使用 tee/克隆方案
                if (this._nodeStream && typeof Readable.toWeb === 'function') {
                    // 转换前克隆 stream 以避免消费
                    // Node.js stream 无法克隆，所以使用缓冲方案
                    // 替代方案：创建复制数据的 pass-through

                    // MCP SDK 兼容性，返回 web stream
                    // 但 text()/json() 从缓冲读取，不从 stream 读取
                    this._webStream = Readable.toWeb(this._nodeStream);
                    this._webStream.cancel = async function(reason) {
                        const reader = this._webStream.getReader();
                        await reader.cancel(reason);
                    };
                    return this._webStream;
                }

                // 备用：返回 null 或原始 body
                return null;
            }

            // 覆盖 text() 使用 node-fetch 的原始实现
            async text() {
                // 使用 node-fetch 的 buffer 方法，正确处理 Node stream
                const buffer = await this.buffer();
                return buffer.toString('utf-8');
            }

            // 覆盖 json() 使用 text() 方法
            async json() {
                const text = await this.text();
                return JSON.parse(text);
            }

            // 覆盖 buffer() 正确处理 Node stream
            async buffer() {
                if (this._nodeStream) {
                    // 直接从 Node stream 读取
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

        // 简单 polyfill - 包装 node-fetch 并返回 CustomResponse
        globalThis.fetch = async function(url, opts) {
            const response = await nodeFetch(url, opts);
            // 返回包装原始 response 的 CustomResponse
            return new CustomResponse(response.body, {
                status: response.status,
                statusText: response.statusText,
                headers: response.headers
            });
        };

        globalThis.Headers = nodeFetch.Headers;
        globalThis.Request = nodeFetch.Request;
        globalThis.Response = CustomResponse;

        console.log('[SSH] fetch polyfill 加载成功 (CustomResponse 延迟 stream 转换)');
    } catch (e) {
        console.error('[SSH] node-fetch 加载失败:', e.message);
        console.error('[SSH] Stack:', e.stack);
    }
}
```

**关键修复**：

1. **Polyfill 条件**：原条件 `typeof globalThis.fetch === 'undefined' || typeof WebAssembly === 'undefined'` 是**错误的**。在 `--jitless` 模式下：
   - `globalThis.fetch` 存在（是个函数）
   - `WebAssembly` 不存在
   - 原生 fetch 存在但调用时静默失败（返回 "fetch failed" TypeError）

   polyfill 必须只检查 `WebAssembly === undefined`，不能检查 `fetch === undefined`。

2. **ANTHROPIC_AUTH_TOKEN 空字符串**：不要设置 `export ANTHROPIC_AUTH_TOKEN=''`（空字符串）。
   - SDK 检查 `if (this.authToken == null)` 来决定认证方式
   - 空字符串 `''` 不是 `null`，所以 SDK 会发送 `Authorization: Bearer ''`
   - LiteLLM 拒绝空的 Bearer token，返回 401 Unauthorized

3. **CustomResponse 类 stream 转换**（对 MCP 至关重要，关键 Bug 修复 2026-05-20）：
   - `Readable.toWeb()` 会消费原始 Node stream，导致 `text()`/`json()` 调用失败
   - node-fetch@2 Response.body 是 Node.js Readable stream (PassThrough)，不是 Web ReadableStream
   - MCP SDK 使用 Web Streams API: `body.pipeThrough(new TextDecoderStream).pipeThrough(new EventSourceParserStream).getReader()`
   - Node.js stream 没有 `pipeThrough` 和 `getReader` 方法
   - 解决方案：使用 `CustomResponse` 类延迟处理 stream 转换
   - 覆盖 `text()`/`json()`/`buffer()` 从原始 Node stream 读取
   - 覆盖 `body` getter 在直接访问时返回 Web ReadableStream
   - 确保 MCP SDK (Web Streams) 和标准 `text()/json()` 都能正常工作

4. **Response.body.cancel()**：Web ReadableStream 的 reader 有 `cancel()`，但 SDK 可能直接调用 `body.cancel()`。
   - 添加 `webStream.cancel = async function() { reader.cancel() }` 作为备用

5. **SSH 远程执行环境变量**（关键）：Shell `source ~/.claude/.env` 不传递变量到 Node.js。
   - SSH 非交互式 shell 在独立进程中运行
   - `source` 在 shell 中设置变量，但 Node.js 子进程不继承它们
   - 结果：API 调用因 `ANTHROPIC_API_KEY` 未定义而返回 401
   - 解决方案：polyfill 必须直接读取 `.env` 文件并设置 `process.env`

**额外注意事项**：
- `--lite-mode` 也禁用 WebAssembly，与 `--jitless` 问题相同
- 不要在 SSH 会话中使用 `NODE_OPTIONS`（会导致同样的崩溃）
- 使用硬编码路径替代命令替换 (`$(...)")
- LLM API 请求可能需要 30-60 秒，确保设置足够的超时时间

## 生成的文件

| 二进制文件 | 大小 | 用途 |
|----------|------|------|
| dropbear | 285KB | SSH 服务器 |
| dbclient | 273KB | SSH 客户端 |
| dropbearkey | 187KB | 密钥生成 |
| dropbearconvert | 195KB | 密钥格式转换 |

## 与 OpenSSH 对比

| 特性 | Dropbear | OpenSSH |
|-----|----------|---------|
| 二进制大小 | ~1MB 总计 | ~4MB+ |
| 配置复杂度 | 手动 Makefile | 复杂的 autoconf |
| 密码认证 | 不支持（无 crypt） | 需要 crypt |
| 构建时间 | ~5 分钟 | ~15+ 分钟 |
| 依赖项 | 内置 libtomcrypt | OpenSSL 头文件 |
| HarmonyOS 补丁 | 5 个源文件 | 更复杂 |

由于构建过程更简单且内置加密库，推荐在 HarmonyOS 上使用 Dropbear。