# PyTorch v2.5.1 on HarmonyOS - 适配指南

> **状态**: 15/15 — 完全功能正常（NumPy 和 LAPACK 已修复）
> **日期**: 2026-05-22
> **PyTorch 版本**: 2.5.0a0+gita8d6afb

## 概述

本文档记录了在 HarmonyOS（鸿蒙内核 1.12.0，aarch64）上编译 PyTorch v2.5.1 的完整适配过程。15/15 个端到端测试全部通过（NumPy 和 LAPACK 已修复）。

## 前置条件

- HarmonyOS SDK（含 clang 15.0.4）
- Python 3.12.8（独立构建版本）
- TMPDIR 设置为可写位置（非 /tmp）

## 关键适配点

### 1. 链接器问题：lld 依赖 libxml2.so.16

**问题描述**: SDK 的 `lld` 链接器位于 `/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin/lld`，动态链接到 `libxml2.so.16`，但该库在 HarmonyOS 上不存在。这会阻塞所有 C++ 编译。

**错误信息**:
```
Error loading shared library libxml2.so.16: (needed by lld)
Error relocating lld: xmlFreeDoc: symbol not found
```

**解决方案**: 通过 `-B` 标志包装器使用 GNU ld.bfd 链接器替代 lld。

创建包装器目录：
```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
# 将 ld.lld 调用重定向到 ld.bfd 的包装器
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

应用到编译：
```bash
export CFLAGS="-B$HOME/Claude/lib/linker_wrapper"
export CXXFLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

### 2. __assert_fail 签名不匹配

**问题描述**: PyTorch 声明 `__assert_fail` 使用 `unsigned int line` 和 `noexcept`，但 HarmonyOS/musl 使用 `int line` 且无 `noexcept`。

**文件**: `c10/macros/Macros.h` — 两个位置需修复：
- 主声明位于第 414-419 行
- SYCL 变体位于第 398 行（同样使用 `unsigned int line`）

**原始代码**:
```cpp
void
__assert_fail(
    const char* assertion,
    const char* file,
    unsigned int line,
    const char* function) noexcept __attribute__((__noreturn__));
```

**修复**: 修改为匹配 musl 签名：
```cpp
void
__assert_fail(
    const char* assertion,
    const char* file,
    int line,
    const char* function) __attribute__((__noreturn__));
```

同时更新第 431-445 行的宏，移除 `static_cast<unsigned int>(__LINE__)`：
```cpp
#define CUDA_KERNEL_ASSERT(cond)                                         \
  if (C10_UNLIKELY(!(cond))) {                                           \
    __assert_fail(                                                       \
        #cond, __FILE__, __LINE__, __func__); \
  }
```

### 3. Sleef 交叉编译工具

**问题描述**: PyTorch 的 sleef 库在交叉编译时需要原生工具（`mkrename`、`mkalias`、`mkdisp`），但它们被编译为目标架构。

**解决方案**: 为主机编译工具并放置在 `NATIVE_BUILD_DIR` 中：

```bash
mkdir -p $HOME/Claude/tmpdir/sleef-native/bin

# 编译 mkrename
clang -B$HOME/Claude/lib/linker_wrapper \
  -I$PYTORCH_SRC/third_party/sleef/src/libm \
  $PYTORCH_SRC/third_party/sleef/src/libm/mkrename.c \
  -o mkrename
binary-sign-tool sign -keyAlias "OpenHarmony" -selfSign 1 -inFile mkrename -outFile mkrename-signed
cp mkrename-signed $HOME/Claude/tmpdir/sleef-native/bin/mkrename

# mkalias、mkrename_gnuabi、mkdisp 同理
```

CMake 配置：
```bash
cmake .. -DNATIVE_BUILD_DIR=$HOME/Claude/tmpdir/sleef-native
```

### 4. 代码签名要求

**问题描述**: HarmonyOS 要求所有 ELF 可执行文件和共享库在执行前必须签名。

