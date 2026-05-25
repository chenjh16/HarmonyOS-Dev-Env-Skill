# Rust 1.95.0 on HarmonyOS - Complete Build Guide

> **中文版本请查看 build.cn.md**

## Overview

Rust officially supports HarmonyOS target `aarch64-unknown-linux-ohos` since version 1.95.0. This guide documents how to install the Rust toolchain manually (rustup doesn't support HarmonyOS yet).

**Key points**:
- Use **musl version** of cargo (ohos version has OpenSSL ABI issues)
- All ELF binaries must be code-signed
- Must configure linker path (HarmonyOS has no default `cc`)

## Prerequisites

- HarmonyOS SDK with clang 15.0.4
- `libgcc_s.so.1` (extracted from Python cryptography package)
- About 500MB disk space for toolchain

## Source Download

Rust toolchain is distributed via `static.rust-lang.org`. Download components manually:

```bash
mkdir -p ~/Claude/rust-build/rust-dist
cd ~/Claude/rust-build/rust-dist

# Check current version
curl -sL https://static.rust-lang.org/dist/channel-rust-stable.toml | grep "aarch64-unknown-linux-ohos"

# Download components (example for 2026-04-16)
BASE="https://static.rust-lang.org/dist/2026-04-16"

# rustc (ohos version)
curl -L "$BASE/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rustc.tar.gz

# rust-std (ohos version - standard library for target)
curl -L "$BASE/rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz" -o rust-std.tar.gz

# cargo (MUSL version - NOT ohos version!)
curl -L "$BASE/cargo-1.95.0-aarch64-unknown-linux-musl.tar.gz" -o cargo.tar.gz
```

**Important**: Use `aarch64-unknown-linux-musl` cargo, not `aarch64-unknown-linux-ohos` cargo. The ohos cargo dynamically links OpenSSL but HarmonyOS OpenSSL uses different naming (`libssl_openssl.z.so`) and ABI.

## Installation Steps

### Step 1: Extract components

```bash
cd ~/Claude/rust-build/rust-dist

tar xzf rustc.tar.gz
tar xzf rust-std.tar.gz
tar xzf cargo.tar.gz
```

### Step 2: Install using install.sh

```bash
INSTALL_DIR="$HOME/.rust"

./rustc-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./rust-std-1.95.0-aarch64-unknown-linux-ohos/install.sh --prefix="$INSTALL_DIR" --destdir=""
./cargo-1.95.0-aarch64-unknown-linux-musl/install.sh --prefix="$INSTALL_DIR" --destdir=""
```

### Step 3: Code signing

All ELF binaries must be signed:

```bash
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
RUST_DIR="$HOME/.rust"

# Sign rustc
$SIGN_TOOL sign -selfSign 1 \
    -inFile $RUST_DIR/bin/rustc \
    -outFile $RUST_DIR/bin/rustc.signed \
    -signAlg SHA256withECDSA
mv $RUST_DIR/bin/rustc.signed $RUST_DIR/bin/rustc
chmod +x $RUST_DIR/bin/rustc

# Sign cargo
$SIGN_TOOL sign -selfSign 1 \
    -inFile $RUST_DIR/bin/cargo \
    -outFile $RUST_DIR/bin/cargo.signed \
    -signAlg SHA256withECDSA
mv $RUST_DIR/bin/cargo.signed $RUST_DIR/bin/cargo
chmod +x $RUST_DIR/bin/cargo

# Sign all .so files in lib/
for f in $RUST_DIR/lib/*.so; do
    $SIGN_TOOL sign -selfSign 1 \
        -inFile "$f" \
        -outFile "${f}.signed" \
        -signAlg SHA256withECDSA
    mv "${f}.signed" "$f"
done

# Sign rustlib bin tools
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

### Step 4: Extract and install libgcc_s.so.1

Cargo (musl version) requires `libgcc_s.so.1`:

```bash
# Extract from Python cryptography package
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/cryptography.libs/libgcc_s-c8ae3477.so.1 \
   $HOME/.rust/lib/libgcc_s.so.1

# Sign it
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile $HOME/.rust/lib/libgcc_s.so.1 \
    -outFile $HOME/.rust/lib/libgcc_s.so.1.signed \
    -signAlg SHA256withECDSA
mv $HOME/.rust/lib/libgcc_s.so.1.signed $HOME/.rust/lib/libgcc_s.so.1
```

### Step 5: Configure linker

HarmonyOS has no default `cc` linker. Create cargo config:

```bash
mkdir -p $HOME/.rust/.cargo

cat > $HOME/.rust/.cargo/config.toml << 'EOF'
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
EOF
```

### Step 6: Configure shell environment

Add to `~/.zshenv`:

```bash
# Rust toolchain
export RUST_HOME="$HOME/.rust"
export PATH="$RUST_HOME/bin:$PATH"
export LD_LIBRARY_PATH="/usr/lib:$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH"
export CARGO_HOME="$RUST_HOME"
export RUSTUP_HOME="$RUST_HOME"
```

## Verification

```bash
# Check versions
rustc --version
# rustc 1.95.0 (59807616e 2026-04-14)

cargo --version  
# cargo 1.95.0 (f2d3ce0bd 2026-03-21)

# Test compilation
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

## Dependency Chain

### rustc dependencies

```
rustc (wrapper)
  → librustc_driver-*.so (277MB, Rust compiler core)
      → libc++_shared.so (system: /system/lib64/libc++_shared.so)
      → libc.so (musl)
```

### cargo (musl) dependencies

```
cargo (musl version)
  → libgcc_s.so.1 (extracted from Python package)
  → libc.so (musl)
```

## End-to-End Tests

### Test 1: Hello World

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

### Test 2: Cargo project

```bash
cargo init --name test-project
cd test-project
cargo build
binary-sign-tool sign -selfSign 1 -inFile target/debug/test-project -outFile target/debug/test-project.s
mv target/debug/test-project.s target/debug/test-project
./target/debug/test-project
cargo test  # All tests should pass
```

### Test 3: FFI with C

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

Compile C caller and link:
```bash
clang -o caller caller.c rust_ffi.so -Wl,-rpath,.
binary-sign-tool sign -selfSign 1 -inFile caller -outFile caller_s
mv caller_s caller && ./caller
```

## Known Issues

### 1. cargo ohos version OpenSSL incompatibility

- Ohos cargo links `libssl.so` + `libcrypto.so`
- HarmonyOS uses `libssl_openssl.z.so` naming
- ABI mismatch (missing `SSL_get0_group_name`)

**Solution**: Use musl cargo

### 2. git clone large repos

Some file names/paths fail to create on HarmonyOS filesystem. Use sparse checkout for large repos like rust-lang/rust.

### 3. Compiled binaries need signing

Every build output must be signed before execution. Consider adding signing step to build scripts.

## Platform Target

The official target is `aarch64-unknown-linux-ohos`:

- Architecture: `aarch64` (ARM64)
- Vendor: `unknown`
- OS: `linux-ohos` (HarmonyOS Linux-like environment)

Also available: `armv7-unknown-linux-ohos`, `x86_64-unknown-linux-ohos`, `loongarch64-unknown-linux-ohos`

## SSL Certificates for Cargo

```bash
# Download CA certificates for crates.io access
curl -L https://curl.se/ca/cacert.pem -o $HOME/.rust/cacert.pem

# Set environment variable
export SSL_CERT_FILE="$HOME/.rust/cacert.pem"
```