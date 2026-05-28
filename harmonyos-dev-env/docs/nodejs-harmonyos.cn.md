# HarmonyOS 上的 Node.js (DevNode-OH)

> **英文版本**: nodejs-harmonyos.md

## 概述

Node.js v24.13.0 在 HarmonyOS PC 上通过 **DevNode-OH**（应用市场）和 **HNP 包**（`/data/service/hnp/node.org/node_v24.13.0/`）提供。

**版本**: v24.13.0
**npm**: 11.6.2
**平台**: `openharmony` / `arm64`
**来源**: HarmonyOS 应用市场 (DevNode-OH) + HNP 包

## 关键问题: process.dlopen 阻止用户空间库加载

### 问题描述

HNP 安装的 Node.js 二进制文件 (`/data/service/hnp/node.org/node_v24.13.0/bin/node`) **没有 .codesign 段**。HarmonyOS 内核执行安全策略：**未签名的进程只能从系统路径** (`/system/lib64`, `/usr/lib`) **dlopen() 加载库文件**。这意味着 `process.dlopen()` — 所有原生 addon 包（bcrypt、better-sqlite3、canvas 等）使用的加载机制 — 对用户可写目录中的 `.node` 或 `.so` 文件返回 `ERR_DLOPEN_FAILED`（"Permission denied"）。

**证据**:
- `better-sqlite3.node`: "Permission denied" (ERR_DLOPEN_FAILED)
- `libffi.so.8` (用户编译): "Permission denied"
- 同样的文件通过 Python `ctypes.CDLL()` 和独立 C 程序 `dlopen()` 可以正常加载

**根本原因**: 限制不在 Node.js 源码中（POSIX 平台使用标准 `dlopen()`）。这是 HarmonyOS 内核级强制：未签名的 ELF 进程只能 dlopen 系统路径的库文件。

### 修复方案: 给 Node 二进制添加 .codesign 段

**不需要从源码重建 Node.js。** 只需给 Node 二进制添加 `.codesign` 段：

```bash
# 在用户空间创建签名副本
cp /data/service/hnp/node.org/node_v24.13.0/bin/node $HOME/.local/bin/node-harmonyos

/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/node-harmonyos \
  -outFile $HOME/.local/bin/node-harmonyos.signed \
  -signAlg SHA256withECDSA

mv $HOME/.local/bin/node-harmonyos.signed $HOME/.local/bin/node-harmonyos
chmod +x $HOME/.local/bin/node-harmonyos

# 创建符号链接，以便 PATH 优先使用
ln -sf node-harmonyos $HOME/.local/bin/node
```

**确保 `$HOME/.local/bin` 在 PATH 中排在 `/data/service/hnp/bin` 之前**，这样 npm/npx 也使用签名的 Node 二进制。

## 原生 Addon 编译与签名流程

### 步骤 1: 使用 HarmonyOS 工具链编译

```bash
export PATH=$HOME/.local/bin:$PATH  # 签名 Node 优先
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export CFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export CXXFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export TMPDIR=$HOME/Claude/tmpdir

npm install <原生-addon-包名>
```

**注意**: `-B$HOME/Claude/lib/linker_wrapper` 标志是**必需的** — 没有它，clang 会调用损坏的 `lld` 链接器（需要 `libxml2.so.16`，HarmonyOS 上不存在）。

### 步骤 2: 签名并修补 .node 文件

所有 `.node` 文件（ELF 共享对象）需要两个修改：

1. **添加 `libc++_shared.so` 依赖** — C++ addon 需要 C++ 运行时符号（`_Znwm` / operator new），Node 不导出这些符号
2. **添加 `.codesign` 段** — `process.dlopen` 从用户空间加载所必需

使用自动化脚本：

```bash
$HOME/.local/bin/sign-node-addon <.node-文件路径>
```

或手动操作：

```bash
# 移除已有 .codesign（patchelf 无法修改已签名的文件）
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign \
  addon.node addon_unsigned.node

# 添加 libc++_shared.so 依赖
/data/service/hnp/bin/patchelf --add-needed libc++_shared.so addon_unsigned.node

# 签名
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile addon_unsigned.node -outFile addon_signed.node

# 替换原文件
cp addon_signed.node addon.node
chmod 775 addon.node
```

**批量签名**项目中的所有 .node 文件：

```bash
find node_modules -name "*.node" -type f -exec \
  $HOME/.local/bin/sign-node-addon {} \;
```

## 已验证的原生 Addon（端到端测试）

