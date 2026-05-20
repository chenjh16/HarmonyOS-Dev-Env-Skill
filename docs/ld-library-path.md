# LD_LIBRARY_PATH Configuration Guide

## Critical Issue: OpenSSL Symbol Version Conflict

On HarmonyOS, the order of directories in `LD_LIBRARY_PATH` is critical due to OpenSSL symbol version conflicts.

### The Problem

If `$HOME/.rust/lib` comes before `/usr/lib` in `LD_LIBRARY_PATH`, you will encounter OpenSSL symbol version errors:

```
Error: version `OPENSSL_3.0.0' not found
Error relocating: SSL_get0_group_name: symbol not found
```

### Root Cause

1. HarmonyOS system OpenSSL uses non-standard naming: `libssl_openssl.z.so`, `libcrypto_openssl.z.so`
2. These libraries are located in `/usr/lib/`
3. Rust toolchain includes its own OpenSSL libraries in `$HOME/.rust/lib`
4. The Rust OpenSSL has different symbol versions than system OpenSSL
5. When Rust OpenSSL is found first, programs expecting system OpenSSL symbols fail

### Correct Order

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$LD_LIBRARY_PATH
```

**`/usr/lib` MUST come first!**

## Full LD_LIBRARY_PATH Configuration

Recommended configuration for HarmonyOS development:

```bash
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin:$LD_LIBRARY_PATH
```

Breakdown:
- `/usr/lib` — System OpenSSL libraries (MUST BE FIRST)
- `$HOME/.rust/lib` — Rust toolchain libraries
- `$HOME/.local/lib` — User-compiled libraries (libxml2, libxslt, libjpeg, etc.)
- `/system/lib64` — System C++ runtime, libc, etc.
- `$HOME/Claude/llama.cpp/build/bin` — llama.cpp OpenMP library

## Configuration in Shell

Add to `~/.zshenv`:

```bash
# LD_LIBRARY_PATH - order matters!
# /usr/lib MUST be first to avoid OpenSSL symbol version conflicts
export LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin
```

## Verification

Check current LD_LIBRARY_PATH:

```bash
echo $LD_LIBRARY_PATH
```

Should output:
```
/usr/lib:/storage/Users/currentUser/.rust/lib:/storage/Users/currentUser/.local/lib:/system/lib64:/storage/Users/currentUser/Claude/llama.cpp/build/bin
```

Verify OpenSSL library resolution:

```bash
ldd /data/service/hnp/bin/clang | grep ssl
# Should NOT show Rust's libssl
```

## Library Loading Debug

To debug library loading issues:

```bash
# Check which library is loaded
LD_DEBUG=libs ./your-program 2>&1 | grep ssl

# Check library search path
LD_DEBUG=files ./your-program 2>&1 | head -50
```

## Common Issues

### OpenSSL symbol not found

**Symptom**:
```
Error relocating: SSL_get0_group_name: symbol not found
```

**Solution**: Ensure `/usr/lib` is first in LD_LIBRARY_PATH.

### Python extension won't load

**Symptom**:
```
ImportError: dynamic module does not define init function
```

**Solution**: 
1. Check LD_LIBRARY_PATH includes `$HOME/.local/lib`
2. Ensure extension module is signed

### Rust program crashes on startup

**Symptom**:
```
zsh: trace trap (core dumped) ./rust-program
```

**Solution**:
1. Check LD_LIBRARY_PATH includes `/system/lib64` for C++ runtime
2. Ensure program is signed

### llama-cli fails to start

**Symptom**:
```
Error loading shared library libomp.so
```

**Solution**: Add llama.cpp bin directory to LD_LIBRARY_PATH.

## Per-Application Override

If an application needs a specific library order, you can temporarily override:

```bash
LD_LIBRARY_PATH=/special/order ./special-app
```

Or use `ld.so.conf` style configuration (not recommended for HarmonyOS).

## Best Practices

1. **Always put `/usr/lib` first** — Prevents OpenSSL conflicts
2. **Use absolute paths** — Avoid variable expansion issues
3. **Keep configuration in `.zshenv`** — Auto-loads on shell start
4. **Don't duplicate entries** — Waste of search time
5. **Test after changes** — Run programs to verify configuration works