**解决方案**: 编译后对所有二进制文件签名：
```bash
for lib in libc10.so libtorch_cpu.so libtorch_python.so; do
  binary-sign-tool sign -keyAlias "OpenHarmony" -selfSign 1 \
    -inFile $lib -outFile ${lib}.signed
  mv ${lib}.signed $lib
done
```

**注意**: `protoc` 二进制文件在 cmake 期间会被重新构建，每次都需要重新签名。

### 5. ldd 不可用

**问题描述**: HarmonyOS 上不存在 `ldd` 命令。CMake 可能会调用它进行依赖检查。

**解决方案**: 使用 `llvm-readelf` 创建包装器：
```bash
cat > $HOME/Claude/lib/linker_wrapper/ldd << 'EOF'
#!/bin/sh
/data/service/hnp/bin/llvm-readelf -d "$1" 2>/dev/null | grep NEEDED | sed 's/.*\[//;s/\].*//'
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ldd
```

**注意**: 之前的正则表达式 `sed 's/.*NEEDED).*\[(.*)\].*/\1/'` 有问题——括号和方括号未正确转义。请使用两步替换 `sed 's/.*\[//;s/\].*//'`。

### 6. Python 扩展模块 (_C.so)

**问题描述**: `_C` Python 扩展是一个桩模块，链接到 `libtorch_python.so`。

**解决方案**: 编译 stub.c 创建正确的 Python 模块：
```bash
clang -B$HOME/Claude/lib/linker_wrapper \
  -shared \
  -I$PYTHON_HOME/include/python3.12 \
  -I$PYTORCH_SRC/torch/csrc \
  -L$TORCH_INSTALL/lib \
  $PYTORCH_SRC/torch/csrc/stub.c \
  -ltorch_python \
  -o _C.so
binary-sign-tool sign -keyAlias "OpenHarmony" -selfSign 1 -inFile _C.so -outFile _C.so.signed
```

### 7. torch_shm_manager

**问题描述**: PyTorch 共享内存操作需要 `torch_shm_manager` 可执行文件。

**解决方案**: 从构建目录复制并签名：
```bash
mkdir -p $TORCH_INSTALL/bin
cp $PYTORCH_BUILD/bin/torch_shm_manager $TORCH_INSTALL/bin/
binary-sign-tool sign -keyAlias "OpenHarmony" -selfSign 1 \
  -inFile torch_shm_manager -outFile torch_shm_manager.signed
```

### 8. NumPy 支持（编译后增量修复）

**问题描述**: `torch.from_numpy()` 报错 "PyTorch was compiled without NumPy support"。这是因为初始 CMake 构建时未找到 NumPy（NumPy 是后续安装的）。

**解决方案**: 增量修复——仅重新编译 `tensor_numpy.cpp`（带 `USE_NUMPY` 标志），然后重新链接 `libtorch_python.so`：

```bash
cd $PYTORCH_BUILD/caffe2/torch

# 1. 使用 USE_NUMPY 重新编译 tensor_numpy.cpp
/data/service/hnp/bin/clang++ -B$HOME/Claude/lib/linker_wrapper \
  -DUSE_NUMPY \
  -I$HOME/.local/lib/python3.12/site-packages/numpy/_core/include \
  [flags.make 中的完整 include 路径] \
  -std=gnu++17 -c \
  $HOME/Claude/pytorch-v2.5.1/torch/csrc/utils/tensor_numpy.cpp \
  -o CMakeFiles/torch_python.dir/csrc/utils/tensor_numpy.cpp.o.new

# 2. 替换目标文件
mv CMakeFiles/torch_python.dir/csrc/utils/tensor_numpy.cpp.o \
   CMakeFiles/torch_python.dir/csrc/utils/tensor_numpy.cpp.o.old
mv CMakeFiles/torch_python.dir/csrc/utils/tensor_numpy.cpp.o.new \
   CMakeFiles/torch_python.dir/csrc/utils/tensor_numpy.cpp.o

# 3. 重新链接 libtorch_python.so（使用 link.txt 中的确切命令）
cat CMakeFiles/torch_python.dir/link.txt
# 执行链接命令，将输出路径改为 libtorch_python.so.new

# 4. 签名新库
binary-sign-tool sign -selfSign 1 -keyAlias "key" \
  -inFile ../../lib/libtorch_python.so.new \
  -outFile ../../lib/libtorch_python.so.signed

# 5. 替换已安装的库
mv ~/.local/lib/python3.12/site-packages/torch/lib/libtorch_python.so backup/
cp ../../lib/libtorch_python.so.signed \
   ~/.local/lib/python3.12/site-packages/torch/lib/libtorch_python.so
```

