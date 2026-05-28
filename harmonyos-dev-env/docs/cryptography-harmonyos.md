# cryptography Package Adaptation Guide for HarmonyOS

This guide documents the complete adaptation process for the `cryptography` Python package (v48.0.0) on HarmonyOS, covering the dependency chain: libffi → cffi → maturin → OpenSSL dev files → cryptography.

## Overview

cryptography is a Python package providing cryptographic primitives and recipes. Since v36+, it uses Rust (PyO3) for core implementation and maturin as its build backend. The dependency chain makes it one of the most complex Python packages to adapt on HarmonyOS.

**Result**: cryptography v48.0.0 — **12/12 e2e tests passed** (AES-CBC, AES-GCM, RSA-2048, ECDSA, Ed25519, SHA/MD5 hashes, HMAC, PBKDF2, X.509, Fernet, ChaCha20-Poly1305, key serialization)

## Dependency Chain

```
cryptography (v48.0.0)
├── cffi >=2.0.0           → requires libffi (not on HarmonyOS)
├── maturin (build backend) → requires Rust toolchain + cargo
├── OpenSSL (libssl/libcrypto) → system has .so.3 but no dev headers/pkg-config
└── Rust toolchain           → aarch64-unknown-linux-ohos target
```

## Step 1: Build libffi from Source

HarmonyOS lacks libffi (no `ffi.h`, no `libffi.so`). Must compile manually without autotools (no automake/aclocal).

### 1.1 Download libffi source

```bash
cd $HOME/Claude/cryptography-build
curl -fL https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz \
  --proxy socks5://127.0.0.1:7890 \
  -o libffi-3.4.6.tar.gz
tar xzf libffi-3.4.6.tar.gz
```

### 1.2 Manual build script

Key adaptations:
- **ffi.h.in template variables**: Replace `@TARGET@` → `AARCH64`, `@HAVE_LONG_DOUBLE@` → `1`, `@FFI_EXEC_TRAMPOLINE_TABLE@` → `0` with sed
- **FFI_HIDDEN macro**: C code uses `__attribute__((visibility("hidden")))`, .S assembly files need `.hidden name` directive — requires separate include paths for C vs assembly compilation
- **memcpy→bcopy macro conflict**: `ffi_common.h` has `#define memcpy(d,s,n) bcopy((s),(d),(n))` which conflicts with HarmonyOS's bcopy signature — must remove this line

The complete build script is available at `$HOME/Claude/cryptography-build/build-libffi.sh`. Key excerpts:

```bash
# Generate ffi.h from template (no autotools)
sed -e 's/@VERSION@/3.4.6/' \
    -e 's/@TARGET@/AARCH64/' \
    -e 's/@HAVE_LONG_DOUBLE@/1/' \
    -e 's/@FFI_EXEC_TRAMPOLINE_TABLE@/0/' \
    ffi.h.in > "$INSTALL_DIR/include/ffi.h"

# Generate fficonfig.h for C compilation (with FFI_HIDDEN)
cat > "$INSTALL_DIR/include/fficonfig.h" << 'EOF'
#define AARCH64 1
#define HAVE_LONG_DOUBLE 1
#define HAVE_MMAP 1
#define FFI_HIDDEN __attribute__((visibility("hidden")))
EOF

# Create separate asm_inc/ directory WITHOUT FFI_HIDDEN (for .S compilation)
mkdir -p "$ASM_INC"
sed '/^#define FFI_HIDDEN/d' "$INSTALL_DIR/include/fficonfig.h" > "$ASM_INC/fficonfig.h"

# Remove harmful memcpy→bcopy macro from ffi_common.h
sed -i '/^#define memcpy.*bcopy/d' src/aarch64/ffi_common.h

# Compile .c files (C-style FFI_HIDDEN from fficonfig.h)
clang -I"$INSTALL_DIR/include" -c src/aarch64/ffi.c -o ffi.o

# Compile .S files (asm-style FFI_HIDDEN via -D, asm_inc first in -I)
clang -D 'FFI_HIDDEN(x)=.hidden x' \
  -I"$ASM_INC" -I"$INSTALL_DIR/include" \
  -c src/aarch64/sysv.S -o sysv.o
```

