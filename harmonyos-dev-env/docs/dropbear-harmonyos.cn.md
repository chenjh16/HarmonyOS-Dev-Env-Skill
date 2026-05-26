# Dropbear SSH 服务器在 HarmonyOS (aarch64) 上的适配指南

> **英文版本请查看 dropbear-harmonyos.md**

## 概述

Dropbear 是一个轻量级 SSH 服务器/客户端，相比 OpenSSH 在 HarmonyOS 上更容易编译。本文档记录完整的适配过程。

**结果**: Dropbear 2024.86 完全可用：
- 服务器: `dropbear` (285KB)
- 客户端: `dbclient` (273KB)
- 密钥生成: `dropbearkey` (187KB)
- 密钥转换: `dropbearconvert` (195KB)

**认证方式**: 仅支持公钥认证（无密码认证，因为缺少 `crypt()` 函数）

**安装位置**: `$HOME/.local/bin/`

## 关键适配

### 1. HarmonyOS 用户系统补丁

HarmonyOS 使用非传统的用户管理：
- 用户不在 `/etc/passwd` 中注册
- 进程 UID（如 20020106）与文件所有者 UID（如 20001006）不同
- 没有 `/etc/shells` 文件

需要修补五个源文件：

| 文件 | 问题 | 补丁 |
|------|------|------|
| `src/common-session.c` | `getpwnam()` 失败 | 接受任何非系统用户名作为设备用户 |
| `src/svr-auth.c` | Shell 验证失败 | 跳过 `/etc/shells` 检查 |
| `src/svr-authpubkey.c` | 权限检查失败 | 跳过文件所有权检查 |
| `src/svr-chansession.c` | PTY 分配失败 | 重用 authstate passwd |
| `src/loginrec.c` | 登录记录失败 | 接受任何非系统用户名（与 common-session 相同逻辑） |

### 2. 无 crypt() 函数

HarmonyOS 缺少用于密码哈希的 `crypt()` 函数。解决方案：禁用密码认证：
```c
// 在 options.h 中
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_CLI_PASSWORD_AUTH 0
```

### 3. 需要 ld.bfd 包装器

SDK 的 `lld` 需要 `libxml2.so.16`，但该文件不存在。使用 ld.bfd 包装器：
```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

### 4. config.h 配置

HarmonyOS 的关键设置：
```c
#undef HAVE_GETRANDOM  /* HarmonyOS 使用 /dev/urandom */
#define BUNDLED_LIBTOM 1
#define HAVE_OPENPTY 1
#define HAVE_PTY_H 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_IPV6 1
```

### 5. SSH 会话中 V8 JIT 崩溃

**问题**: Node.js V8 JIT 在 SSH PTY 环境中崩溃，错误码 `errno=ENOMEM`。

**解决方案**: 使用 `--jitless` 模式 + `node-fetch` polyfill：
```bash
node --jitless --require ~/.claude/ssh-fetch-polyfill.js \
    /path/to/claude-code/cli.js --dangerously-skip-permissions
```

**为什么需要 node-fetch polyfill**：
- `--jitless` 禁用 WebAssembly
- 原生 `fetch` 需要 WebAssembly 进行压缩
- `node-fetch` 使用 `http.request`（无需 WebAssembly）

## 构建摘要

```bash
# 1. 下载源码
cd $HOME/Claude/dropbear-build
curl -L -o dropbear-2024.86.tar.bz2 \
  "https://matt.ucc.asn.au/dropbear/releases/dropbear-2024.86.tar.bz2"
tar xjf dropbear-2024.86.tar.bz2

# 2. 构建 libtommath + libtomcrypt
cd libtommath && make
cd libtomcrypt && make -f makefile.unix

# 3. 创建 config.h 和 options.h（详见 build.cn.md）

# 4. 使用自定义 Makefile 构建
make dropbear dbclient dropbearkey dropbearconvert

# 5. 签名二进制文件
for binary in dropbear dbclient dropbearkey dropbearconvert; do
  llvm-objcopy --remove-section=.codesign $binary ${binary}.unsigned
  binary-sign-tool sign -selfSign 1 -inFile ${binary}.unsigned -outFile ${binary}.signed
  mv ${binary}.signed $binary
  chmod +x $binary
done

