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
| `src/common-session.c` | `getpwnam()` 失败 | 回退到当前 UID |
| `src/svr-auth.c` | Shell 验证失败 | 跳过 `/etc/shells` 检查 |
| `src/svr-authpubkey.c` | 权限检查失败 | 跳过文件所有权检查 |
| `src/svr-chansession.c` | PTY 分配失败 | 重用 authstate passwd |
| `src/loginrec.c` | 登录记录失败 | 使用 authstate UID |

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

# 3. 创建 config.h 和 options.h（详见 build.md）

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
# 前台运行带日志
dropbear -p 2222 -F -E

# 后台运行
dropbear -p 2222
```

### 连接

使用数字 UID 作为用户名：
```bash
dbclient 20020106@localhost -p 2222
# 从远程连接: ssh -p 2222 20020106@<HarmonyOS-IP>
```

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
2. **需要数字用户名** - 使用 UID（如 `20020106`）
3. **需要五个源码补丁** - 必须修改源文件
4. **PTY TIOCSCTTY 警告** - 可能失败但基本 shell 可用
5. **V8 JIT 崩溃** - Node.js 应用需要 `--jitless` + polyfill

## 故障排除

### "Login attempt for nonexistent user"

应用 `common-session.c` 补丁提供 passwd 回退。

### "must be owned by user or root"

应用 `svr-authpubkey.c` 补丁跳过权限检查。

### V8 崩溃 (ENOMEM)

使用 `--jitless` 模式 + node-fetch polyfill。详见 `tools/dropbear/build.md`。

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
- 完整构建指南: `tools/dropbear/build.md`
- SSH polyfill 脚本: `config/.claude/ssh-fetch-polyfill.js`