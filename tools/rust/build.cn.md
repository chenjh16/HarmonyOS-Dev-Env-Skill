# Rust 1.95.0 on HarmonyOS - 完整构建指南

> **English version available at build.md**

## 概述

Rust 自 1.95.0 版本起官方支持 HarmonyOS 目标平台 `aarch64-unknown-linux-ohos`。本文档记录如何手动安装 Rust 工具链（rustup 尚不支持 HarmonyOS）。

**关键点**：
- 使用 **musl 版本** 的 cargo（ohos 版本存在 OpenSSL ABI 兼容问题）
- 所有 ELF 二进制文件必须进行代码签名
- 必须配置链接器路径（HarmonyOS 没有默认的 `cc`）

## 前置条件

- HarmonyOS SDK（含 clang 15.0.4）
- `libgcc_s.so.1`（从 Python cryptography 包中提取）
- 约 500MB 磁盘空间用于工具链

## 源码下载

Rust 工具链通过 `static.rust-lang.org` 分发。手动下载组件：

```bash
mkdir -p ~/Claude/rust-build/rust-dist
cd ~/Claude/rust-build/rust-dist

# 检查当前版本
curl -sL https://static.rust-lang.org/dist/channel-rust-stable.toml | grep "aarch64-unknown-linux-ohos"

# 下载组件（以 2026-04-16 为例）
BASE="https://static.rust-lang.org/dist/2026-04-16"

# rustc（ohos 版本）
curl -L "$BASE/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rustc.tar.gz

# rust-std（ohos 版本 - 目标平台标准库）
curl -L "$BASE/rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rust-std.tar.gz

# cargo（MUSL 版本 - 非 ohos 版本！）
curl -L "$BASE/cargo-1.95.0-aarch64-unknown-linux-musl.tar.gz" -o cargo.tar.gz
```

**重要**：使用 `aarch64-unknown-linux-musl` 版本的 cargo，而非 `aarch64-unknown-linux-ohos` 版本。ohos 版 cargo 动态链接 OpenSSL，但 HarmonyOS 的 OpenSSL 使用不同的命名（`libssl_openssl.z.so`）和 ABI。

## 安装步骤

### 步骤 1：解压组件

```bash
cd ~/Claude/rust-build/rust-dist

tar xzf rustc.tar.gz
tar xzf rust-std.tar.gz
tar xzf cargo.tar.gz
```

### 步骤 2：使用 install.sh 安装

```bash
INSTALL_DIR="$HOME/.rust"

./rustc-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./rust-std-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./cargo-1.95.0-aarch64-unknown-linux-musl/install.sh --prefix="$INSTALL_DIR" --destdir=""
```

### 步骤 3：代码签名

所有 ELF 二进制文件必须签名：

```bash
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
RUST_DIR="$HOME/.rust"

# 签名 rustc
$SIGN_TOOL sign -selfSign 1 \
    -inFile $RUST_DIR/bin/rustc \
    -outFile $RUST_DIR/bin/rustc.signed \
    -signAlg SHA256withECDSA
mv $RUST_DIR/bin/rustc.signed $RUST_DIR/bin/rustc
chmod +x $RUST_DIR/bin/rustc

# 签名 cargo
$SIGN_TOOL sign -selfSign 1 \
    -inFile $RUST_DIR/bin/cargo \
    -outFile $RUST_DIR/bin/cargo.signed \
    -signAlg SHA256withECDSA
mv $RUST_DIR/bin/cargo.signed $RUST_DIR/bin/cargo
chmod +x $RUST_DIR/bin/cargo

# 签名 lib/ 下所有 .so 文件
for f in $RUST_DIR/lib/*.so; do
    $SIGN_TOOL sign -selfSign 1 \
        -inFile "$f" \
        -outFile "${f}.signed" \
        -signAlg SHA256withECDSA
    mv "${f}.signed" "$f"
done

# 签名 rustlib bin 工具
for f in $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/*; do
    if [ -f "$f" ] && file "$f" | grep -q ELF; then
        $SIGN_TOOL sign -selfSign 1 \
            -inFile "$f" \
            -outFile "${f}.signed" \
            -signAlg SHA256withECDSA
        mv "${f}.signed" "$f"
    fi
done
```

### 步骤 4：提取并安装 libgcc_s.so.1

Cargo（musl 版本）需要 `libgcc_s.so.1`：

```bash
# 从 Python cryptography 包中提取
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/cryptography.libs/libgcc_s-c8ae3477.so.1 \
   $HOME/.rust/lib/libgcc_s.so.1

# 签名
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile $HOME/.rust/lib/libgcc_s.so.1 \
    -outFile $HOME/.rust/lib/libgcc_s.so.1.signed \
    -signAlg SHA256withECDSA
mv $HOME/.rust/lib/libgcc_s.so.1.signed $HOME/.rust/lib/libgcc_s.so.1
```