**结果**: `torch.from_numpy()` 和 `tensor.numpy()` 现在正常工作，支持内存共享。

### 9. OpenBLAS/LAPACK 编译（为 torch.det()）

**问题描述**: `torch.det()` 和 `torch.linalg.lu_factor()` 报错 "requires compiling PyTorch with LAPACK"。PyTorch 的 `BatchLinearAlgebraKernel.cpp` 使用 `#if !AT_BUILD_WITH_LAPACK()` 进行条件编译——没有该宏时函数返回错误。

**解决方案**: 编译 OpenBLAS（使用 NOFORTRAN=1 启用 f2c 转换的 LAPACK），并使用 `USE_LAPACK=ON` 重新构建 PyTorch：

```bash
# 1. 下载并解压 OpenBLAS v0.3.28
curl -sL -x http://127.0.0.1:7890 -o $HOME/Claude/tmpdir/OpenBLAS-v0.3.28.tar.gz \
  "https://github.com/OpenMathLib/OpenBLAS/archive/refs/tags/v0.3.28.tar.gz"
tar xzf OpenBLAS-v0.3.28.tar.gz

# 2. 修复预构建：getarch/getarch_2nd 需要 -B 链接器包装器和代码签名
# 修改 Makefile.prebuild 添加 -B 包装器和签名步骤
# 或手动编译：
clang -B$HOME/Claude/lib/linker_wrapper -O2 -o getarch getarch.c cpuid.S
binary-sign-tool sign -selfSign 1 -keyAlias "key" -inFile getarch -outFile getarch_signed

# 3. 使用 NOFORTRAN=1 构建 OpenBLAS（单线程，make -j 在 HarmonyOS 上失败）
make NOFORTRAN=1 TARGET=ARMV8 BINARY=64 \
  'CC=/data/service/hnp/bin/clang -B$HOME/Claude/lib/linker_wrapper' \
  CFLAGS="-O2" HOST_CFLAGS="-O2" -j1 libs

# 4. 手动安装头文件和静态库
cp libopenblas_armv8p-r0.3.28.a ~/.local/lib/libopenblas.a
cp cblas.h ~/.local/include/
cp lapack-netlib/LAPACKE/include/lapacke.h ~/.local/include/

# 5. 从静态库创建共享库
clang -B$HOME/Claude/lib/linker_wrapper \
  -shared -o ~/.local/lib/libopenblas.so \
  -Wl,--whole-archive ~/.local/lib/libopenblas.a \
  -Wl,--no-whole-archive -lpthread -lm
binary-sign-tool sign -selfSign 1 -keyAlias "key" \
  -inFile ~/.local/lib/libopenblas.so -outFile ~/.local/lib/libopenblas.so.signed
mv ~/.local/lib/libopenblas.so.signed ~/.local/lib/libopenblas.so
```

**重要提示**: OpenBLAS 编译过程中每步生成的可执行文件（getarch、getarch_2nd）都需要签名后才能运行。需要修改 `Makefile.prebuild` 来添加 `-B` 链接器包装器和 `binary-sign-tool` 签名步骤。

### 10. Sleef CMakeLists 修复（NATIVE_BUILD_DIR）

