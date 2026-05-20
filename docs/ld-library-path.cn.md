# LD_LIBRARY_PATH 配置指南

## 关键问题：OpenSSL 符号版本冲突

在 HarmonyOS 上，`LD_LIBRARY_PATH` 中目录的顺序至关重要，因为存在 OpenSSL 符号版本冲突问题。

### 问题描述

如果 `$HOME/.rust/lib` 在 `LD_LIBRARY_PATH` 中位于 `/usr/lib` 之前，您将遇到 OpenSSL 符号版本错误：

```
Error: version `OPENSSL_3.0.0' not found
Error relocating: SSL_get0_group_name: symbol not found
```

### 根本原因

1. HarmonyOS 系统 OpenSSL 使用非标准命名：`libssl_openssl.z.so`、`libcrypto_openssl.z.so`
2. 这些库位于 `/usr/lib/`
3. Rust 工具链在 `$HOME/.rust/lib` 中包含自己的 OpenSSL 库
4. Rust OpenSSL 与系统 OpenSSL 具有不同的符号版本
5. 当 Rust OpenSSL 被优先找到时，期望系统 OpenSSL 符号的程序会失败

### 正确顺序

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

**`/usr/lib` 必须放在第一位！**

## 完整的 LD_LIBRARY_PATH 配置

HarmonyOS 开发推荐的配置：

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin:$LD_LIBRARY_PATH
```

详细说明：
- `/usr/lib` — 系统 OpenSSL 库（必须放在第一位）
- `$HOME/.rust/lib` — Rust 工具链库
- `$HOME/.local/lib` — 用户编译的库（libxml2、libxslt、libjpeg 等）
- `/system/lib64` — 系统 C++ 运行时、libc 等
- `$HOME/Claude/llama.cpp/build/bin` — llama.cpp OpenMP 库

## Shell 配置

添加到 `~/.zshenv`：

```bash
# LD_LIBRARY_PATH - 顺序很重要！
# /usr/lib 必须放在第一位以避免 OpenSSL 符号版本冲突
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin
```

## 验证

检查当前的 LD_LIBRARY_PATH：

```bash
echo $LD_LIBRARY_PATH
```

应输出：
```
/usr/lib:/storage/Users/currentUser/.rust/lib:/storage/Users/currentUser/.local/lib:/system/lib64:/storage/Users/currentUser/Claude/llama.cpp/build/bin
```

验证 OpenSSL 库解析：

```bash
ldd /data/service/hnp/bin/clang | grep ssl
# 不应显示 Rust 的 libssl
```

## 库加载调试

调试库加载问题：

```bash
# 检查加载了哪个库
LD_DEBUG=libs ./your-program 2>&1 | grep ssl

# 检查库搜索路径
LD_DEBUG=files ./your-program 2>&1 | head -50
```

## 常见问题

### OpenSSL 符号未找到

**症状**：
```
Error relocating: SSL_get0_group_name: symbol not found
```

**解决方案**：确保 `/usr/lib` 在 LD_LIBRARY_PATH 中位于第一位。

### Python 扩展无法加载

**症状**：
```
ImportError: dynamic module does not define init function
```

**解决方案**：
1. 检查 LD_LIBRARY_PATH 是否包含 `$HOME/.local/lib`
2. 确保扩展模块已签名

### Rust 程序启动时崩溃

**症状**：
```
zsh: trace trap (core dumped) ./rust-program
```

**解决方案**：
1. 检查 LD_LIBRARY_PATH 是否包含 `/system/lib64`（用于 C++ 运行时）
2. 确保程序已签名

### llama-cli 无法启动

**症状**：
```
Error loading shared library libomp.so
```

**解决方案**：将 llama.cpp bin 目录添加到 LD_LIBRARY_PATH。

## 按应用覆盖

如果应用程序需要特定的库顺序，可以临时覆盖：

```bash
LD_LIBRARY_PATH=/special/order ./special-app
```

或使用 `ld.so.conf` 风格的配置（不推荐用于 HarmonyOS）。

## 最佳实践

1. **始终将 `/usr/lib` 放在第一位** — 防止 OpenSSL 冲突
2. **使用绝对路径** — 避免变量展开问题
3. **将配置放在 `.zshenv` 中** — Shell 启动时自动加载
4. **不要重复条目** — 浪费搜索时间
5. **修改后测试** — 运行程序验证配置有效