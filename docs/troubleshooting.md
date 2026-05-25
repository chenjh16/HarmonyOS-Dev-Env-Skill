# HarmonyOS Development Troubleshooting Guide

> **Chinese version**: troubleshooting.cn.md

This guide consolidates common issues and solutions for HarmonyOS development.

## Quick Reference

| Issue | Quick Fix | Full Guide |
|-------|-----------|------------|
| `/tmp` read-only | `export TMPDIR=$HOME/Claude/tmpdir` | [Filesystem](#filesystem-issues) |
| Code signing | Use `binary-sign-tool` | [Code Signing](#code-signing) |
| LD_LIBRARY_PATH conflict | `/usr/lib` first in path | [Library Path](#library-path) |
| SDK linker broken | Use ld.bfd wrapper | [Linker](#linker-issues) |
| V8 JIT crash in SSH | `node --jitless` | [SSH V8 Crash](#ssh-v8-crash) |
| Python extension fails | Compile locally with `-rdynamic` | [Python Extensions](#python-extensions) |
| .so loading denied | Sign .so + use `-rdynamic` Python | [SELinux](#selinux-blocking) |
| TLS certificate error | `NODE_TLS_REJECT_UNAUTHORIZED=0` | [TLS Issues](#tls-certificate) |

---

## Filesystem Issues

### Problem: /tmp is Read-Only

**Symptom**:
```
Error: EROFS: read-only file system, open '/tmp/...'
```

**Solution**:
```bash
export TMPDIR=$HOME/Claude/tmpdir
mkdir -p $TMPDIR
```

For permanent fix, add to `~/.zshenv`:
```bash
export TMPDIR=$HOME/Claude/tmpdir
```

---

## Code Signing

### Problem: Binary Won't Execute

**Symptom**:
```
$ ./my-binary
./my-binary: Permission denied
```

**Cause**: All ELF binaries must be signed on HarmonyOS.

**Solution**:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ./my-binary \
  -outFile ./my-binary-signed \
  -signAlg SHA256withECDSA

mv ./my-binary-signed ./my-binary
```

For batch signing:
```bash
./scripts/sign-all.sh <directory>
```

**Full Guide**: [code-signing.md](code-signing.md)

---

## Library Path

### Problem: OpenSSL Symbol Version Conflict

**Symptom**:
```
ImportError: /storage/Users/.../lib/python3.12/site-packages/...so: 
undefined symbol: EVP_MD_CTX_pkey_ctx, version OPENSSL_3.0.0
```

**Cause**: Wrong LD_LIBRARY_PATH order. Rust's libssl conflicts with system OpenSSL.

**Solution**:
```bash
# CRITICAL: /usr/lib MUST come first
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

**Full Guide**: [ld-library-path.md](ld-library-path.md)

---

## Linker Issues

### Problem: SDK lld Requires Missing libxml2.so.16

**Symptom**:
```
ld.lld: error: cannot find libxml2.so.16
```

**Cause**: SDK's lld is broken on HarmonyOS.

**Solution**: Create ld.bfd wrapper:
```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

Then add `-B$HOME/Claude/lib/linker_wrapper` to clang commands:
```bash
clang -B$HOME/Claude/lib/linker_wrapper ...
```

**Full Guide**: [CLAUDE.md](../rules/CLAUDE.md)

---

## SSH V8 Crash

### Problem: Node.js Crashes in SSH Sessions

**Symptom**:
```
# Fatal error in , line 0
# Check failed: 12 == (*__errno_location()).
```

**Cause**: V8 JIT crashes in SSH PTY environment.

**Solution 1**: Use `--jitless` mode:
```bash
node --jitless your-app.js
```

**Solution 2**: Use node-fetch polyfill:
```bash
node --jitless --require ~/.claude/ssh-fetch-polyfill.js your-app.js
```

**Full Guide**: [dropbear-harmonyos.md](dropbear-harmonyos.md)

---

## Python Extensions

### Problem: Extension Module Permission Denied

**Symptom**:
```
ImportError: dlopen() failed: Permission denied
```

**Cause 1**: Extension not code-signed.
**Cause 2**: Python not compiled with `-rdynamic`.

**Solution**: 
1. Sign the .so file:
```bash
binary-sign-tool sign -selfSign 1 -inFile module.so -outFile module-signed.so -signAlg SHA256withECDSA
```

2. Ensure Python compiled with `-rdynamic` (exports 948+ Py symbols, 1521 total):
```bash
python3 -c "import ctypes; print(len([s for s in dir(ctypes.pythonapi) if not s.startswith('_')]))"
```

**Full Guide**: [python-harmonyos.md](python-harmonyos.md)

---

## SELinux Blocking

### Problem: User Path .so Loading Denied

**Symptom**:
```
ImportError: cannot load numpy: Permission denied
```

**Cause**: SELinux path-based policy blocks user paths (`hmdfs` label).

**What Works**:
- System path .so files (`/data/service/hnp/`)
- Pure Python packages
- Locally compiled Python with `-rdynamic`
- **Signed .so extension modules from `$HOME/.local/lib/`** (34/34 packages tested, all working — see [python-packages-harmonyos.md](python-packages-harmonyos.md))
- PyTorch, numpy, pillow, lxml, bcrypt, greenlet and other compiled extensions from user-installed paths

**What May Have Issues**:
- .so files from arbitrary `/storage/Users/currentUser/` subpaths (not installed via pip to `$HOME/.local/`)
- .so files without code signing
- .so files loaded by Python without `-rdynamic` symbol exports

> **Note**: With code signing + `-rdynamic` Python (948+ Py symbols exported), extension modules from user paths like `$HOME/.local/lib/python3.12/site-packages/` load correctly. The original SELinux restriction is effectively bypassed for this use case. See [selinux-analysis.md](selinux-analysis.md) for details.

**Solution Options**:
1. Install packages to `$HOME/.local/` (pip default) and ensure code signing
2. Use `-rdynamic` Python build for extension module compatibility
3. Use pure Python alternatives if signing is not feasible

**Full Guide**: [selinux-analysis.md](selinux-analysis.md)

---

## TLS Certificate

### Problem: HTTPS Requests Fail

**Symptom**:
```
Error: unable to verify the first certificate
```

**Cause**: System CA certificates incomplete.

**Solution (Development Only)**:
```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**For Rust/cargo**:
```bash
export SSL_CERT_FILE=$HOME/.rust/cacert.pem
```

---

## No GCC

### Problem: Makefile Defaults to GCC

**Symptom**:
```
make: gcc: Command not found
```

**Cause**: HarmonyOS only has clang.

**Solution**:
```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
```

For CMake:
```cmake
set(CMAKE_C_COMPILER /data/service/hnp/bin/clang)
set(CMAKE_CXX_COMPILER /data/service/hnp/bin/clang++)
```

---

## Python pip Issues

### Problem: pip Install C Extension Fails

**Symptom**:
```
Building wheel for package: error
```

**Solution**:
```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
pip install <package>
```

**Problem**: pip Network Timeout

**Solution**:
```bash
# Use mirror
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# Or use proxy
export HTTP_PROXY=http://127.0.0.1:7890
pip install <package>
```

**Full Guide**: [python-packages-harmonyos.md](python-packages-harmonyos.md)

---

## Claude Code Issues

### Problem: ripgrep Permission Denied

**Symptom**:
```
grep: Permission denied for /storage/.../rg
```

**Solution**: 
1. Enable "Run extensions from non-AppGallery sources" in Settings
2. Re-sign ripgrep:
```bash
binary-sign-tool sign -selfSign 1 -inFile rg -outFile rg-signed -signAlg SHA256withECDSA
```

**Full Guide**: [claude-code-harmonyos.md](claude-code-harmonyos.md)

---

## PyTorch Issues

### Problem: PyTorch ImportError

**Symptom**:
```
ImportError: libtorch_cpu.so: cannot open shared object file
```

**Solution**:
```bash
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH
```

**Full Guide**: [pytorch-harmonyos.md](pytorch-harmonyos.md)

---

## llama.cpp Issues

### Problem: Model Loading Slow

**Solution**: Enable NEON/SVE optimizations:
```bash
llama-cli -m model.gguf -p "prompt" -ngl 0 -sm seed
```

**Problem**: CoT Model Doesn't Reason

**Solution**: Add reasoning budget:
```bash
llama-cli -m qwen3.5-9b.gguf --reasoning-budget 8192 -p "problem"
```

**Full Guide**: [llama-cpp-harmonyos.md](llama-cpp-harmonyos.md)

---

## Diagnostic Commands

```bash
# Check SELinux context
cat /proc/self/attr/current

# Check file SELinux label
ls -Z <file>

# Check loaded libraries
cat /proc/self/maps | grep ".so"

# Check Python symbol exports
nm -D $HOME/.local/bin/python3 | grep Py | wc -l

# Check code signature
binary-sign-tool display-sign -inFile <binary>

# Check LD_LIBRARY_PATH
echo $LD_LIBRARY_PATH

# Check temp directory
echo $TMPDIR
```

---

*Last Updated: 2026-05-20*