**问题描述**: 当不使用 `CMAKE_TOOLCHAIN_FILE` 配合 `CMAKE_SYSTEM_NAME=Linux`（以避免 `try_run()` 失败）时，`CMAKE_CROSSCOMPILING` 为 FALSE，因此 sleef 会自行编译原生工具（mkrename、mkdisp）而非使用 `NATIVE_BUILD_DIR`。这些工具需要签名后才能运行，形成循环依赖。

**解决方案**: 修改 `third_party/sleef/CMakeLists.txt`，当提供了 `NATIVE_BUILD_DIR` 时即使非交叉编译也使用预编译工具：

```cmake
# 在 add_host_executable 函数中（约第 234 行）
function(add_host_executable TARGETNAME)
  # 当提供 NATIVE_BUILD_DIR 时使用它（即使非交叉编译）
  # 这避免了在构建过程中需要签名 sleef 工具
  if (NOT CMAKE_CROSSCOMPILING AND NOT DEFINED NATIVE_BUILD_DIR)
    add_executable(${TARGETNAME} ${ARGN})
    ...
  else()
    add_executable(${TARGETNAME} IMPORTED GLOBAL)
    set_property(TARGET ${TARGETNAME} PROPERTY IMPORTED_LOCATION ${NATIVE_BUILD_DIR}/bin/${TARGETNAME})
  endif()
endfunction()
```

### 11. ldd 包装器（CMake 4.1.2）

**问题描述**: CMake 4.1.2 在链接可执行文件后会自动运行 `ldd` 进行依赖检查（通过 `__run_co_compile --lwyu="ldd;-u;-r"`）。如果 PATH 中没有 `ldd`，所有链接步骤都会失败。

**解决方案**: 将 ldd 包装器复制到 `~/.local/bin/ldd`（该路径在 PATH 中）：

```bash
cp $HOME/Claude/lib/linker_wrapper/ldd $HOME/.local/bin/ldd
```

### 12. Sleef 头文件生成 Bug

**问题描述**: 使用 NATIVE_BUILD_DIR 的 IMPORTED sleef 工具时，CMake 生成的 ninja 规则只拼接 `sleeflibm_header.h.org` 和 `sleeflibm_footer.h.org`，缺失所有 SIMD section 文件（`sleeflibm_*.h.tmp`）。导致 `dispscalar.c` 中 `Sleef_double_2` 等类型未定义。

**解决方案**: 手动生成 `sleef.h`，拼接所有 section 文件：

```bash
cd $PYTORCH_BUILD/sleef/src/libm
cat sleeflibm_header.h.org \
  sleeflibm_ADVSIMD.h.tmp sleeflibm_ADVSIMDNOFMA.h.tmp sleeflibm_ADVSIMD_.h.tmp \
  sleeflibm_DSP_SCALAR.h.tmp sleeflibm_PUREC_SCALAR.h.tmp sleeflibm_PURECFMA_SCALAR.h.tmp \
  sleeflibm_SVE.h.tmp sleeflibm_SVENOFMA.h.tmp \
  $PYTORCH_SRC/third_party/sleef/src/libm/sleeflibm_footer.h.org \
  > $PYTORCH_BUILD/include/sleef.h
cp $PYTORCH_BUILD/include/sleef.h $PYTORCH_BUILD/sleef/include/sleef.h
```

### 13. cpuinfo 静态库缺失 ARM 对象文件

**问题描述**: `libcpuinfo.a` 只包含 4 个对象文件（api.c.obj, cache.c.obj, init.c.obj, log.c.obj），但需要 17+ 个文件包括 ARM Linux 初始化。缺少 `cpuinfo_arm_linux_init` 导致 `libc10.so` 链接失败。

**解决方案**: 用所有编译好的对象文件重建 `libcpuinfo.a`：

```bash
# 列出所有 .o 文件
find $PYTORCH_BUILD/confu-deps/cpuinfo/CMakeFiles/cpuinfo.dir/src -name "*.o" -type f | sort

# 创建完整静态库
/data/service/hnp/bin/ar rcs $PYTORCH_BUILD/lib/libcpuinfo.a \
  $(find $PYTORCH_BUILD/confu-deps/cpuinfo/CMakeFiles/cpuinfo.dir/src -name "*.o" -type f | sort)
```

