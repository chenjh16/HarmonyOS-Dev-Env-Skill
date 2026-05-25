# Code Signing Guide for HarmonyOS

## Overview

HarmonyOS requires all ELF binaries (executables and shared libraries) to be signed before execution. This is a security mechanism unique to HarmonyOS, not a permission issue.

Unsigned binaries will fail with:
```
zsh: permission denied: ./binary
```
Exit code: 126

## Signing Tools

### ELF Binary Signing: `binary-sign-tool`

Location: `/data/service/hnp/bin/binary-sign-tool`

Commands:
- `sign` — Sign an ELF binary
- `display-sign` — Display signature information

Supported algorithms:
- `SHA256withECDSA`
- `SHA384withECDSA`

### HAP/App Signing: `hap-sign-tool`

Location: `/data/service/hnp/bin/hap-sign-tool`

Commands:
- `generate-keypair` — Generate key pair
- `generate-csr` — Generate certificate signing request
- `generate-cert` — Generate certificate
- `generate-ca` — Generate CA certificate
- `generate-app-cert` — Generate app certificate
- `generate-profile-cert` — Generate profile certificate
- `sign-profile` — Sign profile file
- `verify-profile` — Verify profile signature
- `sign-app` — Sign HAP/app package
- `verify-app` — Verify app signature

Key algorithm: ECC (NIST-P-256 / NIST-P-384)

## Signing Methods

### Self-Signing (Local Testing)

For local testing and development, use self-signing:

```bash
/data/service/hnp/bin/binary-sign-tool sign \
  -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

### Production Signing (Requires Certificates)

For production deployment, use proper certificates:

```bash
/data/service/hnp/bin/binary-sign-tool sign \
  -keyAlias "your-key-alias" \
  -appCertFile cert.cer \
  -profileFile profile.p7b \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -keystoreFile keystore.p12 \
  -signAlg SHA256withECDSA
```

Required parameters:
- `-keyAlias`: Key alias in keystore
- `-appCertFile`: Application certificate file
- `-profileFile`: Profile file (p7b format)
- `-inFile`: Input unsigned binary
- `-outFile`: Output signed binary
- `-keystoreFile`: Keystore file (p12 format)
- `-signAlg`: Signature algorithm

## What Needs Signing

### Executables

All compiled executables must be signed:
- Python interpreter (`python3`)
- Rust compiler outputs (`rustc` compiled programs)
- Go compiled programs
- llama.cpp binaries (`llama-cli`, `llama-server`)
- mihomo proxy binary
- Dropbear SSH binaries
- Any other ELF executable

### Shared Libraries (.so files)

All shared libraries that will be dynamically loaded must be signed:
- Python extension modules (`.cpython-312-aarch64-linux-gnu.so`)
- Rust dynamic libraries (`*.so`)
- Native libraries for applications

### What Doesn't Need Signing

- Shell scripts (`.sh`)
- Python scripts (`.py`)
- Text files
- Configuration files
- Data files
- Static libraries (`.a` files — only linked, not loaded)

## Batch Signing Script

Use `scripts/sign-all.sh` to sign all binaries in a directory:

```bash
#!/bin/sh
# Batch sign all ELF binaries in a directory

DIR="${1:-.}"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

for f in "$DIR"/*; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        echo "Signing: $f"
        # Remove existing signature section
        /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned" 2>/dev/null || cp "$f" "${f}.unsigned"
        
        # Sign the binary
        "$SIGN_TOOL" sign -selfSign 1 \
            -inFile "${f}.unsigned" \
            -outFile "${f}.signed" \
            -signAlg SHA256withECDSA
        
        # Replace original
        mv "${f}.signed" "$f"
        rm -f "${f}.unsigned"
        chmod +x "$f"
    fi
done

echo "Done signing all binaries in $DIR"
```

## Verifying Signature

To check if a binary is signed:

```bash
/data/service/hnp/bin/binary-sign-tool display-sign -inFile <binary>
```

If signed, will show signature details. If unsigned, will report error.

## Common Issues

### "permission denied" after signing

1. Check if signing was successful (display-sign)
2. Ensure execute permission: `chmod +x <binary>`
3. Verify file ownership is correct

### Signature already exists

Remove old signature before re-signing:

```bash
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign <binary> <binary>.unsigned
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile <binary>.unsigned -outFile <binary>.signed
mv <binary>.signed <binary>
```

### Signing fails with error

1. Check binary is valid ELF: `file <binary>`
2. Ensure binary is not corrupted
3. Verify sign tool has correct permissions

## Integration with Build Processes

### Python Extension Build

After pip install for C extensions:

```bash
cd ~/.local/lib/python3.12/site-packages/<package>
for f in *.cpython-312-aarch64-linux-gnu.so; do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned"
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "${f}.unsigned" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
done
```

### Rust Cargo Build

After `cargo build`:

```bash
for f in target/debug/* target/release/*.so; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.s"
        mv "${f}.s" "$f"
    fi
done
```

### C/C++ Build

After `make` or `cmake`:

```bash
for f in <output-dir>/*; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned"
        /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "${f}.unsigned" -outFile "$f"
        rm "${f}.unsigned"
    fi
done
```

## Security Considerations

Self-signed binaries (`-selfSign 1`) are suitable for:
- Local development and testing
- Personal projects
- Internal tools

For production or distributed applications:
- Use proper certificates from authorized CA
- Follow HarmonyOS app signing guidelines
- Store keystore securely