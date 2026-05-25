# HarmonyOS Native Child Process IPC 方案分析

> **英文版本**: ipc-feasibility.md

## 概述

HarmonyOS 提供 **Native Child Process API** (`OH_Ability_CreateNativeChildProcess`)，支持:
- 从原生库创建子进程
- 在父进程和子进程间建立 IPC (Binder) 通信
- 可能绕过用户路径 .so 加载限制

本分析评估该 API 是否能解决 [selinux-analysis.cn.md](selinux-analysis.cn.md) 中记录的 SELinux 阻止问题。

## API 详情

### 必需头文件
```c
#include "AbilityKit/native_child_process.h"
#include "IPCKit/ipc_kit.h"
```

### 可用库
- `libchild_process.so` (NDK)
- `libipc_capi.so` (IPC Kit)
- `libchild_process_manager.z.so` (系统)

### 关键函数

```c
// 创建原生子进程
int OH_Ability_CreateNativeChildProcess(
    const char* libName,                // 子进程加载的库
    OH_Ability_OnNativeChildProcessStarted onProcessStarted  // 回调
);

// 回调接收 IPC 代理
typedef void (*OH_Ability_OnNativeChildProcessStarted)(
    int errCode,
    OHIPCRemoteProxy *remoteProxy       // IPC 通信对象
);

// 子进程库必需导出:
OHIPCRemoteStub* NativeChildProcess_OnConnect();  // 返回 IPC stub
void NativeChildProcess_MainProc();                // 主循环
```

### IPC 通信 (Binder)

```c
// 父进程发送请求
int OH_IPCRemoteProxy_SendRequest(
    const OHIPCRemoteProxy *proxy,
    uint32_t code,
    const OHIPCParcel *data,
    OHIPCParcel *reply,
    const OH_IPC_MessageOption *option
);

// 子进程处理请求
typedef int (*OH_OnRemoteRequestCallback)(
    uint32_t code,
    const OHIPCParcel *data,
    OHIPCParcel *reply,
    void *userData
);
```

## 错误码分析

| 代码 | 名称 | 含义 |
|------|------|------|
| 0 | NCP_NO_ERROR | 成功 |
| 401 | NCP_ERR_INVALID_PARAM | 参数无效 |
| 801 | NCP_ERR_NOT_SUPPORTED | 设备不支持 |
| **16010004** | NCP_ERR_MULTI_PROCESS_DISABLED | **多进程模式禁用** |
| 16010005 | NCP_ERR_ALREADY_IN_CHILD | 已在子进程中 |
| 16010006 | NCP_ERR_MAX_CHILD_PROCESSES_REACHED | 达到最大进程数 |
| 16010007 | NCP_ERR_LIB_LOADING_FAILED | 库加载失败 |

## 提议架构

```
┌─────────────────────┐     Binder IPC      ┌─────────────────────┐
│   父进程            │◄────────────────────►│   子进程            │
│   (Python CLI)      │                      │   (原生服务)        │
│                     │                      │                     │
│  - Python 运行时    │   请求: "numpy"      │  - 加载 numpy.so    │
│  - 纯 Python 包     │   响应: 结果         │  - 执行调用         │
│  - IPC 代理客户端   │                      │  - 通过 IPC 返回    │
└─────────────────────┘                      └─────────────────────┘
        │                                            │
        │                                            │
   用户路径                                     系统路径?
   (hmdfs SELinux)                           (不同上下文?)
```

## 挑战与限制

### 挑战 1: 库路径要求

`libName` 参数指定的库必须能被子进程加载。文档显示:
```
dlopen(libName)  // 在子进程中
```

**问题**: 该库可以在用户路径，还是必须在 HAP libs 目录?

基于分析:
- Bundle 库 SELinux 标签: `data_app_el1_file`
- 用户库 SELinux 标签: `hishell_hap_data_file` 或 `hmdfs`
- 子进程很可能继承父进程安全上下文

**可能方案**: 将库放在 `/data/storage/el2/base/haps/entry/libs/arm64/`

### 挑战 2: 多进程模式

错误码 `NCP_ERR_MULTI_PROCESS_DISABLED (16010004)` 表示多进程模式可按设备或应用禁用。

**要求**:
- 应用必须在 `module.json` 声明多进程能力
- 设备必须支持原生子进程

**检查**: hishell 应用可能未启用多进程。

### 挑战 3: IPC 复杂度

IPC 通信需要:
- Parcel 序列化/反序列化
- 同步/异步请求处理
- 错误处理和超时管理
- 线程池管理

### 挑战 4: NumPy 集成

NumPy 是复杂库:
- 多个内部 .so 文件
- 模块间相互依赖
- 状态管理 (数组对象、内存)
- 无法轻松代理所有功能

## 可行性评估

| 方面 | 可行性 | 说明 |
|------|--------|------|
| API 可用 | ✓ 是 | libchild_process.so 可加载 |
| 多进程 | ⚠ 未知 | hishell 可能禁用 |
| 库路径 | ✗ 问题 | 用户路径 .so 仍被阻止 |
| IPC 复杂度 | ⚠ 中等 | 需大量代码 |
| NumPy 代理 | ✗ 极难 | 太复杂无法代理 |
| 安全上下文 | ✗ 可能问题 | 子进程继承父进程上下文 |

## 为什么无法解决问题

1. **子进程继承安全上下文** - 相同 SELinux 限制适用
2. **库必须在允许路径** - 不是用户路径
3. **多进程可能禁用** - 需应用配置
4. **NumPy 太复杂** - 无法轻松代理所有功能
5. **IPC 开销** - 显著降低数据密集操作速度

## 结论

### 可行性: 低

Native Child Process API 设计用于:
- 原生应用 (C/C++)
- HAP 打包服务
- 受控 IPC 场景

**不适合**:
- Python 扩展加载
- 任意 .so 文件执行
- 用户安装包

### 推荐替代方案

1. **接受限制**: 本地使用纯 Python 包
2. **云计算**: 在远程服务器运行 numpy
3. **HAP 打包**: 如需 numpy，创建正式 HAP 应用 (非 CLI)
4. **WebAssembly**: 未来可能，如有 WASM 运行时

---

*分析日期: 2026-05-12*
*API 版本: HarmonyOS SDK 26.0.0.18*
*Native Child Process API: 自 12 起*