### 14. visibility=hidden 导致动态符号缺失

**问题描述**: PyTorch 使用 `-fvisibility=hidden` 编译，导致 `RefcountedMapAllocator::decref()`、`incref()` 和 `at::internal::invoke_parallel()` 从 libtorch_cpu.so 动态符号表中被隐藏。libtorch_python.so 引用这些符号导致 "symbol not found"。

**解决方案**: 创建 `libtorch_supplement.so` 补充库提供 stub 实现，通过 `patchelf --add-needed` 添加为依赖。

### 15. NEEDED 库路径格式差异

**问题描述**: Ninja 构建的库使用 "lib/" 前缀（如 `lib/libtorch_cpu.so`），原始安装使用无前缀格式。导致运行时加载错误。

**解决方案**: 使用 patchelf 修复 NEEDED 条目。

## CMake 配置

**重要提示**: 不要使用 `CMAKE_TOOLCHAIN_FILE` 配合 `CMAKE_SYSTEM_NAME=Linux`——这会触发 CMake 的交叉编译模式，导致 `try_run()` 失败（因为 CMake 无法执行测试二进制文件）。改用轻量级 toolchain 文件，仅设置编译器和链接器包装器，不设 `CMAKE_SYSTEM_NAME`。

构建命令（使用 **Ninja**，不要用 `make -j`——`make -j` 会因 `mkfifo` 返回"Operation not permitted"而失败）：

```bash
mkdir -p build && cd build

OpenBLAS_HOME=$HOME/.local \
cmake $PYTORCH_SRC \
  -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$HOME/Claude/tmpdir/toolchain-harmonyos-lite.cmake \
  -DGLIBCXX_USE_CXX11_ABI=0 \
  -DBUILD_PYTHON=ON \
  -DBUILD_TEST=OFF \
  -DUSE_CUDA=OFF \
  -DUSE_KINETO=OFF \
  -DNATIVE_BUILD_DIR=$HOME/Claude/tmpdir/sleef-native \
  -DCMAKE_BUILD_TYPE=Release \
  -DPython_EXECUTABLE=$HOME/.local/bin/python3 \
  -DUSE_LAPACK=ON \
  -DBLAS=OpenBLAS \
  -DLAPACK_LIBRARIES=$HOME/.local/lib/libopenblas.so \
  -DLAPACK_FOUND=TRUE \
  -DUSE_EIGEN_FOR_BLAS=OFF \
  -DUSE_MKL=OFF

ninja
```

**关于 `make -j` 的说明**: 并行 make 使用 `mkfifo` 进行 jobserver 通信，但 `mkfifo` 在 HarmonyOS 上返回"Operation not permitted"。Ninja 不使用 `mkfifo`，可以正常并行构建。

**关于 NATIVE_BUILD_DIR 和 sleef 的说明**: 即使非交叉编译，sleef 仍需要 `NATIVE_BUILD_DIR/bin/` 工具（见适配 #10——需修改 sleef CMakeLists.txt 以便在提供 `NATIVE_BUILD_DIR` 时使用它）。如果不做此修改，ninja 会尝试在本地编译 sleef 工具，需要对每个工具（protoc、mkrename、mkdisp 等）进行签名，形成循环依赖。

**关于 LAPACK 配置的说明**: CMake 的 `find_package(LAPACK)` 无法在 OpenBLAS 中找到 LAPACK。需显式设置 `LAPACK_LIBRARIES` 和 `LAPACK_FOUND=TRUE`，并设置 `OpenBLAS_HOME` 环境变量以便 OpenBLAS 搜索。

**关于 protoc 签名的说明**: `protoc` 二进制文件在 cmake 期间会被重新构建，每次都需要重新签名。CMake 4.1.2 还在链接后运行 `ldd`（PATH 中需要有 ldd——复制到 `~/.local/bin/`）。

