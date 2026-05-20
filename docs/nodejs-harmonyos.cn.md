# HarmonyOS 上的 Node.js (DevNode-OH)

> **英文版本**: nodejs-harmonyos.md

## 概述

Node.js 在 HarmonyOS PC 上通过 **DevNode-OH** 提供，这是应用市场的 HarmonyOS 原生 Node.js 发行版。

**版本**: v24.13.0 (已验证可用)
**来源**: HarmonyOS 应用市场 (DevNode-OH 包)

## 安装

### 步骤 1: 从应用市场安装

1. 在 HarmonyOS PC 上打开 **应用市场**
2. 搜索 **DevNode-OH**
3. 安装应用
4. 关闭并重新打开 **HiShell** 终端

### 步骤 2: 验证安装

```bash
node -v
# → v24.13.0

npm -v
# → 10.x.x
```

### 步骤 3: 配置 PATH

将 npm 全局 bin 目录加入 PATH:

```bash
echo 'export PATH=$(npm prefix -g)/bin:$PATH' >> $HOME/.zshrc
source $HOME/.zshrc
```

## 系统要求

### 隐私设置 (关键)

在运行下载二进制文件的 Node.js 应用 (如 Claude Code) 之前:

1. 打开 **设置**
2. 进入 **隐私和安全**
3. 点击 **高级**
4. 启用 **"运行来自非应用市场的扩展程序"**

这允许代码签名的下载二进制文件执行。

## 与标准 Node.js 的关键差异

### 1. /tmp 只读

HarmonyOS 的 `/tmp` 是只读的。设置 TMPDIR:

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

对于 Node.js 应用:
```bash
export NODE_TMPDIR=$HOME/Claude/tmpdir
```

### 2. TLS 证书问题

系统 CA 证书可能不完整。对于网络请求:

```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**警告**: 这降低安全性。仅用于开发或可信网络。

### 3. SSH 会话中 V8 JIT 崩溃

在 SSH 会话中运行 Node.js 时，V8 JIT 可能崩溃:

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**解决方案**: 使用 `--jitless` 模式:

```bash
node --jitless your-app.js
```

详见 [dropbear-harmonyos.cn.md](dropbear-harmonyos.cn.md) 中 SSH 设置和 V8 崩溃解决方案。

## npm 使用

### 安装全局包

```bash
npm install -g <package>
```

已验证可用的示例包:
- `claude-code` (HarmonyOS 移植版)
- `typescript`
- `eslint`

### 安装本地包

```bash
npm install <package>
```

### 使用 npm 镜像

在中国加速下载:

```bash
npm config set registry https://registry.npmmirror.com
```

## 已验证应用

| 应用 | 状态 | 说明 |
|------|------|------|
| node -v | ✓ 正常 | v24.13.0 |
| npm install | ✓ 正常 | 全局和本地 |
| Claude Code | ✓ 正常 | 需要 HarmonyOS 移植版 |
| TypeScript | ✓ 正常 | tsc 正确编译 |
| V8 JIT | ⚠ SSH 问题 | SSH 中使用 --jitless |

## 故障排除

### 下载二进制文件 "Permission denied"

1. 启用隐私设置 (见上文)
2. 确保二进制已代码签名:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <未签名> -outFile <已签名> \
  -signAlg SHA256withECDSA
```

### npm install 网络错误

1. 如使用 mihomo，检查代理设置:
```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
```

2. 或使用 npm 镜像:
```bash
npm config set registry https://registry.npmmirror.com
```

### Node.js 在 SSH 中崩溃

使用 `--jitless` 标志:
```bash
node --jitless your-app.js
```

## 相关文档

- [Claude Code for HarmonyOS](claude-code-harmonyos.cn.md) — AI 编程助手
- [Dropbear SSH](dropbear-harmonyos.cn.md) — SSH 服务器与 V8 崩溃解决方案
- [mihomo](mihomo-harmonyos.cn.md) — 代理配置

---

*验证日期: 2026-05-20*
*平台: HarmonyOS HongMeng Kernel 1.12.0*