# 6. 生成主机密钥
mkdir -p $HOME/.local/etc/dropbear
dropbearkey -t rsa -f ~/.local/etc/dropbear/dropbear_rsa_host_key -s 2048
dropbearkey -t ecdsa -f ~/.local/etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f ~/.local/etc/dropbear/dropbear_ed25519_host_key
```

## 运行服务器

### 手动启动

```bash
# 前台运行带日志（-e 将父进程环境传递给子会话）
dropbear -p 2222 -e -F -E

# 后台运行（使用 -e 传递环境）
dropbear -p 2222 -e
```

**重要**：`-e` 参数将父进程的环境变量（LD_LIBRARY_PATH、PATH 等）传递给 SSH 子会话。没有 `-e` 时，`clearenv()` 会清除所有环境变量，只设置最小默认值（PATH=/usr/bin:/bin），导致 HarmonyOS 上的 SSH 会话异常。

### 连接

任何非系统用户名都可以使用（HarmonyOS 是单用户设备）：
```bash
# 任何用户名都可以
ssh -p 2222 chenh@localhost
ssh -p 2222 user@localhost
ssh -p 2222 currentUser@localhost

# 数字 UID 也可以
dbclient 20020106@localhost -p 2222
# 从远程连接: ssh -p 2222 chenh@<HarmonyOS-IP>
```

**注意**：交互式 SSH 会话（带 PTY 的 shell）有一个已知限制——`ioctl(TIOCSCTTY)` 在 HarmonyOS 上失败，导致没有控制终端。这意味着交互式会话中作业控制受限。命令执行模式（`ssh user@host command`）正常工作。

### 登录时自动启动

脚本位于 `$HOME/.local/bin/`：
- `start-ssh.sh [port]` - 启动服务器
- `stop-ssh.sh` - 停止服务器

在 `.zshrc` 中自动启动：
```bash
if [ -z "$NO_AUTOSTART_SSH" ]; then
    "$HOME/.local/bin/start-ssh.sh"
fi
```

禁用方式：`export NO_AUTOSTART_SSH=1`

## 已知限制

1. **无密码认证** - HarmonyOS 缺少 `crypt()`
2. **接受任何非系统用户名** - 所有用户名（除了 root/bin/system）映射到同一个设备用户
3. **需要五个源码补丁** - 必须修改源文件
4. **PTY TIOCSCTTY 失败** - 交互式会话没有控制终端（HarmonyOS 内核限制）；命令执行模式正常
5. **必须使用 `-e` 参数** - 环境传递对 SSH 子会话至关重要
6. **V8 JIT 崩溃** - Node.js 应用需要 `--jitless` + polyfill

## 故障排除

### "Login attempt for nonexistent user"

应用 `common-session.c` 和 `loginrec.c` 补丁。两者现在都接受任何非系统用户名作为设备用户。补丁后，`chenh`、`user`、`currentUser` 或数字 UID 等用户名均可使用。

### "must be owned by user or root"

应用 `svr-authpubkey.c` 补丁跳过权限检查。

### V8 崩溃 (ENOMEM)

使用 `--jitless` 模式 + node-fetch polyfill。详见 `tools/dropbear/build.cn.md`。

## 生成的文件

| 二进制 | 大小 | 用途 |
|--------|------|------|
| dropbear | 285KB | SSH 服务器 |
| dbclient | 273KB | SSH 客户端 |
| dropbearkey | 187KB | 密钥生成 |
| dropbearconvert | 195KB | 密钥转换 |

## 与 OpenSSH 对比

| 特性 | Dropbear | OpenSSH |
|------|----------|---------|
| 二进制大小 | ~1MB 总计 | ~4MB+ |
| 配置 | 手动 Makefile | 复杂 autoconf |
| 密码认证 | 不支持 | 需要 crypt |
| 构建时间 | ~5 分钟 | ~15+ 分钟 |
| 依赖 | 内置 libtomcrypt | OpenSSL headers |
| HarmonyOS 补丁 | 5 个源文件 | 更复杂 |

由于构建简单和内置加密库，推荐在 HarmonyOS 上使用 Dropbear。

## 参考

- Dropbear 源码: https://matt.ucc.asn.au/dropbear/releases/
- 完整构建指南: `tools/dropbear/build.cn.md`
- SSH polyfill 脚本: `scripts/ssh-fetch-polyfill.js`