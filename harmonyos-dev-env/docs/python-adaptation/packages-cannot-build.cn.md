# 无法构建的 Python 包 — HarmonyOS

> **169 个 Python 包可用**，9 个无法构建（详见下文）。

## 永久阻塞（硬件/平台限制）

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| scipy | 需要gfortran（Fortran编译器） | HarmonyOS 没有 Fortran 编译器（gfortran）。scipy 的 C/Fortran 扩展模块无法编译。 | 无 — 硬件限制 |
| uvloop | libuv vendor 无法配置 | libuv 的 autoconf 无法检测 HarmonyOS 平台；musl libc 缺少 cpu_set_t、CPU_SETSIZE 和 mmsghdr。需要大量 libuv 源码补丁。 | 无 — 平台限制 |

## 构建复杂度问题

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| polars | cargo metadata 失败 | Polars 是复杂的 Rust/PyO3 包；pip 构建期间 cargo metadata 失败。需要下载源码手动构建。 | 考虑替代方案（pandas 可用） |
| grpcio | C/C++ 构建过于复杂 | grpcio 需要从源码构建 gRPC Core（C++），需要复杂的 CMake/Bazel 设置。多个依赖（protobuf、c-ares、abseil）造成级联构建问题。 | 考虑替代方案（纯 Python grpcio-io；或直接使用 protobuf 进行消息序列化） |
| pyarrow | Apache Arrow C++ 构建 | pyarrow 需要构建 Apache Arrow C++ 库（巨大代码库，复杂 CMake）。构建需30+分钟且有大量平台特定问题。 | 考虑替代方案（pandas CSV/Parquet via fastparquet；orjson 用于 JSON） |
| scikit-learn | 需要 scipy + Cython | scikit-learn 依赖 scipy（被 Fortran 阻塞）。即使没有 scipy，Cython 扩展也有复杂的构建需求。 | 耡虑替代方案（手动实现特定算法；optuna 用于优化） |
| xgboost | CMake + git 子模块 + OpenMP | xgboost 需要 CMake 构建配合递归 git 子模块（dmlc-core、rabit），这些在 HarmonyOS 上无法获取。还需要 OpenMP 支持。 | 考虑替代方案（optuna 用于优化；手动梯度提升） |
| lightgbm | CMake 构建成功但导入失败（需要 scipy） | lightgbm 使用 CC/CXX + --no-build-isolation 成功构建，但导入失败因为 lightgbm.basic 在模块级别导入 scipy.sparse。由于 scipy 无法构建，lightgbm 不可用。 | 考虑替代方案（optuna 用于优化；numpy 向量化操作） |

## 依赖冲突

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| pynacl | libsodium autotools configure 在 HarmonyOS 上失败 | libsodium 的内置 configure 脚本失败因为：(1) /tmp 只读（无法为健全性检查创建临时文件），(2) 编译的测试可执行文件需要代码签名才能执行。meson 自动签名包装器不起作用因为 libsodium 使用 autotools，不是 meson。需要手动编译 libsodium 绕过 configure。 | 考虑替代方案（cryptography 可用 — 提供 NaCl: Ed25519、X25519、ChaCha20Poly1305） |

## 级联失败

| 包 | 错误 | 原因 | 替代方案 |
|---|------|------|----------|
| paramiko | 依赖 pynacl | pynacl 无法构建（libsodium configure 失败）。paramiko 本身是纯 Python，但缺少 nacl.signing 无法工作。 | 无 pynacl 则不可用；尽可能使用 cryptography 的 NaCl 原语 |

## 之前阻塞 — 现已可用

这些包之前在"无法构建"列表中，现已成功适配：

| 包 | 版本 | 适配方法 | E2E 测试 |
|---|------|----------|----------|
| soundfile | 0.14.0 | 从源码编译 libsndfile 1.2.2（cmake+ninja），修补 soundfile.py 支持 HarmonyOS 平台检测 + musl find_library 回退 | 3/3 |
| h5py | 3.16.0 | 从源码编译 HDF5 1.14.6（cmake+ninja，无 zlib/szip），使用 --no-build-isolation 构建 h5py，签名 .so，修复 NEEDED 路径前缀（bin/→），设置 RPATH | 3/3 |
| psycopg2 | 2.9.12 | 从 PostgreSQL 17.5 编译 libpq（meson+ninja），创建 pg_config 包装器，使用 --no-build-isolation 构建 psycopg2，签名 .so | 3/3 |
| numexpr | 2.14.1 | 已安装并正常工作（C 扩展，签名 .so，后缀重命名） | 3/3 |
| numcodecs | 0.16.5 | 使用 --no-build-isolation 构建（Cython 扩展），签名 .so，后缀重命名，设置 RPATH | 3/3 |
| numcodecs 启用 zarr | zarr | numcodecs 可用 → zarr 的压缩编解码器现已正常工作 | 见 zarr e2e |

## 分析

### libsodium configure 失败（pynacl）

libsodium 的 autotools configure 脚本在 HarmonyOS 上失败因为：
1. `/tmp` 只读 — configure 使用 `mktemp` 为健全性检查创建临时文件
2. 编译的测试可执行文件需要代码签名才能在 HarmonyOS 上执行
3. meson 自动签名 clang 包装器只适用于 meson 项目；libsodium 使用 autotools

**潜在修复**（尚未尝试）：手动创建最小 config.h，使用 clang 直接将所有 libsodium .c 文件编译为 .so，完全绕过 configure。

### scipy 依赖级联

多个包在导入时依赖 scipy（不仅是可选功能）：
- **lightgbm**：`import scipy.sparse` 在模块级别 → 导入失败
- **scikit-learn**：scipy 是硬依赖
- 这造成"依赖级联"，构建 C 库并不能解决问题因为 scipy 在导入时就需要

### libuv 平台检测（uvloop）

libuv 的 configure 脚本无法检测 HarmonyOS：
- `musl libc` 缺少 `cpu_set_t`、`CPU_SETSIZE` 和 `mmsghdr` 结构
- autoconf 的 `guess_platform` 逻辑没有 HarmonyOS 条目
- 需要上游级别的 libuv 源码补丁

### Fortran 依赖（scipy）

scipy 需要 Fortran 编译器来编译其核心线性代数模块。HarmonyOS 没有 `gfortran`，也没有合理途径获取：
- 从源码交叉编译 gfortran 需要自举 GCC，而 GCC 本身需要 gcc
- HarmonyOS SDK 只提供 clang（C/C++/ObjC）
- 这是根本的硬件/平台限制