### 步骤 5：配置链接器

HarmonyOS 没有默认的 `cc` 链接器。创建 cargo 配置：

```bash
mkdir -p $HOME/.rust/.cargo

cat > $HOME/.rust/.cargo/config.toml << 'EOF'
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
EOF
```

### 步骤 6：配置 shell 环境

添加到 `~/.zshenv`：

```bash
# Rust toolchain
export RUST_HOME="$HOME/.rust"
export PATH="$RUST_HOME/bin:$PATH"
export LD_LIBRARY_PATH="/usr/lib:$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH"
export CARGO_HOME="$RUST_HOME"
export RUSTUP_HOME="$RUST_HOME"
```

## 验证

```bash
# 检查版本
rustc --version
# rustc 1.95.0 (59807616e 2026-04-14)

cargo --version
# cargo 1.95.0 (f2d3ce0bd 2026-03-21)

# 测试编译
cat > hello.rs << 'EOF'
fn main() {
    println!("Hello from Rust on HarmonyOS!");
}
EOF

rustc hello.rs -o hello
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile hello -outFile hello_signed
mv hello_signed hello && chmod +x hello
./hello
# Hello from Rust on HarmonyOS!
```

## 依赖链

### rustc 依赖

```
rustc (wrapper)
  → librustc_driver-*.so (277MB, Rust compiler core)
      → libc++_shared.so (system: /system/lib64/libc++_shared.so)
      → libc.so (musl)
```

### cargo（musl）依赖

```
cargo (musl version)
  → libgcc_s.so.1 (extracted from Python package)
  → libc.so (musl)
```

## 端到端测试

### 测试 1：Hello World

```rust
fn main() {
    println!("Hello from Rust on HarmonyOS!");
}
```

```bash
rustc hello.rs -C linker=/data/service/hnp/bin/clang -o hello
binary-sign-tool sign -selfSign 1 -inFile hello -outFile hello_s
mv hello_s hello && ./hello
```

### 测试 2：Cargo 项目

```bash
cargo init --name test-project
cd test-project
cargo build
binary-sign-tool sign -selfSign 1 -inFile target/debug/test-project -outFile target/debug/test-project.s
mv target/debug/test-project.s target/debug/test-project
./target/debug/test-project
cargo test  # 所有测试应通过
```

### 测试 3：FFI 与 C 交互

```rust
// rust_ffi.rs
use std::os::raw::{c_char, c_int};
use std::ffi::CStr;

#[no_mangle]
pub extern "C" fn rust_add(a: c_int, b: c_int) -> c_int {
    a + b
}

#[no_mangle]
pub extern "C" fn rust_greet(name: *const c_char) -> *mut c_char {
    let c_name = CStr::from_ptr(name);
    let greeting = format!("Hello from Rust, {}!", c_name.to_str().unwrap());
    let result = std::ffi::CString::new(greeting).unwrap();
    result.into_raw()
}
```

```bash
rustc --crate-type dylib rust_ffi.rs -o rust_ffi.so -C linker=/data/service/hnp/bin/clang
binary-sign-tool sign -selfSign 1 -inFile rust_ffi.so -outFile rust_ffi.so.s
mv rust_ffi.so.s rust_ffi.so
```

编译 C 调用程序并链接：
```bash
clang -o caller caller.c rust_ffi.so -Wl,-rpath,.
binary-sign-tool sign -selfSign 1 -inFile caller -outFile caller_s
mv caller_s caller && ./caller
```

## 已知问题

### 1. cargo ohos 版本 OpenSSL 不兼容

- Ohos cargo 链接 `libssl.so` + `libcrypto.so`
- HarmonyOS 使用 `libssl_openssl.z.so` 命名
- ABI 不匹配（缺少 `SSL_get0_group_name`）

**解决方案**：使用 musl 版本的 cargo

### 2. git clone 大型仓库

部分文件名/路径在 HarmonyOS 文件系统上创建失败。对大型仓库（如 rust-lang/rust）使用稀疏检出。

### 3. 编译后二进制需要签名

每次构建输出必须在执行前签名。考虑将签名步骤添加到构建脚本中。

## 平台目标

官方目标平台为 `aarch64-unknown-linux-ohos`：

- 架构：`aarch64`（ARM64）
- 厂商：`unknown`
- 操作系统：`linux-ohos`（HarmonyOS Linux 类环境）

其他可用目标：`armv7-unknown-linux-ohos`、`x86_64-unknown-linux-ohos`、`loongarch64-unknown-linux-ohos`

## Cargo SSL 证书配置

```bash
# 下载 CA 证书用于访问 crates.io
curl -L https://curl.se/ca/cacert.pem -o $HOME/.rust/cacert.pem

# 设置环境变量
export SSL_CERT_FILE="$HOME/.rust/cacert.pem"
```