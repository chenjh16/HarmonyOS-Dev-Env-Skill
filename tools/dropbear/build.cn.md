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

从 `src/default_options.h` 复制并修改：
- 设置 `DROPBEAR_SVR_PASSWORD_AUTH 0`（无 crypt()）
- 设置 `DROPBEAR_CLI_PASSWORD_AUTH 0`
- 更新密钥路径为 `~/.local/etc/dropbear/`

### 7. 创建 Makefile

使用项目中的 Makefile 或手动创建。

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

为 `getpwnam()` 失败添加 fallback，支持不在 passwd 中的用户：

```c
// 在 fill_passwd() 函数中，"pw = getpwnam(username);" 之后添加
pw = getpwnam(username);
if (!pw) {
    /* HarmonyOS fallback: 如果 getpwnam 失败，检查用户名是否匹配当前 UID */
    char uid_str[32];
    snprintf(uid_str, sizeof(uid_str), "%u", getuid());
    if (strcmp(username, uid_str) == 0 || strcmp(username, "currentUser") == 0) {
        /* 为当前用户创建虚拟 passwd entry */
        ses.authstate.pw_uid = getuid();
        ses.authstate.pw_gid = getgid();
        ses.authstate.pw_name = m_strdup(uid_str);
        ses.authstate.pw_dir = m_strdup(getenv("HOME") ? getenv("HOME") : "/storage/Users/currentUser");
        ses.authstate.pw_shell = m_strdup(getenv("SHELL") ? getenv("SHELL") : "/usr/bin/zsh");
        ses.authstate.pw_passwd = m_strdup("!!");
        return;
    }
    return;
}
```

**解释**：SSH 客户端使用用户名 `20020106`（进程 UID）连接时，`getpwnam()` 失败，因为 HarmonyOS 的 `/etc/passwd` 中没有这个用户。补丁使用当前进程的 UID/GID 和 HOME/SHELL 环境变量创建合成 passwd entry。

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

记录登录会话时，`login_init_entry()` 调用 `getpwnam()`。添加 fallback：

```c
// 在 login_init_entry() 函数中，约第 278 行
pw = getpwnam(li->username);
if (pw == NULL) {
    /* HarmonyOS fallback: 如果 getpwnam 失败，使用 authstate uid */
    if (ses.authstate.pw_name && strcmp(li->username, ses.authstate.pw_name) == 0) {
        li->uid = ses.authstate.pw_uid;
    } else {
        dropbear_exit("login_init_entry: Cannot find user \"%s\"", li->username);
    }
} else {
    li->uid = pw->pw_uid;
}
```

**注意**：需要在 loginrec.c 中添加 `#include "session.h"` 或声明 `extern struct sshsession ses;`。

**解释**：登录记录（utmp/wtmp）需要用户 UID 查找。在 HarmonyOS 上，`getpwnam()` 失败，所以使用 authstate 中的 UID。

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

由于 HarmonyOS 的非标准用户系统，SSH 连接必须使用数字 UID 作为用户名：

```bash
# 在 HarmonyOS 上获取你的 UID
echo $UID  # 例如，20020106

# 从远程机器连接
ssh -p 2222 20020106@<HarmonyOS-IP>

# 使用实际值的示例
ssh -p 2222 20020106@10.1.35.63
```

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
4. **必须使用数字用户名** - 必须使用 UID（如 `20020106`）而非人类可读的用户名
5. **需要源码补丁** - 必须修改五个源文件以支持 HarmonyOS
6. **PTY 控制终端警告** - `ioctl(TIOCSCTTY)` 可能因 HarmonyOS PTY 限制而失败，但基本 shell 功能正常

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

**解决方案**：应用 `common-session.c` 补丁（第 10 步），为当前 UID 提供 fallback passwd entry。

### "must be owned by user or root, and not writable by group or others"

日志显示：`/storage/Users/currentUser must be owned by user or root...`

**原因**：HarmonyOS 文件所有权模型与 Linux 不同：
- 进程 UID (20020106) != 文件所属 UID (20001006)
- 主目录有 group writable 权限 (`drwxrws--x`)

**解决方案**：应用 `svr-authpubkey.c` 补丁（第 10 步）以跳过权限验证。

### Permission denied (publickey) 添加密钥后

**检查**：
1. `~/.ssh/authorized_keys` 中的公钥格式正确
2. 使用正确的用户名（数字 UID 如 `20020106`）
3. 所有五个源码补丁已应用且 dropbear 已重新编译

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
// 重要：在 --jitless 模式下：
// - 原生 fetch 存在（typeof fetch === 'function'）
// - WebAssembly 不存在（typeof WebAssembly === 'undefined'）
// - 原生 fetch 虽然存在但调用时会失败（返回 "fetch failed" TypeError）
//
// 因此 polyfill 条件必须只检查 WebAssembly，不能检查 fetch 是否存在

if (typeof WebAssembly === 'undefined') {
    console.log('[SSH] WebAssembly 禁用 (--jitless 模式)，使用 node-fetch 替代 fetch...');
    try {
        // 使用绝对路径，因为 preload 在 cwd 设置前执行
        const nodeFetch = require('/storage/Users/currentUser/Claude/node_modules/node-fetch');
        globalThis.fetch = nodeFetch;
        globalThis.Headers = nodeFetch.Headers;
        globalThis.Request = nodeFetch.Request;
        globalThis.Response = nodeFetch.Response;
        console.log('[SSH] fetch polyfill 加载成功');
    } catch (e) {
        console.error('[SSH] node-fetch 加载失败:', e.message);
        // 失败时 fetch 调用会报错
    }
}
```

**关键修复**：原条件 `typeof globalThis.fetch === 'undefined' || typeof WebAssembly === 'undefined'` 是**错误的**。在 `--jitless` 模式下：
- `globalThis.fetch` 存在（是个函数）
- `WebAssembly` 不存在
- 原生 fetch 存在但调用时静默失败（返回 "fetch failed" TypeError）

polyfill 必须只检查 `WebAssembly === undefined`，不能检查 `fetch === undefined`。如果同时检查两个条件，原生 fetch（损坏的）会被检测到但不被替换，导致 API 调用返回 401 错误。

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