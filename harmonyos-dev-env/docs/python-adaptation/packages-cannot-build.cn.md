# 无法构建的 Python 包 — HarmonyOS

## 永久阻塞（硬件/平台限制）

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| scipy | 需要gfortran（Fortran编译器） | HarmonyOS 没有 Fortran 编译器（gfortran）。scipy 的 C/Fortran 扩展模块无法编译。 | 无 — 硬件限制 |
| uvloop | libuv vendor 无法配置 | libuv 的 autoconf 无法检测 HarmonyOS 平台；musl libc 缺少 cpu_set_t、CPU_SETSIZE 和 mmsghdr。需要大量 libuv 源码补丁。 | 无 — 平台限制 |

## 构建复杂度问题

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| polars | cargo metadata 失败 | Polars 是复杂的 Rust/PyO3 包；pip 构建期间 cargo metadata 失败。需要下载源码手动构建。 | 考虑替代方案（pandas 可用） |

## 依赖冲突

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| pynacl | libsodium C 扩展 + cffi 版本冲突 | pip 构建隔离触发 cffi 版本不匹配：我们的 cffi 2.0.0 vs HNP 系统的 cffi 1.17.1。`--no-build-isolation` 也失败，因为子进程加载 `/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/_cffi_backend.cpython-312.so`（1.17.1）。需要手动编译 libsodium + cffi 版本锁定。 | 考虑替代方案（cryptography 可用） |

## 级联失败

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| paramiko | 依赖 pynacl | pynacl 无法构建（cffi 版本冲突）。paramiko 本身是纯 Python，但缺少 nacl.signing 无法工作。 | 无 pynacl 则不可用 |

## 分析

### cffi 版本冲突（pynacl）

这是最细微的失败。根本原因：1. 我们的 Python 有 cffi 2.0.0 和 `_cffi_backend.cpython-312-aarch64-linux-gnu.so`（2.0.0 版）2. HNP 系统Python 在 `/data/service/hnp/python.org/python_3.12/bin/python3.12` 有 cffi 1.17.1 和 `_cffi_backend.cpython-312.so`（1.17.1 版）3. pip 构建隔离使用 HNP 系统Python，加载其自身的 cffi backend 4. `--no-build-isolation` 也失败，因为子进程调用仍加载 HNP cffi backend **潜在修复**（尚未尝试）：从源码编译 libsodium，然后使用我们的 cffi 2.0.0 手动创建 pynacl 的 C 扩展，完全绕过 pip。

### libuv 平台检测（uvloop）

libuv 的 configure 脚本无法检测 HarmonyOS：- `musl libc` 缺少 `cpu_set_t`、`CPU_SETSIZE` 和 `mmsghdr` 结构- autoconf 的 `guess_platform` 逻辑没有 HarmonyOS 条目- 需要上游级别的 libuv 源码补丁

### Fortran 依赖（scipy）

scipy 需要Fortran 编译器来编译其核心线性代数模块。HarmonyOS 没有 `gfortran`，也没有合理途径获取一个：- 从源码交叉编译gfortran需要一个可用的 GCC，而HarmonyOS SDK 只提供 clang（C/C++/ObjC）- 这是根本的硬件/平台限制