**Critical fix**: The `#include <fficonfig.h>` in sysv.S overrides command-line `-D FFI_HIDDEN`. Must place asm_inc path first in `-I` order so its FFI_HIDDEN-free fficonfig.h takes precedence.

### 1.3 Install and sign

```bash
# Link shared library
clang -shared -o "$INSTALL_DIR/lib/libffi.so.8.1.4" *.o

# Code sign
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile "$INSTALL_DIR/lib/libffi.so.8.1.4" \
  -outFile signed -signAlg SHA256withECDSA
mv signed "$INSTALL_DIR/lib/libffi.so.8.1.4"

# Create symlinks and install to ~/.local
ln -sf libffi.so.8.1.4 "$INSTALL_DIR/lib/libffi.so.8"
ln -sf libffi.so.8 "$INSTALL_DIR/lib/libffi.so"
cp -r "$INSTALL_DIR/include" $HOME/.local/include/
cp -r "$INSTALL_DIR/lib" $HOME/.local/lib/
```

## Step 2: Install cffi

```bash
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CXX=/data/service/hnp/bin/clang++ \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/.local/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L$HOME/.local/lib" \
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
pip install cffi

# Sign cffi backend .so and fix suffix
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so \
  -outFile signed -signAlg SHA256withECDSA
mv signed $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so

# Fix .so suffix (Python expects .cpython-312-aarch64-linux-gnu.so)
mv $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312.so \
   $HOME/.local/lib/python3.12/site-packages/_cffi_backend.cpython-312-aarch64-linux-gnu.so
```

## Step 3: Install maturin

maturin is cryptography's build backend. It requires Rust + cargo.

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

### 3.2 Sign maturin binary

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/maturin \
  -outFile $HOME/.local/bin/maturin.signed \
  -signAlg SHA256withECDSA
mv $HOME/.local/bin/maturin.signed $HOME/.local/bin/maturin
chmod +x $HOME/.local/bin/maturin
```

### 3.3 Fix platform.system() mismatch

**Critical issue**: maturin checks that `platform.system()` from Python matches the Rust target OS. On HarmonyOS, `platform.system()` returns `"HarmonyOS"` but the Rust target is `aarch64-unknown-linux-ohos` (OS = `"Linux"`). This mismatch causes maturin to refuse building with error: "platform.system() in python, harmonyos, and the rust target, Target { os: Linux, ... }, don't match".

**Fix**: Create a `sitecustomize.py` that patches `platform.system()`:

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

Python automatically loads `sitecustomize.py` on startup, so this patch applies globally. After this, `platform.system()` returns `"Linux"` and maturin's platform check passes.

**Note**: This is a broader workaround that affects all Python code on the system. If you need `platform.system()` to return `"HarmonyOS"` for other purposes, you may need a more targeted approach (e.g., only patching during maturin builds).

## Step 4: Set Up OpenSSL Development Files

HarmonyOS has OpenSSL runtime libraries (`/usr/lib/libssl.so.3`, `/usr/lib/libcrypto.so.3`) but no development headers or pkg-config files. cryptography's Rust build (`openssl-sys` crate) requires these.

### 4.1 Download OpenSSL headers

Download OpenSSL 3.0 source (matching system version) and copy headers:

```bash
cd $HOME/Claude/cryptography-build
curl -fL https://github.com/openssl/openssl/releases/download/openssl-3.0.16/openssl-3.0.16.tar.gz \
  --proxy socks5://127.0.0.1:7890 \
  -o openssl-3.0.16.tar.gz
tar xzf openssl-3.0.16.tar.gz

