# cryptography 包 HarmonyOS 适配指南

本指南记录了 `cryptography` Python 包 (v48.0.0) 在 HarmonyOS 上的完整适配过程，涵盖依赖链：libffi → cffi → maturin → OpenSSL 开发文件 → cryptography。

## 概述

cryptography 是提供密码学原语和协议的 Python 包。自 v36 起，核心实现使用 Rust (PyO3)，构建后端使用 maturin。其依赖链使其成为 HarmonyOS 上最复杂的 Python 包之一。

**结果**: cryptography v48.0.0 — **12/12 端到端测试通过**（AES-CBC、AES-GCM、RSA-2048、ECDSA、Ed25519、SHA/MD5 哈希、HMAC、PBKDF2、X.509、Fernet、ChaCha20-Poly1305、密钥序列化）

## 依赖链

```
cryptography (v48.0.0)
├── cffi >=2.0.0           → 需要 libffi（HarmonyOS 上不存在）
├── maturin（构建后端）    → 需要 Rust 工具链 + cargo
├── OpenSSL (libssl/libcrypto) → 系统有 .so.3 但无开发头文件/pkg-config
└── Rust 工具链           → aarch64-unknown-linux-ohos 目标
```

## 步骤 1: 从源码编译 libffi

HarmonyOS 缺少 libffi（无 `ffi.h`，无 `libffi.so`）。必须在无 autotools（无 automake/aclocal）的情况下手动编译。

### 1.1 下载 libffi 源码

```bash
cd $HOME/Claude/cryptography-build
curl -fL https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz \
  --proxy socks5://127.0.0.1:7890 \
  -o libffi-3.4.6.tar.gz
tar xzf libffi-3.4.6.tar.gz
```

### 1.2 手动构建脚本

关键适配点：
- **ffi.h.in 模板变量**: 用 sed 替换 `@TARGET@` → `AARCH64`、`@HAVE_LONG_DOUBLE@` → `1`、`@FFI_EXEC_TRAMPOLINE_TABLE@` → `0`
- **FFI_HIDDEN 宏**: C 代码使用 `__attribute__((visibility("hidden")))`，.S 汇编文件需要 `.hidden name` 指令 — 需要为 C 和汇编编译分别设置不同的 include 路径
- **memcpy→bcopy 宏冲突**: `ffi_common.h` 有 `#define memcpy(d,s,n) bcopy((s),(d),(n))`，与 HarmonyOS 的 bcopy 签名冲突 — 必须删除此行

完整构建脚本位于 `$HOME/Claude/cryptography-build/build-libffi.sh`。关键摘录：

```bash
# 从模板生成 ffi.h（无 autotools）
sed -e 's/@VERSION@/3.4.6/' \
    -e 's/@TARGET@/AARCH64/' \
    -e 's/@HAVE_LONG_DOUBLE@/1/' \
    -e 's/@FFI_EXEC_TRAMPOLINE_TABLE@/0/' \
    ffi.h.in > "$INSTALL_DIR/include/ffi.h"

# 为 C 编译生成 fficonfig.h（含 FFI_HIDDEN）
cat > "$INSTALL_DIR/include/fficonfig.h" << 'EOF'
#define AARCH64 1
#define HAVE_LONG_DOUBLE 1
#define HAVE_MMAP 1
#define FFI_HIDDEN __attribute__((visibility("hidden")))
EOF

# 创建独立的 asm_inc/ 目录，不含 FFI_HIDDEN（用于 .S 编译）
mkdir -p "$ASM_INC"
sed '/^#define FFI_HIDDEN/d' "$INSTALL_DIR/include/fficonfig.h" > "$ASM_INC/fficonfig.h"

# 删除有害的 memcpy→bcopy 宏
sed -i '/^#define memcpy.*bcopy/d' src/aarch64/ffi_common.h

# 编译 .c 文件（C 风格 FFI_HIDDEN，来自 fficonfig.h）
clang -I"$INSTALL_DIR/include" -c src/aarch64/ffi.c -o ffi.o

# 编译 .S 文件（汇编风格 FFI_HIDDEN 通过 -D，asm_inc 在 -I 中优先）
clang -D 'FFI_HIDDEN(x)=.hidden x' \
  -I"$ASM_INC" -I"$INSTALL_DIR/include" \
  -c src/aarch64/sysv.S -o sysv.o
```