| 包名 | 版本 | 状态 | 说明 |
|------|------|------|------|
| better-sqlite3 | 12.10.0 | ✓ 正常 | 完整 CRUD、预编译语句、参数绑定 |
| bcrypt | 6.0.0 | ✓ 正常 | hashSync、compareSync 均可用 |
| express | 5.2.1 | ✓ 正常 | HTTP 服务器、JSON 响应 |
| lodash | 4.18.1 | ✓ 正常 | 所有实用函数 |
| axios | 1.16.1 | ✓ 正常 | HTTP 客户端、外部 HTTPS 请求 |
| dayjs | 1.11.21 | ✓ 正常 | 日期格式化 |
| uuid | 14.0.0 | ✓ 正常 | v4 生成 |
| commander | 14.0.3 | ✓ 正常 | CLI 参数解析 |
| dotenv | 17.4.2 | ✓ 正常 | .env 加载 |
| jsdom | 29.1.1 | ✓ 正常 | DOM 操作 |
| ws | 8.21.0 | ✓ 正常 | WebSocket 服务器/客户端 |
| rxjs | 7.8.2 | ✓ 正常 | Observable、of() |
| socket.io | 4.8.3 | ✓ 正常 | 实时双向通信 |
| vitest | 4.1.7 | ✓ 正常 | 测试框架 (ESM import) |

**核心模块**: 14 个全部通过（fs、crypto、http、net、os、path、child_process、worker_threads、stream、url、Intl、SQLite 内置、async/await、ESM）— 100% 通过率。

**总计**: 23/23 端到端测试通过 (100%)。

## 已知问题

### 1. chalk v5 仅支持 ESM

chalk v5.6.2 在 package.json 中使用 `"type": "module"`。`require('chalk')` 返回空对象（无方法）。使用 chalk v4（CJS 兼容）或在 ESM 上下文中使用动态 `import()`。

### 2. sharp — 无预编译二进制

sharp 需要 libvips 预编译二进制。不存在 `openharmony-arm64` 平台的二进制。WASM 回退方案也失败（npm 强制 `cpu=wasm32` 匹配）。需要先从源码编译 libvips。

### 3. node-gyp V8 崩溃（使用未签名 Node 时）

使用**未签名**的系统 Node (`/data/service/hnp/bin/node`) 时，node-gyp 的配置步骤在子进程中调用 `node -p` 时 V8 崩溃（`Check failed: 12 == (*__errno_location())`，Signal 5/SIGTRAP）。使用**签名** Node 二进制后此问题解决。

### 4. canvas — 缺少 C 依赖

canvas 需要 pixman/cairo 系统库，HarmonyOS 上不可用。需要先手动编译这些 C 依赖库。

## 与标准 Node.js 的关键差异

### 1. /tmp 只读

```bash
export TMPDIR=$HOME/Claude/tmpdir
```

Node.js 正确尊重 `TMPDIR` — `os.tmpdir()` 返回 `$HOME/Claude/tmpdir`。

### 2. TLS 证书问题

```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**警告**: 这降低安全性。仅用于开发或可信网络。

### 3. SSH 会话中 V8 JIT 崩溃

```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**解决方案**: 使用 `--jitless` 模式:
```bash
node --jitless your-app.js
```

详见 [dropbear-harmonyos.cn.md](dropbear-harmonyos.cn.md) 中 SSH 设置和 V8 崩溃解决方案。

### 4. process.platform = "openharmony"

`process.platform` 返回 `openharmony`（不是 `linux`）。这可能影响检查特定平台的包。考虑通过 sitecustomize.js 修补（类似 Python 为 maturin 做的处理）。

## 隐私设置（关键）

在运行下载二进制文件的 Node.js 应用之前：

1. 打开 **设置**
2. 进入 **隐私和安全**
3. 点击 **高级**
4. 启用 **"运行来自非应用市场的扩展程序"**

## 相关文档

- [代码签名](code-signing.cn.md) — 详细代码签名说明
- [LD_LIBRARY_PATH](ld-library-path.cn.md) — 动态库路径配置
- [Python 扩展适配](python-extension-adaptation.cn.md) — 通用 .so 适配模式
- [Dropbear SSH](dropbear-harmonyos.cn.md) — SSH 服务器与 V8 崩溃解决方案
- [SELinux 分析](selinux-analysis.cn.md) — HarmonyOS 安全执行分析

---

*验证日期: 2026-05-28*
*平台: HarmonyOS HongMeng Kernel 1.12.0*
*端到端测试: 23/23 通过 (100%)*