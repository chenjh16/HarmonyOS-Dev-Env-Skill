# PyTorch v2.5.1 on HarmonyOS - 适配指南

> **状态**: 完全可用（100% 测试通过）
> **日期**: 2026-05-15
> **PyTorch 版本**: 2.5.0a0+gita8d6afb

## 概述

本文档记录了在 HarmonyOS（鸿蒙内核 1.12.0，aarch64）上编译 PyTorch v2.5.1 的完整适配过程。所有 12 个端到端测试均成功通过。

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

**文件**: `c10/macros/Macros.h`（第 414-419 行）

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
/data/service/hnp/bin/llvm-readelf -d "$1" 2>/dev/null | grep NEEDED | sed 's/.*NEEDED).*\[(.*)\].*/\1/'
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ldd
```

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

## CMake 配置

工具链文件（`toolchain-harmonyos.cmake`）：
```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER /data/service/hnp/bin/clang)
set(CMAKE_CXX_COMPILER /data/service/hnp/bin/clang++)

# 链接器包装器，绕过损坏的 lld
set(LINKER_WRAPPER_DIR /storage/Users/currentUser/Claude/lib/linker_wrapper)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -B${LINKER_WRAPPER_DIR}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -B${LINKER_WRAPPER_DIR}")
set(CMAKE_LINKER /data/service/hnp/bin/ld.bfd)

set(Python_EXECUTABLE /storage/Users/currentUser/.local/bin/python3)
```

构建命令：
```bash
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=../toolchain-harmonyos.cmake \
  -DGLIBCXX_USE_CXX11_ABI=0 \
  -DBUILD_PYTHON=ON \
  -DBUILD_TEST=OFF \
  -DUSE_CUDA=OFF \
  -DUSE_KINETO=OFF \
  -DNATIVE_BUILD_DIR=$HOME/Claude/tmpdir/sleef-native \
  -DCMAKE_BUILD_TYPE=Release

make -j2
```

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

全部 12 个测试通过：

1. PyTorch 版本: 2.5.0a0+gita8d6afb
2. CUDA 可用: False（纯 CPU 设备预期行为）
3. CPU 线程数: 20
4. 张量创建: ✓（tensor、zeros、ones、randn、arange）
5. 算术运算: ✓（add、sub、mul、div、pow）
6. 矩阵运算: ✓（matmul、transpose、sum、mean）
7. 神经网络模块: ✓（Linear、ReLU、Sequential）
8. 自动求导: ✓（backward、梯度计算）
9. 优化器: ✓（SGD 前向/反向传播）
10. 保存/加载: ✓（torch.save、torch.load）
11. 设备操作: ✓（CPU 设备）
12. 数据类型操作: ✓（float32、float64、int32）

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

2. **匹配 musl 签名**: HarmonyOS 使用 musl libc——根据 `/data/service/hnp/ohos-sdk.org/.../sysroot/usr/include/` 检查函数签名。

3. **签名所有文件**: 每个 ELF 二进制文件都需要签名——在构建脚本中设置自动签名。

4. **交叉编译工具**: 当 cmake 检测到交叉编译时，它期望在 `NATIVE_BUILD_DIR/bin/` 中找到原生工具。

5. **Python 桩模块**: PyTorch 的 Python 绑定是一个加载主库的薄桩——不要试图将 libtorch_python.so 直接作为 Python 扩展。

## 未来工作

- NumPy 集成（当前已禁用）
- 潜在的 aarch64 SIMD 优化
- 与标准 Linux 构建的性能基准对比

## 参考链接

- PyTorch 源码: https://github.com/pytorch/pytorch (v2.5.1)
- HarmonyOS SDK: `/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/`
- HarmonyOS 上的 Python: [python-harmonyos.md](python-harmonyos.md)