# HarmonyOS Compiled .so Loading Issue - Deep Analysis

> **Chinese version**: selinux-analysis.cn.md

## Problem Summary

**Symptom**: Compiled Python extension modules (.so files) cannot be loaded from user paths, returning "Permission denied" error.

**Scope**: Originally affected numpy, pandas, pillow, and all packages with compiled extensions installed via pip.

> **UPDATE (2026-05-22)**: This issue has been **fully resolved**. Our locally compiled Python with `-rdynamic` exports 948+ Py symbols (1521 total), and **all signed .so extension modules now load successfully from user paths**. 34/34 tested packages (including numpy, pillow, lxml, bcrypt, greenlet) work correctly. See [python-packages-harmonyos.md](python-packages-harmonyos.md) for the full compatibility report.

## Root Cause Analysis

### 1. SELinux Path-Based Policy

**Key Finding**: The issue is **NOT** code signing, but **SELinux path-based security policy**.

| Path | File System | SELinux Label | .so Loading |
|------|-------------|---------------|-------------|
| `/data/service/hnp/` | hmfs | `u:object_r:hnp_file:s0` | ✓ Works |
| `/system/lib64/` | system | System labels | ✓ Works |
| `$HOME` (example: `/storage/Users/<user>/`) | hmdfs | `u:object_r:hmdfs:s0` | ✗ Denied |
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
- **Signed .so extension modules from `$HOME/.local/lib/`** ✓ (resolved via code signing + `-rdynamic` Python)
- **pip-installed packages with compiled extensions** ✓ (34/34 tested, all working from `$HOME/.local/lib/python3.12/site-packages/`)

**Historical Issues (Resolved)**:
The following items previously did not work but have been **resolved** via `-rdynamic` Python + code signing:

| Historical Issue | Resolution | Date |
|-----------------|------------|------|
| dlopen() from user paths | Works with signed .so + `-rdynamic` Python | 2026-05-22 |
| Loading .so even with correct file permissions | Works after code signing | 2026-05-22 |
| Code signing doesn't help (original assessment) | Code signing IS required; combined with `-rdynamic` it resolves the issue | 2026-05-22 |

**Still Not Working**:
- SELinux label modification (setfattr fails) ✗
- .so loading from arbitrary non-user-installed paths (e.g., random `$HOME/` subdirectories without proper installation) ✗

### 4. Technical Details

```
# Comparison
System .so:
  Path: /data/service/hnp/python.org/python_3.12/lib/python3.12/lib-dynload/_ssl.cpython-312.so
  SELinux: u:object_r:hnp_file:s0
  Code sign: NOT FOUND
  Load: SUCCESS

User .so:
  Path: $HOME/Claude/venv/lib/python3.12/site-packages/numpy/_core/_multiarray_umath.cpython-312.so
  SELinux: u:object_r:hmdfs:s0
  Code sign: self-sign (added manually)
  Load: PERMISSION DENIED
```

## Why Our Python Build Works

Our locally compiled Python (see [python-harmonyos.md](python-harmonyos.md)) uses `-rdynamic` to export 948+ Py symbols (1521 total), allowing extension modules compiled with `-DPy_BUILD_CORE_MODULE` to resolve symbols without needing `libpython.so`.

**This now works for extensions in user paths as well**. The combination of `-rdynamic` Python + code signing for all .so files resolves the SELinux blocking issue. 34/34 tested packages with compiled extensions (numpy, pillow, lxml, bcrypt, greenlet, etc.) all load successfully from `$HOME/.local/lib/python3.12/site-packages/`. See [python-packages-harmonyos.md](python-packages-harmonyos.md) for details.

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

> **UPDATE**: This option is no longer necessary. All listed packages now work with our `-rdynamic` Python build after code signing.

The following packages now work with compiled extensions from user paths:

| Package | Status | Notes |
|---------|--------|-------|
| numpy | ✓ Working | Compiled with clang, signed .so |
| pandas | ✓ Working | Pure Python (no .so needed for basic use) |
| pillow | ✓ Working | Compiled with clang, signed .so |
| lxml | ✓ Working | Compiled with clang, signed .so |
| matplotlib | Not tested | Mostly pure Python |
| scipy | Not tested | Would need compiled LAPACK dependency |

### Option 5: Remote Python Server

Run Python with compiled extensions on a remote server, communicate via HTTP/WebSocket.

**Pros**:
- Full Python functionality on server
- Local machine handles UI/interface

**Cons**:
- Requires network connection
- Not suitable for offline work

## Conclusion

> **UPDATE (2026-05-22)**: The original conclusion below is outdated. The issue has been **resolved** via `-rdynamic` Python + code signing. 34/34 packages with compiled .so extensions now load successfully from user paths.

**Original Analysis (2026-05-12)**: The loading of compiled .so files from user paths was blocked by HarmonyOS SELinux policy, specifically:
1. Path-based label assignment (hmdfs vs hnp_file)
2. Domain restriction (hishell_hap cannot execute from user paths)
3. This was a **platform-level security decision**, not a bug

**Resolved Solution**: Our `-rdynamic` Python build exports 948+ Py symbols (1521 total), enabling extension modules to resolve symbols without `libpython.so`. Combined with code signing for all .so files, compiled extensions now load from user paths (`$HOME/.local/lib/python3.12/site-packages/`). This effectively bypasses the SELinux restriction for Python use cases.

See [python-packages-harmonyos.md](python-packages-harmonyos.md) for the full 34/34 package compatibility report.

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