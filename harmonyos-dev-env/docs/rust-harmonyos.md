# Rust Compiler HarmonyOS (aarch64) Installation and End-to-End Testing

## 1. Official Toolchain: aarch64-unknown-linux-ohos officially supported

Rust since version 1.95.0 officially supports HarmonyOS target `aarch64-unknown-linux-ohos` (plus armv7, loongarch64, x86_64 four ohos targets). Toolchain can be downloaded directly from `static.rust-lang.org`, no need to compile from source.

Download URL format:
```
https://static.rust-lang.org/dist/<date>/rustc-<version>-aarch64-unknown-linux-ohos.tar.gz
https://static.rust-lang.org/dist/<date>/rust-std-<version>-aarch64-unknown-linux-ohos.tar.gz
https://static.rust-lang.org/dist/<date>/cargo-<version>-aarch64-unknown-linux-ohos.tar.gz
```

Check current version via `channel-rust-stable.toml`:
```bash
curl -sL https://static.rust-lang.org/dist/channel-rust-stable.toml | grep "aarch64-unknown-linux-ohos" | grep "url ="
```

---

## 2. Toolchain Installation: Manual extraction + install.sh

On HarmonyOS `rustup-init` has no ohos binary (`aarch64-unknown-linux-ohos/rustup-init` returns 404), need manual install.

### Steps

```bash
# 1. Download components
mkdir -p ~/Claude/rust-build/rust-dist && cd ~/Claude/rust-dist
BASE="https://static.rust-lang.org/dist/2026-04-16"
curl -L "$BASE/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rustc.tar.gz
curl -L "$BASE/rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rust-std.tar.gz
curl -L "$BASE/cargo-1.95.0-aarch64-unknown-linux-musl.tar.gz" -o cargo.tar.gz  # Note: use musl version!

# 2. Extract
tar xzf rustc.tar.gz
tar xzf rust-std.tar.gz
tar xzf cargo.tar.gz

# 3. Install (specify custom prefix)
INSTALL_DIR="$HOME/.rust"
./rustc-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./rust-std-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./cargo-1.95.0-aarch64-unknown-linux-musl/install.sh --prefix="$INSTALL_DIR" --destdir=""
```

### Note: cargo must use musl version

ohos version cargo links `libssl.so` + `libcrypto.so` + `libz.so`, but HarmonyOS system OpenSSL uses `.z.so` naming (`libssl_openssl.z.so`, `libcrypto_openssl.z.so`), ABI incompatible (missing `SSL_get0_group_name` etc symbols). Python bundled OpenSSL (`libssloh.so.3`) also incompatible.

**Solution**: Use `aarch64-unknown-linux-musl` version cargo. musl version only depends on `libgcc_s.so.1` + `libc.so`, doesn't depend on OpenSSL (OpenSSL vendored statically linked). `libgcc_s.so.1` can be obtained from Python package.

---

## 3. Code Signing: All ELF must be signed

HarmonyOS requires all executable ELF binaries (including .so dynamic libraries) to have code signature before execution. Unsigned directly reports `permission denied` (exit code 126), not traditional permission issue.

### Signing command

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

### Files to sign after Rust installation

