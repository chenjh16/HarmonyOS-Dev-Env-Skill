# HarmonyOS Compiled .so Loading Issue - Deep Analysis

> **Chinese version**: selinux-analysis.cn.md

## Problem Summary

**Symptom**: Compiled Python extension modules (.so files) cannot be loaded from user paths, returning "Permission denied" error.

**Scope**: Affects numpy, pandas, pillow, and all packages with compiled extensions installed via pip.

## Root Cause Analysis

### 1. SELinux Path-Based Policy

**Key Finding**: The issue is **NOT** code signing, but **SELinux path-based security policy**.

| Path | File System | SELinux Label | .so Loading |
|------|-------------|---------------|-------------|
| `/data/service/hnp/` | hmfs | `u:object_r:hnp_file:s0` | ✓ Works |
| `/system/lib64/` | system | System labels | ✓ Works |
| `/storage/Users/currentUser/` | hmdfs | `u:object_r:hmdfs:s0` | ✗ Denied |
| `/data/storage/el2/base/haps/` | hmfs | `u:object_r:hishell_hap_data_file:s0` | ✗ Denied |
| `/data/local/tmp/` | hmfs | `u:object_r:data_local_tmp:s0` | ✗ Denied (no write access) |

**Proof**: Same system .so file (`_bisect.cpython-312.so`) loads successfully from `/data/service/hnp/` but fails when copied to user path.

### 2. Security Context

Process context: `u:r:hishell_hap:s0`

SELinux status:
- Enforce mode: 0 (permissive? No, still blocking)
- deny_unknown: 1 (rejects unknown permissions)
- Seccomp: 2 (strict mode enabled)

### 3. What Works vs What Doesn't

**Working**:
- mmap with PROT_EXEC ✓
- Reading .so files ✓
- File read/write/execute permissions ✓
- System Python extensions ✓
- Pure Python packages ✓

**Not Working**:
- dlopen() from user paths ✗
- Loading .so even with correct file permissions ✗
- SELinux label modification (setfattr fails) ✗
- Code signing (doesn't help) ✗

### 4. Technical Details

```
# Comparison
System .so:
  Path: /data/service/hnp/python.org/python_3.12/lib/python3.12/lib-dynload/_ssl.cpython-312.so
  SELinux: u:object_r:hnp_file:s0
  Code sign: NOT FOUND
  Load: SUCCESS

User .so:
  Path: /storage/Users/currentUser/Claude/venv/lib/python3.12/site-packages/numpy/_core/_multiarray_umath.cpython-312.so
  SELinux: u:object_r:hmdfs:s0
  Code sign: self-sign (added manually)
  Load: PERMISSION DENIED
```

## Why Our Python Build Works

Our locally compiled Python (see [python-harmonyos.md](python-harmonyos.md)) uses `-rdynamic` to export 1517 Python symbols, allowing extension modules compiled with `-DPy_BUILD_CORE_MODULE` to resolve symbols without needing `libpython.so`.

However, **this only works for extensions in system paths**. User-compiled extensions still face SELinux blocking.

## Possible Solutions

### Option 1: Install to System Path (Requires Root)

If we could write to `/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/`, compiled extensions would work.

**Problem**: No write access to system paths.

### Option 2: Modify SELinux Policy (Requires Root)

Create a custom SELinux policy module to allow `hishell_hap` domain to execute files from user paths.

```c
// Example policy (would need to be compiled and loaded)
allow hishell_hap hishell_hap_data_file:file { execute execmod map };
allow hishell_hap hmdfs:file { execute execmod map };
```

**Problem**: Requires root access and SELinux policy compilation tools (not available).

### Option 3: HAP Packaging

Package Python + extensions as a proper HarmonyOS HAP (HarmonyOS Ability Package). A properly signed HAP would have appropriate permissions.

**Pros**:
- Official way to distribute apps on HarmonyOS
- Proper code signing and permissions
- Could enable loading of compiled extensions

**Cons**:
- Complex build process
- Requires DevEco Studio
- Would need to bundle entire Python + packages
- Not suitable for CLI development

### Option 4: Pure Python Alternatives

Accept the limitation and use pure Python alternatives:

| Blocked Package | Pure Python Alternative |
|-----------------|------------------------|
| numpy | Use cloud Jupyter, or write pure Python algorithms |
| pandas | Use csv module + pure Python |
| pillow | Use pure Python image libs (limited) |
| matplotlib | Use plotly (mostly pure Python) |
| scipy | Use cloud computing |

### Option 5: Remote Python Server

Run Python with compiled extensions on a remote server, communicate via HTTP/WebSocket.

**Pros**:
- Full Python functionality on server
- Local machine handles UI/interface

**Cons**:
- Requires network connection
- Not suitable for offline work

## Conclusion

The loading of compiled .so files from user paths is **blocked by HarmonyOS SELinux policy**, specifically:
1. Path-based label assignment (hmdfs vs hnp_file)
2. Domain restriction (hishell_hap cannot execute from user paths)
3. This is a **platform-level security decision**, not a bug

**Most Practical Solution**: Use pure Python packages locally, use cloud services for data science/ML work.

**Potential Future Solution**: If HarmonyOS provides developer mode or allows custom SELinux policies, compiled extensions could be enabled.

## Test Commands

```bash
# Check SELinux context
cat /proc/self/attr/current

# Check file label
getfattr -d <file> | grep selinux

# Check loaded libraries
cat /proc/self/maps | grep ".so"

# Compare system vs user .so loading
python3 -c "import ctypes; ctypes.CDLL('/data/service/hnp/...')"  # Works
python3 -c "import ctypes; ctypes.CDLL('/storage/Users/...')"     # Fails
```

---

*Analysis Date: 2026-05-12*
*Platform: HarmonyOS HongMeng Kernel 1.12.0*