## 构建结果

| 组件 | 大小 | 状态 |
|-----------|------|--------|
| libc10.so | 1.2MB | 已构建 |
| libtorch_cpu.so | 183MB | 已构建 |
| libtorch_python.so | 23MB | 已构建 |
| libtorch.so | 19KB | 已构建 |
| libshm.so | 56KB | 已构建 |
| functorch.so | - | 已构建 |

构建完成度：**100%**（零错误）

## 端到端测试

15/15 个测试全部通过：

1. PyTorch 版本: 2.5.0a0+gita8d6afb ✓
2. CUDA 可用: False（纯 CPU 设备预期行为） ✓
3. CPU 线程数: 20 ✓
4. 张量创建: ✓（tensor、zeros、ones、randn、arange）
5. 算术运算: ✓（add、sub、mul、div、pow）
6. 矩阵运算: ✓（matmul、transpose、sum、mean）
7. 神经网络模块: ✓（Linear、ReLU、Sequential）
8. 自动求导: ✓（backward、梯度计算）
9. 优化器: ✓（SGD 前向/反向传播）
10. 保存/加载: ✓（torch.save、torch.load）
11. 设备操作: ✓（CPU 设备）
12. 数据类型操作: ✓（float32、float64、int32）
13. torch.det() ✓（LAPACK 已修复）
14. torch.from_numpy() ✓（通过增量修复已解决）
15. torch.linalg.norm() ✓

### 已验证 LAPACK 功能

通过 OpenBLAS v0.3.28（NOFORTRAN=1，f2c 转换的 LAPACK 3.9.0）启用 LAPACK 后，以下线性代数功能已验证正常工作：

- `torch.det()` — 矩阵行列式计算
- `torch.linalg.svd()` — 奇异值分解
- `torch.linalg.lu_factor()` — LU 分解
- `torch.linalg.inv()` — 矩阵求逆
- `torch.linalg.norm()` — 向量/矩阵范数

## MNIST 神经网络训练

成功在 MNIST 数据集上训练神经网络（纯 CPU）：

| 指标 | 值 |
|--------|-------|
| 数据集 | MNIST（5000 训练样本，500 测试样本）|
| 模型 | 3 层全连接网络（784→128→64→10）|
| 优化器 | Adam（lr=0.001）|
| 训练轮数 | 5 |
| 批次大小 | 32 |
| 最终训练准确率 | 95.9% |
| 测试准确率 | **92.4%** |
| 模型大小 | 440KB |

训练命令：
```bash
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH
export TMPDIR=$HOME/Claude/tmpdir
python3 mnist_train.py
```

模型保存路径：`$HOME/Claude/tmpdir/mnist_model.pt`

## 安装目录结构

```
$HOME/.local/lib/python3.12/site-packages/torch/
├── lib/
│   ├── libc10.so
│   ├── libtorch_cpu.so
│   ├── libtorch_python.so
│   ├── libtorch.so
│   ├── libshm.so
│   ├── libtorch_supplement.so
│   └── libtorch_global_deps.so
├── bin/
│   └── torch_shm_manager
├── _C.so          # Python 扩展模块
├── __init__.py
├── nn/
├── optim/
├── autograd/
└── ... (其他模块)
```

## 经验总结

1. **始终使用 ld.bfd 包装器**: SDK 的 lld 有未满足的依赖——不要试图修复 lld，直接绕过它。

2. **匹配 musl 签名**: HarmonyOS 使用 musl libc——根据 `/data/service/hnp/ohos-sdk.org/.../sysroot/usr/include/` 检查函数签名。主 `__assert_fail` 声明和 SYCL 变体都需要修复（第 398 行和第 414-419 行）。

3. **签名所有文件**: 每个 ELF 二进制文件都需要签名——在构建脚本中设置自动签名。包括 protoc、sleef 原生工具和所有 .so 库。CMake 4.1.2 需要 PATH 中有 `ldd`。