```bash
RUST_DIR="$HOME/.rust"

# rustc main binary
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/bin/rustc -outFile $RUST_DIR/bin/rustc.signed -signAlg SHA256withECDSA
mv $RUST_DIR/bin/rustc.signed $RUST_DIR/bin/rustc

# cargo main binary
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/bin/cargo -outFile $RUST_DIR/bin/cargo.signed -signAlg SHA256withECDSA
mv $RUST_DIR/bin/cargo.signed $RUST_DIR/bin/cargo

# .so files in rustlib (must be signed for dynamic loading)
for f in $RUST_DIR/lib/*.so; do
  binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
  mv "${f}.signed" "$f"
done

# rustlib bin directory (lld, objcopy etc tools)
for f in $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-lld \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/gcc-ld/ld.lld \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-objcopy \
         $RUST_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/wasm-component-ld; do
  binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
  mv "${f}.signed" "$f"
done

# libgcc_s.so.1 (copied from Python package then signed)
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/cryptography.libs/libgcc_s-c8ae3477.so.1 \
   $RUST_DIR/lib/libgcc_s.so.1
binary-sign-tool sign -selfSign 1 -inFile $RUST_DIR/lib/libgcc_s.so.1 -outFile $RUST_DIR/lib/libgcc_s.so.1.signed -signAlg SHA256withECDSA
mv $RUST_DIR/lib/libgcc_s.so.1.signed $RUST_DIR/lib/libgcc_s.so.1
```

**Note**: Compiled Rust programs also need signing before running! Signing is necessary step before execution.

---

## 4. Dynamic Library Dependencies

### rustc dependency chain

```
rustc (15KB wrapper)
  → librustc_driver-cd4503251e9a57d5.so (277MB, Rust compiler core)
      → libc++_shared.so (system: /system/lib64/libc++_shared.so)
      → libc.so
```

rustc uses musl libc (dynamic linker `/lib/ld-musl-aarch64.so.1`, exists in `/lib/` on system), but librustc_driver needs `libc++_shared.so` (C++ runtime), located at `/system/lib64/`.

### cargo (musl version) dependency chain

```
cargo (musl version)
  → libgcc_s.so.1 (extracted from Python package)
  → libc.so (musl libc)
```

### Required LD_LIBRARY_PATH

```bash
export LD_LIBRARY_PATH=$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH
```

---

## 5. Linker Configuration: No cc, must specify clang

HarmonyOS has no default `cc` command. rustc compilation by default calls `cc` as linker, will error `linker 'cc' not found`.

### Solution

**Method 1: Command line parameter**
```bash
rustc hello.rs -C linker=/data/service/hnp/bin/clang
```

**Method 2: cargo config (recommended)**

In project `.cargo/config.toml`:
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
```

**Method 3: Global config**

Set in `$HOME/.rust/.cargo/config.toml`, all cargo projects auto apply.

---

## 6. TMPDIR Configuration

`/tmp` is read-only on HarmonyOS. rustc and cargo write temp files in TMPDIR. Must set:
```bash
export TMPDIR=$HOME/Claude/tmpdir
```

Or set in cargo config.toml `[env]` section.

---

## 7. Environment Variables Summary

All third-party toolchain environment variables configured in `$HOME/.zshenv`, auto loaded on each zsh startup:

```bash
# ~/.zshenv content
export RUST_HOME="$HOME/.rust"
export PATH="$RUST_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH"
export CARGO_HOME="$RUST_HOME"
export RUSTUP_HOME="$RUST_HOME"

# llama.cpp also added to PATH
export LLAMA_HOME="$HOME/Claude/llama.cpp/build/bin"
export PATH="$LLAMA_HOME:$PATH"
export LD_LIBRARY_PATH="$LLAMA_HOME:$LD_LIBRARY_PATH"