**关键修复**: sysv.S 中的 `#include <fficonfig.h>` 会覆盖命令行 `-D FFI_HIDDEN`。必须将 asm_inc 路径放在 `-I` 顺序首位，使其不含 FFI_HIDDEN 的 fficonfig.h 优先。

### 1.3 安装和签名

```bash
# 链接共享库
clang -shared -o "$INSTALL_DIR/lib/libffi.so.8.1.4" *.o

# 代码签名
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile "$INSTALL_DIR/lib/libffi.so.8.1.4" \
  -outFile signed -signAlg SHA256withECDSA
mv signed "$INSTALL_DIR/lib/libffi.so.8.1.4"

# 创建符号链接并安装到 ~/.local
ln -sf libffi.so.8.1.4 "$INSTALL_DIR/lib/libffi.so.8"
ln -sf libffi.so.8 "$INSTALL_DIR/lib/libffi.so"
cp -r "$INSTALL_DIR/include" $HOME/.local/include/
cp -r "$INSTALL_DIR/lib" $HOME/.local/lib/
```

## 步骤 2: 安装 cffi

```bash
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CXX=/data/service/hnp/bin/clang++ \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/.local/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L$HOME/.local/lib" \
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
pip install cffi

# 签名 cffi 后端 .so 并修复后缀
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so \
  -outFile signed -signAlg SHA256withECDSA
mv signed $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so

# 修复 .so 后缀（Python 需要 .cpython-312-aarch64-linux-gnu.so）
mv $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so \
   $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312-aarch64-linux-gnu.so
```

## 步骤 3: 安装 maturin

maturin 是 cryptography 的构建后端。需要 Rust + cargo。

### 3.1 cargo install maturin

```bash
CC=/data/service/hnp/bin/clang \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
CARGO_HOME=$HOME/.rust \
RUSTUP_HOME=$HOME/.rust \
SSL_CERT_FILE=$HOME/.rust/cacert.pem \
TMPDIR=$HOME/Claude/tmpdir \
cargo install maturin
```

### 3.2 签名 maturin 二进制

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/maturin \
  -outFile $HOME/.local/bin/maturin.signed \
  -signAlg SHA256withECDSA
mv $HOME/.local/bin/maturin.signed $HOME/.local/bin/maturin
chmod +x $HOME/.local/bin/maturin
```

### 3.3 修复 platform.system() 不匹配

**关键问题**: maturin 检查 Python 的 `platform.system()` 是否与 Rust target OS 匹配。在 HarmonyOS 上，`platform.system()` 返回 `"HarmonyOS"`，但 Rust target 是 `aarch64-unknown-linux-ohos`（OS = `"Linux"`）。此不匹配导致 maturin 拒绝构建，报错："platform.system() in python, harmonyos, and the rust target, Target { os: Linux, ... }, don't match"。

**修复**: 创建 `sitecustomize.py` 补丁 `platform.system()`:

```python
# $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
import platform

_original_system = platform.system
def _patched_system():
    result = _original_system()
    if result == "HarmonyOS":
        return "Linux"
    return result

platform.system = _patched_system
```

Python 启动时自动加载 `sitecustomize.py`，此补丁全局生效。之后 `platform.system()` 返回 `"Linux"`，maturin 的平台检查通过。

**注意**: 这是一个全局性的 workaround，影响所有 Python 代码。如果其他场景需要 `platform.system()` 返回 `"HarmonyOS"`，需要更精细的方案（例如仅在 maturin 构建时补丁）。

## 步骤 4: 配置 OpenSSL 开发文件

HarmonyOS 有 OpenSSL 运行库（`/usr/lib/libssl.so.3`、`/usr/lib/libcrypto.so.3`）但没有开发头文件或 pkg-config 文件。cryptography 的 Rust 构建（`openssl-sys` crate）需要这些。

### 4.1 下载 OpenSSL 头文件

下载与系统版本匹配的 OpenSSL 3.0 源码并复制头文件：

```bash
cd $HOME/Claude/cryptography-build
curl -fL https://github.com/openssl/openssl/releases/download/openssl-3.0.16/openssl-3.0.16.tar.gz \
  --proxy socks5://127.0.0.1:7890 \
  -o openssl-3.0.16.tar.gz