# Copy headers to ~/.local/include/openssl/
mkdir -p $HOME/.local/include/openssl
cp -r openssl-3.0.16/include/openssl/*.h $HOME/.local/include/openssl/
```

### 4.2 Create pkg-config files

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

### 4.3 Create unversioned symlinks for linker

```bash
# ld.bfd requires unversioned .so for linking
ln -sf /usr/lib/libssl.so.3 $HOME/.local/lib/libssl.so
ln -sf /usr/lib/libcrypto.so.3 $HOME/.local/lib/libcrypto.so
```

## Step 5: Build cryptography with --no-build-isolation

pip's build isolation creates a fresh environment that doesn't inherit RUSTFLAGS/CC/LD_LIBRARY_PATH. Use `--no-build-isolation` with all required environment variables:

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

**Key additions for cryptography vs other Rust extensions**:
- `LDFLAGS="-L/usr/lib -L$HOME/.local/lib"` — linker must find libssl/libcrypto
- `RUSTFLAGS="-C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib"` — cargo linker search paths
- `PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig"` — openssl-sys finds OpenSSL via pkg-config

## Step 6: Sign cryptography .so extension

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/python3.12/site-packages/cryptography/hazmat/bindings/_rust.abi3.so \
  -outFile signed -signAlg SHA256withECDSA
mv signed $HOME/.local/lib/python3.12/site-packages/cryptography/hazmat/bindings/_rust.abi3.so
```

## Step 7: Verify

```bash
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64" \
python3 -c "import cryptography; print(cryptography.__version__)"
# Output: 48.0.0
```

## End-to-End Test Results

12/12 tests passed:

| Test | Description | Result |
|------|-------------|--------|
| AES-256-CBC | Symmetric encrypt/decrypt with padding | PASS |
| AES-256-GCM | Authenticated encryption with tag verification | PASS |
| RSA-2048 | Keygen, sign/verify (PSS), encrypt/decrypt (OAEP), PEM/DER serialization | PASS |
| EC SECP256R1 | Keygen, ECDH key exchange, ECDSA sign/verify | PASS |
| Ed25519 | Sign/verify | PASS |
| SHA256/384/512 | Hash digests | PASS |
| SHA3_256 | SHA-3 hash | PASS |
| MD5 | Legacy hash (OpenSSL legacy provider warning) | PASS |
| HMAC-SHA256 | Message authentication | PASS |
| PBKDF2-SHA256 | Key derivation | PASS |
| X.509 | Certificate create, sign, parse | PASS |
| Fernet | High-level symmetric encryption with TTL | PASS |
| ChaCha20-Poly1305 | AEAD encryption | PASS |
| Key serialization | PEM/DER private/public key roundtrip | PASS |

## HarmonyOS-Specific Adaptation Summary

| Issue | Standard Linux | HarmonyOS | Fix |
|-------|---------------|-----------|-----|
| libffi | System package (`apt install libffi-dev`) | Not available | Manual build from source without autotools |
| FFI_HIDDEN macro | autotools generates correct config | C vs .S compilation difference | Separate asm_inc with FFI_HIDDEN-free fficonfig.h |
| memcpy→bcopy macro | Works (glibc bcopy compatible) | Conflicts with HarmonyOS bcopy | Remove macro via sed |
| maturin platform check | `platform.system()` = `"Linux"` matches Rust target | Returns `"HarmonyOS"`, mismatches `"Linux"` | sitecustomize.py patches platform.system() |
| pip build isolation | Works (inherits env vars) | Doesn't inherit RUSTFLAGS/CC | Use `--no-build-isolation` |
| OpenSSL dev files | System package (`apt install libssl-dev`) | Only runtime .so.3, no headers/pkg-config | Download headers + create pkg-config files + unversioned symlinks |
| Linker lib search | ld searches standard paths | cargo doesn't pass `-L/usr/lib` | Add `-C link-args=-L/usr/lib` to RUSTFLAGS |
| .so signing | Not required | Mandatory for execution | `binary-sign-tool sign -selfSign 1` |
| .so suffix | `.cpython-312.so` works | Needs `.cpython-312-aarch64-linux-gnu.so` | Rename after install |

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `don't match ಠ_ಠ` (maturin) | platform.system() returns "HarmonyOS" vs Rust target "Linux" | sitecustomize.py patch |
| `Package openssl was not found` (pkg-config) | No openssl.pc on system | Create pkg-config files in $HOME/.local/lib/pkgconfig |
| `ld.lld: error: unable to find library -lssl` | Linker can't find libssl.so | Add `-C link-args=-L/usr/lib` to RUSTFLAGS + create unversioned symlinks |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so suffix mismatch or not signed | Rename to `.cpython-312-aarch64-linux-gnu.so` + sign |
| `FFI_HIDDEN` undefined in .S files | C-style macro doesn't work in assembly | Separate asm_inc/ with FFI_HIDDEN removed + `-D 'FFI_HIDDEN(x)=.hidden x'` |
| `failed to run build_openssl.py` (cryptography-cffi) | cffi backend .so not loaded | Sign + rename _cffi_backend .so |