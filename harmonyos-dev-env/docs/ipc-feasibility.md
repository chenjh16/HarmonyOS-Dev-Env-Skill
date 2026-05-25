# HarmonyOS Native Child Process IPC Solution Analysis

> **Chinese version**: ipc-feasibility.cn.md

## Overview

HarmonyOS provides **Native Child Process API** (`OH_Ability_CreateNativeChildProcess`) that allows:
- Creating a child process from a native library
- Establishing IPC (Binder) communication between parent and child
- Potentially bypassing user-path .so loading restrictions

This analysis evaluates whether this API can solve the SELinux blocking issue documented in [selinux-analysis.md](selinux-analysis.md).

## API Details

### Required Headers
```c
#include "AbilityKit/native_child_process.h"
#include "IPCKit/ipc_kit.h"
```

### Available Libraries
- `libchild_process.so` (NDK)
- `libipc_capi.so` (IPC Kit)
- `libchild_process_manager.z.so` (System)

### Key Functions

```c
// Create native child process
int OH_Ability_CreateNativeChildProcess(
    const char* libName,                // Library to load in child
    OH_Ability_OnNativeChildProcessStarted onProcessStarted  // Callback
);

// Callback receives IPC proxy
typedef void (*OH_Ability_OnNativeChildProcessStarted)(
    int errCode,
    OHIPCRemoteProxy *remoteProxy       // IPC object for communication
);

// Required exports from child library:
OHIPCRemoteStub* NativeChildProcess_OnConnect();  // Return IPC stub
void NativeChildProcess_MainProc();                // Main loop
```

### IPC Communication (Binder)

```c
// Parent process sends request
int OH_IPCRemoteProxy_SendRequest(
    const OHIPCRemoteProxy *proxy,
    uint32_t code,
    const OHIPCParcel *data,
    OHIPCParcel *reply,
    const OH_IPC_MessageOption *option
);

// Child process handles request
typedef int (*OH_OnRemoteRequestCallback)(
    uint32_t code,
    const OHIPCParcel *data,
    OHIPCParcel *reply,
    void *userData
);
```

## Error Codes Analysis

| Code | Name | Meaning |
|------|------|---------|
| 0 | NCP_NO_ERROR | Success |
| 401 | NCP_ERR_INVALID_PARAM | Invalid parameters |
| 801 | NCP_ERR_NOT_SUPPORTED | Device doesn't support |
| **16010004** | NCP_ERR_MULTI_PROCESS_DISABLED | **Multi-process mode disabled** |
| 16010005 | NCP_ERR_ALREADY_IN_CHILD | Already in child process |
| 16010006 | NCP_ERR_MAX_CHILD_PROCESSES_REACHED | Max processes reached |
| 16010007 | NCP_ERR_LIB_LOADING_FAILED | Library loading failed |

## Proposed Architecture

```
┌─────────────────────┐     Binder IPC      ┌─────────────────────┐
│   Parent Process    │◄────────────────────►│   Child Process     │
│   (Python CLI)      │                      │   (Native Service)  │
│                     │                      │                     │
│  - Python runtime   │   Request: "numpy"   │  - Loads numpy.so   │
│  - Pure Python pkgs │   Response: result   │  - Executes call    │
│  - IPC Proxy client │                      │  - Returns via IPC  │
└─────────────────────┘                      └─────────────────────┘
        │                                            │
        │                                            │
   User Path                                    System Path?
   (hmdfs SELinux)                            (Different context?)
```

## Challenges and Limitations

### Challenge 1: Library Path Requirement

The `libName` parameter specifies a library that must be loadable by the child process. The documentation shows:
```
dlopen(libName)  // In child process
```

**Question**: Can this library be in user path, or must it be in HAP libs directory?

Based on analysis:
- Bundle libs have SELinux label: `data_app_el1_file`
- User libs have SELinux label: `hishell_hap_data_file` or `hmdfs`
- Child process likely inherits parent's security context

**Possible Solution**: Place library in `/data/storage/el2/base/haps/entry/libs/arm64/`

### Challenge 2: Multi-Process Mode

Error code `NCP_ERR_MULTI_PROCESS_DISABLED (16010004)` indicates multi-process mode can be disabled per device or per app.

**Requirements**:
- App must declare multi-process capability in `module.json`
- Device must support native child processes

**Check**: hishell app may not have multi-process enabled.

### Challenge 3: IPC Complexity

IPC communication requires:
- Parcel serialization/deserialization
- Synchronous/asynchronous request handling
- Error handling and timeout management
- Thread pool management

### Challenge 4: NumPy Integration

NumPy is a complex library:
- Multiple internal .so files
- Interdependencies between modules
- State management (array objects, memory)
- Cannot easily proxy all functionality

## Feasibility Assessment

| Aspect | Feasibility | Notes |
|--------|-------------|-------|
| API Available | ✓ Yes | libchild_process.so can be loaded |
| Multi-Process | ⚠ Unknown | May be disabled for hishell |
| Library Path | ✗ Problematic | User path .so still blocked |
| IPC Complexity | ⚠ Moderate | Requires significant code |
| NumPy Proxying | ✗ Very Hard | Too complex to proxy |
| Security Context | ✗ Likely Issue | Child inherits parent context |

## Why It Won't Solve Our Problem

1. **Child process inherits security context** - Same SELinux restrictions apply
2. **Library must be in allowed paths** - Not user paths
3. **Multi-process may be disabled** - Requires app configuration
4. **NumPy too complex** - Cannot easily proxy all functionality
5. **IPC overhead** - Would significantly slow down data-intensive operations

## Conclusion

### Feasibility: LOW

The Native Child Process API is designed for:
- Native applications (C/C++)
- HAP-packaged services
- Controlled IPC scenarios

**Not suitable for**:
- Python extension loading
- Arbitrary .so file execution
- User-installed packages

### Recommended Alternatives

1. **Accept limitation**: Use pure Python packages locally
2. **Cloud computing**: Run numpy on remote servers
3. **HAP packaging**: If need numpy, create proper HAP application (not CLI)
4. **WebAssembly**: Future possibility if WASM runtime available

---

*Analysis Date: 2026-05-12*
*API Version: HarmonyOS SDK 26.0.0.18*
*Native Child Process API: since 12*