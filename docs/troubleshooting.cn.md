# HarmonyOS 开发故障排除指南

> **英文版本**: troubleshooting.md

本指南整合了 HarmonyOS 开发中的常见问题和解决方案。

## 快速参考

| 问题 | 快速修复 | 完整指南 |
|------|----------|----------|
| `/tmp` 只读 | `export TMPDIR=$HOME/Claude/tmpdir` | [文件系统](#文件系统问题) |
| 代码签名 | 使用 `binary-sign-tool` | [代码签名](#代码签名) |
| LD_LIBRARY_PATH 冲突 | `/usr/lib` 放在最前面 | [库路径](#库路径) |
| SDK 链接器损坏 | 使用 ld.bfd 包装器 | [链接器](#链接器问题) |
| SSH 中 V8 JIT 崩溃 | `node --jitless` | [SSH V8 崩溃](#ssh-v8-崩溃) |
| Python 扩展失败 | 本地编译带 `-rdynamic` | [Python 扩展](#python-扩展) |
| .so 加载拒绝 | 签名 .so + 使用 `-rdynamic` Python | [SELinux](#selinux-阻止) |
| TLS 证书错误 | `NODE_TLS_REJECT_UNAUTHORIZED=0` | [TLS 问题](#tls-证书) |

---

## 文件系统问题

### 问题: /tmp 只读

**现象**:
```
Error: EROFS: read-only file system, open '/tmp/...'
```

**解决方案**:
```bash
export TMPDIR=$HOME/Claude/tmpdir
mkdir -p $TMPDIR
```

永久修复，添加到 `~/.zshenv`:
```bash
export TMPDIR=$HOME/Claude/tmpdir
```

---

## 代码签名

### 问题: 二进制无法执行

**现象**:
```
$ ./my-binary
./my-binary: Permission denied
```

**原因**: HarmonyOS 上所有 ELF 二进制必须签名。

**解决方案**:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ./my-binary \
  -outFile ./my-binary-signed \
  -signAlg SHA256withECDSA

mv ./my-binary-signed ./my-binary
```

批量签名:
```bash
./scripts/sign-all.sh <目录>
```

**完整指南**: [code-signing.cn.md](code-signing.cn.md)

---

## 库路径

### 问题: OpenSSL 符号版本冲突

**现象**:
```
ImportError: /storage/Users/.../lib/python3.12/site-packages/...so: 
undefined symbol: EVP_MD_CTX_pkey_ctx, version OPENSSL_3.0.0
```

**原因**: LD_LIBRARY_PATH 顺序错误。Rust 的 libssl 与系统 OpenSSL 冲突。

**解决方案**:
```bash
# 关键: /usr/lib 必须在最前面
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

**完整指南**: [ld-library-path.cn.md](ld-library-path.cn.md)

---

## 链接器问题

### 问题: SDK lld 缺少 libxml2.so.16

**现象**:
```
ld.lld: error: cannot find libxml2.so.16
```

**原因**: SDK 的 lld 在 HarmonyOS 上损坏。

**解决方案**: 创建 ld.bfd 包装器:
```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

然后添加 `-B$HOME/Claude/lib/linker_wrapper` 到 clang 命令:
```bash
clang -B$HOME/Claude/lib/linker_wrapper ...
```

**完整指南**: [CLAUDE.cn.md](../rules/CLAUDE.cn.md)

---

## SSH V8 崩溃

### 问题: Node.js 在 SSH 会话中崩溃

**现象**:
```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**原因**: V8 JIT 在 SSH PTY 环境中崩溃。

**方案 1**: 使用 `--jitless` 模式:
```bash
node --jitless your-app.js
```

**方案 2**: 使用 node-fetch polyfill:
```bash
node --jitless --require ~/.claude/ssh-fetch-polyfill.js your-app.js
```

**完整指南**: [dropbear-harmonyos.cn.md](dropbear-harmonyos.cn.md)

---

## Python 扩展

### 问题: 扩展模块权限拒绝

**现象**:
```
ImportError: dlopen() failed: Permission denied
```

**原因 1**: 扩展未代码签名。
**原因 2**: Python 未用 `-rdynamic` 编译。

**解决方案**:
1. 签名 .so 文件:
```bash
binary-sign-tool sign -selfSign 1 -inFile module.so -outFile module-signed.so -signAlg SHA256withECDSA
```

2. 确保 Python 用 `-rdynamic` 编译 (导出 948+ Py 符号，1521 总导出):
```bash
python3 -c "import ctypes; print(len([s for s in dir(ctypes.pythonapi) if not s.startswith('_')]))"
```

**完整指南**: [python-harmonyos.cn.md](python-harmonyos.cn.md)

---

## SELinux 阻止

### 问题: 用户路径 .so 加载拒绝

**现象**:
```
ImportError: cannot load numpy: Permission denied
```

**原因**: SELinux 路径策略阻止用户路径 (`hmdfs` 标签)。

**可用**:
- 系统路径 .so 文件 (`/data/service/hnp/`)
- 纯 Python 包
- 本地编译带 `-rdynamic` 的 Python
- **从 `$HOME/.local/lib/` 加载的签名 .so 扩展模块**（34/34 包测试全部通过 — 见 [python-packages-harmonyos.cn.md](python-packages-harmonyos.cn.md)）
- PyTorch、numpy、pillow、lxml、bcrypt、greenlet 等从用户安装路径加载的编译扩展

**可能有问题**:
- 从 `/storage/Users/currentUser/` 其他子路径加载的 .so 文件（未通过 pip 安装到 `$HOME/.local/`）
- 未进行代码签名的 .so 文件
- 由不带 `-rdynamic` 符号导出的 Python 加载的 .so 文件

> **注意**: 配合代码签名 + `-rdynamic` Python（导出 948+ Py 符号），从用户路径 `$HOME/.local/lib/python3.12/site-packages/` 加载的扩展模块可正常工作。原始 SELinux 限制在此场景下已被有效绕过。详见 [selinux-analysis.cn.md](selinux-analysis.cn.md)。

**解决方案选项**:
1. 将包安装到 `$HOME/.local/`（pip 默认路径）并确保代码签名
2. 使用 `-rdynamic` Python 构建以保证扩展模块兼容性
3. 如无法签名，使用纯 Python 替代方案

**完整指南**: [selinux-analysis.cn.md](selinux-analysis.cn.md)

---

## TLS 证书

### 问题: HTTPS 请求失败

**现象**:
```
Error: unable to verify the first certificate
```

**原因**: 系统 CA 证书不完整。

**解决方案 (仅开发)**:
```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**对于 Rust/cargo**:
```bash
export SSL_CERT_FILE=$HOME/.rust/cacert.pem
```

---

## 无 GCC

### 问题: Makefile 默认使用 GCC

**现象**:
```
make: gcc: Command not found
```

**原因**: HarmonyOS 只有 clang。

**解决方案**:
```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

对于 CMake:
```cmake
set(CMAKE_C_COMPILER /data/service/hnp/bin/clang)
set(CMAKE_CXX_COMPILER /data/service/hnp/bin/clang++)
```

---

## Python pip 问题

### 问题: pip 安装 C 扩展失败

**现象**:
```
Building wheel for package: error
```

**解决方案**:
```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
pip install <package>
```

**问题**: pip 网络超时

**解决方案**:
```bash
# 使用镜像
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 或使用代理
export HTTP_PROXY=http://127.0.0.1:7890
pip install <package>
```

**完整指南**: [python-packages-harmonyos.cn.md](python-packages-harmonyos.cn.md)

---

## Claude Code 问题

### 问题: ripgrep 权限拒绝

**现象**:
```
grep: Permission denied for /storage/.../rg
```

**解决方案**:
1. 在设置中启用 "运行来自非应用市场的扩展程序"
2. 重签 ripgrep:
```bash
binary-sign-tool sign -selfSign 1 -inFile rg -outFile rg-signed -signAlg SHA256withECDSA
```

**完整指南**: [claude-code-harmonyos.cn.md](claude-code-harmonyos.cn.md)

---

## PyTorch 问题

### 问题: PyTorch ImportError

**现象**:
```
ImportError: libtorch_cpu.so: cannot open shared object file
```

**解决方案**:
```bash
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH
```

**完整指南**: [pytorch-harmonyos.cn.md](pytorch-harmonyos.cn.md)

---

## llama.cpp 问题

### 问题: 模型加载慢

**解决方案**: 启用 NEON/SVE 优化:
```bash
llama-cli -m model.gguf -p "prompt" -ngl 0 -sm seed
```

**问题**: CoT 模型不推理

**解决方案**: 添加推理预算:
```bash
llama-cli -m qwen3.5-9b.gguf --reasoning-budget 8192 -p "问题"
```

**完整指南**: [llama-cpp-harmonyos.cn.md](llama-cpp-harmonyos.cn.md)

---

## 诊断命令

```bash
# 检查 SELinux 上下文
cat /proc/self/attr/current

# 检查文件 SELinux 标签
ls -Z <文件>

# 检查已加载库
cat /proc/self/maps | grep ".so"

# 检查 Python 符号导出
nm -D $HOME/.local/bin/python3 | grep Py | wc -l

# 检查代码签名
binary-sign-tool display-sign -inFile <二进制>

# 检查 LD_LIBRARY_PATH
echo $LD_LIBRARY_PATH

# 检查临时目录
echo $TMPDIR
```

---

*最后更新: 2026-05-20*