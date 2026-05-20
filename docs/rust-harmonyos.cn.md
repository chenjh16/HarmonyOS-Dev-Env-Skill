# Rust 编译器 HarmonyOS (aarch64) 安装与端到端测试

## 1. 官方工具链：aarch64-unknown-linux-ohos 官方支持

Rust 自 1.95.0 版本起官方支持 HarmonyOS 目标 `aarch64-unknown-linux-ohos`（以及 armv7、loongarch64、x86_64 四个 ohos 目标）。工具链可直接从 `static.rust-lang.org` 下载，无需从源码编译。

下载 URL 格式：
```
https://static.rust-lang.org/dist/<date>/rustc-<version>-aarch64-unknown-linux-ohos.tar.gz
https://static.rust-lang.org/dist/<date>/rust-std-<version>-aarch64-unknown-linux-ohos.tar.gz
https://static.rust-lang.org/dist/<date>/cargo-<version>-aarch64-unknown-linux-ohos.tar.gz
```

通过 `channel-rust-stable.toml` 查看当前版本：
```bash
curl -sL https://static.rust-lang.org/dist/channel-rust-stable.toml | grep "aarch64-unknown-linux-ohos" | grep "url ="
```

---

## 2. 工具链安装：手动解压 + install.sh

在 HarmonyOS 上 `rustup-init` 没有 ohos 二进制文件（`aarch64-unknown-linux-ohos/rustup-init` 返回 404），需要手动安装。

### 步骤

```bash
# 1. 下载组件
mkdir -p ~/Claude/rust-build/rust-dist && cd ~/Claude/rust-dist
BASE="https://static.rust-lang.org/dist/2026-04-16"
curl -L "$BASE/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rustc.tar.gz
curl -L "$BASE/rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rust-std.tar.gz
curl -L "$BASE/cargo-1.95.0-aarch64-unknown-linux-musl.tar.gz" -o cargo.tar.gz  # 注意：使用 musl 版本！

# 2. 解压
tar xzf rustc.tar.gz
tar xzf rust-std.tar.gz
tar xzf cargo.tar.gz

# 3. 安装（指定自定义前缀）
INSTALL_DIR="$HOME/.rust"
./rustc-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./rust-std-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./cargo-1.95.0-aarch64-unknown-linux-musl/install.sh --prefix="$INSTALL_DIR" --destdir=""
```

### 注意：cargo 必须使用 musl 版本

ohos 版本的 cargo 动态链接 `libssl.so` + `libcrypto.so` + `libz.so`，但 HarmonyOS 系统 OpenSSL 使用 `.z.so` 命名方式（`libssl_openssl.z.so`、`libcrypto_openssl.z.so`），ABI 不兼容（缺少 `SSL_get0_group_name` 等符号）。Python 自带的 OpenSSL（`libssloh.so.3`）也不兼容。

**解决方案**：使用 `aarch64-unknown-linux-musl` 版本的 cargo。musl 版本仅依赖 `libgcc_s.so.1` + `libc.so`，不依赖 OpenSSL（OpenSSL 静态链接内嵌）。`libgcc_s.so.1` 可从 Python 包中获取。

---

## 3. 代码签名：所有 ELF 必须签名

HarmonyOS 要求所有可执行 ELF 二进制文件（包括 .so 动态库）在执行前进行代码签名。未签名直接报 `permission denied`（退出码 126），并非传统权限问题。

### 签名命令

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

### Rust 安装后需签名的文件

```bash
RUST_DIR="$HOME/.rust"

# rustc 主二进制
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/bin/rustc -outFile $RUST_DIR/bin/rustc.signed -signAlg SHA256withECDSA
mv $RUST_DIR/bin/rustc.signed $RUST_DIR/bin/rustc

# cargo 主二进制
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/bin/cargo -outFile $RUST_DIR/bin/cargo.signed -signAlg SHA256withECDSA
mv $RUST_DIR/bin/cargo.signed $RUST_DIR/bin/cargo

# rustlib 中的 .so 文件（动态加载必须签名）
for f in $RUST_DIR/lib/*.so; do
  binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
  mv "${f}.signed" "$f"
done

# rustlib bin 目录（lld、objcopy 等工具）
for f in $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-lld \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/gcc-ld/ld.lld \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-objcopy \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/wasm-component-ld; do
  binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
  mv "${f}.signed" "$f"
done

# libgcc_s.so.1（从 Python 包复制后签名）
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/cryptography.libs/libgcc_s-c8ae3477.so.1 \
   $RUST_DIR/lib/libgcc_s.so.1
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/lib/libgcc_s.so.1 -outFile $RUST_DIR/lib/libgcc_s.so.1.signed -signAlg SHA256withECDSA
mv $RUST_DIR/lib/libgcc_s.so.1.signed $RUST_DIR/lib/libgcc_s.so.1
```