export TMPDIR="$HOME/Claude/tmpdir"
```

No need to manually source each time, new shell auto applies.

---

## 8. End-to-End Test Results

### Test 1: Hello World (rustc direct compilation)

```rust
fn main() {
    println!("Hello from Rust on HarmonyOS!");
}
```

```bash
rustc hello.rs -o hello -C linker=/data/service/hnp/bin/clang
binary-sign-tool sign -selfSign 1 -inFile hello -outFile hello_signed -signAlg SHA256withECDSA
mv hello_signed hello && chmod +x hello && ./hello
# Output: Hello from Rust on HarmonyOS!
```

### Test 2: Core Language Features

Covered: Fibonacci, generic functions, struct generics, enum+match, HashMap, VecDeque, string operations, iterators+closures, Option/Result, multithreading (std::thread::spawn).

Result: All assertions passed.

### Test 3: Advanced Features

Covered: File I/O (BufWriter/BufReader), custom error types+From impl, lifetimes, trait objects (dyn Describe), Rc/Arc/Box/RefCell smart pointers, slice operations, Range iteration, match guards.

Result: All assertions passed. File read/write verified.

### Test 4: System Interop

Covered: std::panic::catch_unwind, std::process::id, std::env::var, SystemTime/UNIX_EPOCH, Duration operations, Cow, unsafe raw pointers, CString, macros (macro_rules!).

Result: All assertions passed.

### Test 5: C→Rust FFI Interop

Rust compiled to .so (`--crate-type dylib`), exports extern "C" functions:
```rust
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 { a + b }
#[no_mangle]
pub extern "C" fn rust_greet(name: *const c_char) -> *mut c_char { ... }
```

C program compiled with clang and links Rust .so:
```bash
clang -o caller caller.c rust_ffi.so -Wl,-rpath,...
```

Result: `rust_add(10,20)=30`, `rust_greet("HarmonyOS")="Hello from Rust, HarmonyOS!"`, FFI interop success.

**Note**: In Rust 1.95.0, `CStr::from_ptr` parameter type is `*const c_char` (u8), not `*const i8`. Need to use `std::os::raw::c_char` instead of manually writing `i8`.

### Test 6: Cargo Full Flow

```bash
cargo init --name cargo-e2e   # Create project
cargo build                   # Build success (2.43s)
binary-sign-tool sign ...     # Sign
./target/debug/cargo-e2e      # Run success
cargo test                    # 4 integration tests all pass
```

---

## 9. Known Issues and Limitations

### 9.1 cargo ohos version OpenSSL incompatibility

ohos version cargo dynamically links `libssl.so` + `libcrypto.so`, but HarmonyOS system OpenSSL libraries:
- Different naming: `libssl_openssl.z.so`, `libcrypto_openssl.z.so`
- ABI incompatible: missing `SSL_get0_group_name` etc new OpenSSL symbols
- Python bundled `libssloh.so.3`/`libcryptooh.so.3` also incompatible

**Solution**: Use musl version cargo (verified working).

### 9.2 Compiled artifacts must be signed

Every compiled Rust binary/dynamic library must be signed before running. This is HarmonyOS security mechanism requirement, not permission issue. Batch signing can be written as script.

### 9.3 git clone large repos may fail

HarmonyOS filesystem has creation limits for certain filenames (containing special characters or deeply nested directories). `git clone rust-lang/rust` (59543 files) about 70+ files creation failed (`unable to create file`), finally fatal at `tests/ui/layout/aggregate-lang` directory name. If need to compile Rust from source, use sparse checkout or other strategies.

### 9.4 No default cc linker

All Rust compilation must specify `-C linker=/data/service/hnp/bin/clang`. Recommend global config in cargo config.toml.

---

## Summary: HarmonyOS Rust Usage Checklist

1. **Download**: From `static.rust-lang.org` download ohos version rustc + rust-std, musl version cargo
2. **Install**: Manual `install.sh --prefix=$HOME/.rust`, no rustup support
3. **Sign**: All ELF (rustc, cargo, .so, compiled artifacts) must `binary-sign-tool -selfSign 1` sign
4. **Dependencies**: `LD_LIBRARY_PATH` include `.rust/lib` + `/system/lib64`; `libgcc_s.so.1` extract from Python package
5. **Linker**: cargo config.toml specify `linker = "/data/service/hnp/bin/clang"`
6. **TMPDIR**: Set `TMPDIR=$HOME/Claude/tmpdir` (/tmp read-only)
7. **Cargo**: Must use musl version (ohos version OpenSSL ABI incompatible)
8. **FFI**: Rust 1.95.0 c_char is u8 type (not i8), CStr::from_ptr use `*const c_char`