tar xzf openssl-3.0.16.tar.gz

# 复制头文件到 ~/.local/include/openssl/
mkdir -p $HOME/.local/include/openssl
cp -r openssl-3.0.16/include/openssl/*.h $HOME/.local/include/openssl/
```

### 4.2 创建 pkg-config 文件

```bash
mkdir -p $HOME/.local/lib/pkgconfig

# openssl.pc
cat > $HOME/.local/lib/pkgconfig/openssl.pc << 'EOF'
prefix=/storage/Users/currentUser/.local
exec_prefix=/storage/Users/currentUser/.local
libdir=/usr/lib
includedir=/storage/Users/currentUser/.local/include

Name: OpenSSL
Version: 3.0.16
Description: Secure Sockets Layer and cryptography libraries and tools
Requires: libcrypto
Libs: -L/usr/lib -lssl -lcrypto
Cflags: -I/storage/Users/currentUser/.local/include
EOF

# libcrypto.pc
cat > $HOME/.local/lib/pkgconfig/libcrypto.pc << 'EOF'
prefix=/storage/Users/currentUser/.local
exec_prefix=/storage/Users/currentUser/.local
libdir=/usr/lib
includedir=/storage/Users/currentUser/.local/include

Name: libcrypto
Version: 3.0.16
Description: OpenSSL cryptography library
Libs: -L/usr/lib -lcrypto
Cflags: -I/storage/Users/currentUser/.local/include
EOF

# libssl.pc
cat > $HOME/.local/lib/pkgconfig/libssl.pc << 'EOF'
prefix=/storage/Users/currentUser/.local
exec_prefix=/storage/Users/currentUser/.local
libdir=/usr/lib
includedir=/storage/Users/currentUser/.local/include

Name: libssl
Version: 3.0.16
Description: Secure Sockets Layer and cryptography library
Requires: libcrypto
Libs: -L/usr/lib -lssl
Cflags: -I/storage/Users/currentUser/.local/include
EOF
```

### 4.3 创建无版本号的符号链接（供链接器使用）

```bash
# ld.bfd 链接时需要无版本号的 .so
ln -sf /usr/lib/libssl.so.3 $HOME/.local/lib/libssl.so
ln -sf /usr/lib/libcrypto.so.3 $HOME/.local/lib/libcrypto.so
```

## 步骤 5: 使用 --no-build-isolation 构建 cryptography

pip 的构建隔离会创建新环境，不会继承 RUSTFLAGS/CC/LD_LIBRARY_PATH。使用 `--no-build-isolation` 并设置所有必要环境变量：

```bash
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CXX=/data/service/hnp/bin/clang++ \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/.local/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L/usr/lib -L$HOME/.local/lib" \
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib" \
CARGO_HOME=$HOME/.rust \
RUSTUP_HOME=$HOME/.rust \
SSL_CERT_FILE=$HOME/.rust/cacert.pem \
pip install cryptography --no-build-isolation
```

**与其他 Rust 扩展相比，cryptography 需要的额外设置**:
- `LDFLAGS="-L/usr/lib -L$HOME/.local/lib"` — 链接器必须找到 libssl/libcrypto
- `RUSTFLAGS="-C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib"` — cargo 链接器搜索路径
- `PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig"` — openssl-sys 通过 pkg-config 查找 OpenSSL

## 步骤 6: 签名 cryptography .so 扩展

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/python3.12/site-packages/cryptography/hazmat/bindings/_rust.abi3.so \
  -outFile signed -signAlg SHA256withECDSA
mv signed $HOME/.local/lib/python3.12/site-packages/cryptography/hazmat/bindings/_rust.abi3.so
```

## 步骤 7: 验证

```bash
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64" \
python3 -c "import cryptography; print(cryptography.__version__)"
# 输出: 48.0.0
```

## 端到端测试结果

12/12 测试通过：

| 测试 | 描述 | 结果 |
|------|------|------|
| AES-256-CBC | 对称加密/解密（含填充） | 通过 |
| AES-256-GCM | 认证加密（含标签验证） | 通过 |
| RSA-2048 | 密钥生成、签名/验证(PSS)、加密/解密(OAEP)、PEM/DER 序列化 | 通过 |
| EC SECP256R1 | 密钥生成、ECDH 密钥交换、ECDSA 签名/验证 | 通过 |
| Ed25519 | 签名/验证 | 通过 |
| SHA256/384/512 | 哈希摘要 | 通过 |
| SHA3_256 | SHA-3 哈希 | 通过 |
| MD5 | 传统哈希（OpenSSL legacy provider 警告） | 通过 |
| HMAC-SHA256 | 消息认证 | 通过 |
| PBKDF2-SHA256 | 密钥派生 | 通过 |
| X.509 | 证书创建、签名、解析 | 通过 |
| Fernet | 高层对称加密（含 TTL） | 通过 |
| ChaCha20-Poly1305 | AEAD 加密 | 通过 |
| 密钥序列化 | PEM/DER 私钥/公钥往返 | 通过 |

## HarmonyOS 适配问题汇总

| 问题 | 标准 Linux | HarmonyOS | 修复 |
|------|-----------|-----------|------|
| libffi | 系统包 (`apt install libffi-dev`) | 不存在 | 无 autotools 手动源码编译 |
| FFI_HIDDEN 宏 | autotools 生成正确配置 | C 与 .S 编译差异 | 创建独立 asm_inc，不含 FFI_HIDDEN 的 fficonfig.h |
| memcpy→bcopy 宏 | 可用（glibc bcopy 兼容） | 与 HarmonyOS bcopy 签名冲突 | sed 删除宏 |
| maturin 平台检查 | `platform.system()` = `"Linux"` 匹配 Rust target | 返回 `"HarmonyOS"`，不匹配 `"Linux"` | sitecustomize.py 补丁 platform.system() |
| pip 构建隔离 | 可用（继承环境变量） | 不继承 RUSTFLAGS/CC | 使用 `--no-build-isolation` |
| OpenSSL 开发文件 | 系统包 (`apt install libssl-dev`) | 仅运行时 .so.3，无头文件/pkg-config | 下载头文件 + 创建 pkg-config 文件 + 无版本号符号链接 |
| 链接器库搜索 | ld 搜索标准路径 | cargo 不传递 `-L/usr/lib` | RUSTFLAGS 中添加 `-C link-args=-L/usr/lib` |
| .so 签名 | 不需要 | 执行必须 | `binary-sign-tool sign -selfSign 1` |
| .so 后缀 | `.cpython-312.so` 可用 | 需要 `.cpython-312-aarch64-linux-gnu.so` | 安装后重命名 |

## 常见错误与修复

| 错误 | 原因 | 修复 |
|------|------|------|
| `don't match ಠ_ಠ`（maturin） | platform.system() 返回 "HarmonyOS" vs Rust target "Linux" | sitecustomize.py 补丁 |
| `Package openssl was not found`（pkg-config） | 系统无 openssl.pc | 创建 $HOME/.local/lib/pkgconfig/ 下的 pkg-config 文件 |
| `ld.lld: error: unable to find library -lssl` | 链接器找不到 libssl.so | RUSTFLAGS 添加 `-C link-args=-L/usr/lib` + 创建无版本号符号链接 |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so 后缀不匹配或未签名 | 重命名为 `.cpython-312-aarch64-linux-gnu.so` + 签名 |
| `.S 文件中 FFI_HIDDEN 未定义` | C 风格宏在汇编中不工作 | 创建独立 asm_inc/ 去除 FFI_HIDDEN + `-D 'FFI_HIDDEN(x)=.hidden x'` |
| `failed to run build_openssl.py`（cryptography-cffi） | cffi 后端 .so 未加载 | 签名 + 重命名 _cffi_backend .so |