**注意**：编译的 Rust 程序运行前也需要签名！签名是执行前的必要步骤。

---

## 4. 动态库依赖

### rustc 依赖链

```
rustc (15KB 包装器)
  → librustc_driver-cd4503251e9a57d5.so (277MB, Rust 编译器核心)
      → libc++_shared.so (系统: /system/lib64/libc++_shared.so)
      → libc.so
```

rustc 使用 musl libc（动态链接器 `/lib/ld-musl-aarch64.so.1`，系统 `/lib/` 下存在），但 librustc_driver 需要 `libc++_shared.so`（C++ 运行时），位于 `/system/lib64/`。

### cargo（musl 版本）依赖链

```
cargo (musl 版本)
  → libgcc_s.so.1（从 Python 包提取）
  → libc.so (musl libc)
```

### 必需的 LD_LIBRARY_PATH

```bash
export LD_LIBRARY_PATH=$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH
```

---

## 5. 链接器配置：无 cc，必须指定 clang

HarmonyOS 没有默认的 `cc` 命令。rustc 编译默认调用 `cc` 作为链接器，会报错 `linker 'cc' not found`。

### 解决方案

**方法一：命令行参数**
```bash
rustc hello.rs -C linker=/data/service/hnp/bin/clang
```

**方法二：cargo 配置（推荐）**

在项目 `.cargo/config.toml` 中：
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
```

**方法三：全局配置**

在 `$HOME/.rust/.cargo/config.toml` 中设置，所有 cargo 项目自动应用。

---

## 6. TMPDIR 配置

HarmonyOS 上 `/tmp` 是只读的。rustc 和 cargo 在 TMPDIR 中写入临时文件。必须设置：
```bash
export TMPDIR=/storage/Users/currentUser/Claude/tmpdir
```

或在 cargo config.toml 的 `[env]` 部分设置。

---

## 7. 环境变量汇总

所有第三方工具链环境变量配置在 `$HOME/.zshenv` 中，每次 zsh 启动时自动加载：

```bash
# ~/.zshenv 内容
export RUST_HOME="$HOME/.rust"
export PATH="$RUST_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH"
export CARGO_HOME="$RUST_HOME"
export RUSTUP_HOME="$RUST_HOME"

# llama.cpp 也添加到 PATH
export LLAMA_HOME="$HOME/Claude/llama.cpp/build/bin"
export PATH="$LLAMA_HOME:$PATH"
export LD_LIBRARY_PATH="$LLAMA_HOME:$LD_LIBRARY_PATH"