4. **使用轻量级 toolchain 文件**: 使用仅设置编译器和链接器包装器的 CMake toolchain 文件，不设 `CMAKE_SYSTEM_NAME`。这避免了 `try_run()` 失败，同时允许 sleef 使用 `NATIVE_BUILD_DIR`。

5. **使用 Ninja，不要用 make -j**: `make -j` 使用 `mkfifo` 进行 jobserver 通信，在 HarmonyOS 上返回"Operation not permitted"。Ninja 可以正常工作。

6. **NATIVE_BUILD_DIR 配合 sleef CMakeLists 修复**: 修改 sleef 的 `add_host_executable` 函数，当提供 `NATIVE_BUILD_DIR` 时（即使非交叉编译）使用 `NATIVE_BUILD_DIR/bin/` 工具。这避免了构建过程中需要对 sleef 工具进行签名的循环依赖。

7. **NumPy 编译后增量修复**: 如果 CMake 期间未找到 NumPy，`torch.from_numpy()` 会报错。通过增量重新编译 `tensor_numpy.cpp`（带 `-DUSE_NUMPY`）并重新链接 `libtorch_python.so` 即可修复，无需完整重新构建。

8. **OpenBLAS 为 LAPACK 提供支持**: 使用 `NOFORTRAN=1` 编译 OpenBLAS v0.3.28（使用 f2c 转换的 LAPACK 3.9.0）。需要修改 `Makefile.prebuild` 来添加 `-B` 链接器包装器和代码签名步骤。从 .a 创建 .so 以便 CMake 的 `find_library` 找到。

9. **Python 桩模块**: PyTorch 的 Python 绑定是一个加载主库的薄桩——不要试图将 libtorch_python.so 直接作为 Python 扩展。

10. **Sleef 头文件生成**: CMake 的 sleef_concat_files 使用 NATIVE_BUILD_DIR IMPORTED 工具时会生成不完整的 sleef.h。需手动拼接所有 sleeflibm_*.h.tmp + header.org + footer.org。

11. **cpuinfo 静态库不完整**: libcpuinfo.a 可能只包含 4 个目标文件。需用 `ar rcs` 从 confu-deps/cpuinfo 的所有 .o 文件重建，以包含 ARM Linux 初始化函数。

12. **visibility=hidden + supplement.so**: PyTorch 使用 `-fvisibility=hidden` 编译，导致 `RefcountedMapAllocator::decref/incref` 和 `at::internal::invoke_parallel` 从 libtorch_cpu.so 动态符号表中被隐藏。创建 `libtorch_supplement.so` 提供 stub 实现，通过 `patchelf --add-needed` 添加为 NEEDED 依赖。

13. **NEEDED 路径前缀修复**: Ninja 构建的库在 NEEDED 条目中使用 "lib/" 前缀（如 `lib/libtorch_cpu.so`）。使用 `patchelf --replace-needed` 去除前缀，并 `--set-rpath` 设置 `$ORIGIN:$HOME/.local/lib`。

14. **完整 LAPACK 需要全量编译**: 初始 OpenBLAS (NOFORTRAN=1) 只编译了基础 LAPACK（getrf, getrs）。完整 LAPACK 需要编译 lapack-netlib/SRC/ 的全部 1912 个 C 源文件，以支持 sytrf、gelsd、geev 等高级函数。

15. **从 .a 创建 OpenBLAS .so**: 使用 `-Wl,--whole-archive` 从静态库创建共享库以包含所有符号。添加 pthread stub 解决 `pthread_setaffinity_np`（musl 不提供）。

## 后续工作

- 潜在的 aarch64 SIMD 优化
- 与标准 Linux 构建的性能基准对比

## 参考链接

- PyTorch 源码: https://github.com/pytorch/pytorch (v2.5.1)
- HarmonyOS SDK: `/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/`
- HarmonyOS 上的 Python: [python-harmonyos.cn.md](python-harmonyos.cn.md)