export TMPDIR="$HOME/Claude/tmpdir"
```

无需每次手动 source，新 shell 自动生效。

---

## 8. 端到端测试结果

### 测试 1：Hello World（rustc 直接编译）

```rust
fn main() {
    println!("Hello from Rust on HarmonyOS!");
}
```

```bash
rustc hello.rs -o hello -C linker=/data/service/hnp/bin/clang
binary-sign-tool sign -selfSign 1 -inFile hello -outFile hello_signed -signAlg SHA256withECDSA
mv hello_signed hello && chmod +x hello && ./hello
# 输出: Hello from Rust on HarmonyOS!
```

### 测试 2：核心语言特性

覆盖：斐波那契、泛型函数、结构体泛型、枚举+match、HashMap、VecDeque、字符串操作、迭代器+闭包、Option/Result、多线程（std::thread::spawn）。

结果：所有断言通过。

### 测试 3：高级特性

覆盖：文件 I/O（BufWriter/BufReader）、自定义错误类型+From 实现、生命周期、trait 对象（dyn Describe）、Rc/Arc/Box/RefCell 智能指针、切片操作、Range 迭代、match 守卫。

结果：所有断言通过。文件读写验证成功。

### 测试 4：系统互操作

覆盖：std::panic::catch_unwind、std::process::id、std::env::var、SystemTime/UNIX_EPOCH、Duration 操作、Cow、unsafe 原始指针、CString、宏（macro_rules!）。

结果：所有断言通过。

### 测试 5：C→Rust FFI 互操作

Rust 编译为 .so（`--crate-type dylib`），导出 extern "C" 函数：
```rust
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 { a + b }
#[no_mangle]
pub extern "C" fn rust_greet(name: *const c_char) -> *mut c_char { ... }
```

C 程序用 clang 编译并链接 Rust .so：
```bash
clang -o caller caller.c rust_ffi.so -Wl,-rpath,...
```

结果：`rust_add(10,20)=30`、`rust_greet("HarmonyOS")="Hello from Rust, HarmonyOS!"`，FFI 互操作成功。

**注意**：在 Rust 1.95.0 中，`CStr::from_ptr` 参数类型是 `*const c_char`（u8），不是 `*const i8`。需要使用 `std::os::raw::c_char` 而不是手写 `i8`。

### 测试 6：Cargo 完整流程

```bash
cargo init --name cargo-e2e   # 创建项目
cargo build                   # 编译成功（2.43秒）
binary-sign-tool sign ...     # 签名
./target/debug/cargo-e2e      # 运行成功
cargo test                    # 4 个集成测试全部通过
```

---

## 9. 已知问题与限制

### 9.1 cargo ohos 版本 OpenSSL 不兼容

ohos 版本 cargo 动态链接 `libssl.so` + `libcrypto.so`，但 HarmonyOS 系统 OpenSSL 库：
- 命名不同：`libssl_openssl.z.so`、`libcrypto_openssl.z.so`
- ABI 不兼容：缺少 `SSL_get0_group_name` 等新 OpenSSL 符号
- Python 自带的 `libssloh.so.3`/`libcryptooh.so.3` 也不兼容

**解决方案**：使用 musl 版本的 cargo（已验证可用）。

### 9.2 编译产物必须签名

每个编译的 Rust 二进制文件/动态库运行前必须签名。这是 HarmonyOS 安全机制要求，不是权限问题。可编写脚本批量签名。

### 9.3 git clone 大型仓库可能失败

HarmonyOS 文件系统对某些文件名（包含特殊字符或深层嵌套目录）有创建限制。`git clone rust-lang/rust`（59543 个文件）约 70+ 个文件创建失败（`unable to create file`），最终在 `tests/ui/layout/aggregate-lang` 目录名处致命错误。如需从源码编译 Rust，请使用稀疏检出或其他策略。

### 9.4 无默认 cc 链接器

所有 Rust 编译必须指定 `-C linker=/data/service/hnp/bin/clang`。建议在 cargo config.toml 中全局配置。

---

## 总结：HarmonyOS Rust 使用检查清单

1. **下载**：从 `static.rust-lang.org` 下载 ohos 版本 rustc + rust-std，musl 版本 cargo
2. **安装**：手动运行 `install.sh --prefix=$HOME/.rust`，不支持 rustup
3. **签名**：所有 ELF（rustc、cargo、.so、编译产物）必须用 `binary-sign-tool -selfSign 1` 签名
4. **依赖**：`LD_LIBRARY_PATH` 包含 `.rust/lib` + `/system/lib64`；`libgcc_s.so.1` 从 Python 包提取
5. **链接器**：cargo config.toml 指定 `linker = "/data/service/hnp/bin/clang"`
6. **TMPDIR**：设置 `TMPDIR=/storage/Users/currentUser/Claude/tmpdir`（/tmp 只读）
7. **Cargo**：必须使用 musl 版本（ohos 版本 OpenSSL ABI 不兼容）
8. **FFI**：Rust 1.95.0 的 c_char 是 u8 类型（不是 i8），CStr::from_ptr 使用 `*const c_char`