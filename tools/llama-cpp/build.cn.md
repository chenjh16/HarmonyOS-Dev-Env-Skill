# llama.cpp HarmonyOS (aarch64) 适配与端到端测试

> **English version available at build.md**

## 1. 仓库克隆：GitHub 直连不通，需用国内代理

**问题**: `github.com:443` 连接超时（HarmonyOS 网络环境限制）。

**解决**: 使用 `gh-proxy.com` 代理克隆：
```bash
git clone https://gh-proxy.com/https://github.com/ggml-org/llama.cpp.git
```

**注意**: 克隆后部分文件 checkout 失败（空文件），需手动 `git show HEAD:<path>` 恢复。涉及文件：
- `src/unicode-data.cpp` (7034 行 → 0 字节)
- `examples/speculative-simple/speculative-simple.cpp` (348 行 → 0 字节)

恢复方法：
```bash
git show HEAD:src/unicode-data.cpp > /tmpdir/unicode-data.cpp
cp /tmpdir/unicode-data.cpp src/unicode-data.cpp
```
不能直接 `git show HEAD:src/unicode-data.cpp > src/unicode-data.cpp`，因该路径在仓库内有权限问题会导致写入失败。需先写到 `tmpdir/` 再 `cp` 过去。

---

## 2. 关键前置：ld.bfd Wrapper

**重要**: SDK 的 lld 需要 `libxml2.so.16`，该库不存在于 HarmonyOS。必须创建 ld.bfd wrapper：

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

---

## 3. CMake 构建配置

**问题**: CMake 无法识别 HarmonyOS 平台（`System is unknown to cmake`），默认回退 generic CPU 实现。

**解决**: 使用 Ninja + Clang 构建，关键参数：
```bash
LINKER_WRAPPER_DIR=$HOME/Claude/lib/linker_wrapper

cmake .. \
  -GNinja \
  -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
  -DCMAKE_CXX_COMPILER=/data/service/hnp/bin/clang++ \
  -DCMAKE_C_FLAGS="-B$LINKER_WRAPPER_DIR" \
  -DCMAKE_CXX_FLAGS="-B$LINKER_WRAPPER_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_NATIVE=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_BLAS=OFF \
  -DGGML_CUDA=OFF \
  -DGGML_METAL=OFF \
  -DGGML_VULKAN=OFF \
  -DGGML_OPENCL=OFF \
  -DGGML_SYCL=OFF \
  -DGGML_RPC=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DBUILD_SHARED_LIBS=OFF
```

**关键点**:
- `-GNinja`: `make` 的 `-j` 参数在 HarmonyOS 上会 mkfifo 失败，必须用 Ninja
- `-DGGML_NATIVE=OFF`: 防止 CMake 尝试检测未知平台特性导致编译失败
- `-DLLAMA_BUILD_SERVER=ON`: `llama-cli` 目标只在 `LLAMA_BUILD_SERVER=ON` 时才会被包含（在 `tools/CMakeLists.txt` 中 `add_subdirectory(cli)` 被此开关控制）
- `-DBUILD_SHARED_LIBS=OFF`: 静态链接避免 HarmonyOS 动态库加载问题

---

## 3. 链接错误：unicode-data 空文件导致 undefined symbol

**问题**: 链接阶段报错：
```
ld.lld: error: undefined symbol: unicode_map_lowercase
ld.lld: error: undefined symbol: unicode_ranges_nfd
ld.lld: error: undefined symbol: unicode_set_whitespace
ld.lld: error: undefined symbol: unicode_ranges_flags
```

**原因**: checkout 时 `src/unicode-data.cpp` 变为空文件（0 字节），编译后产生无效 obj（824 字节），链接时缺失符号定义。

**解决**: 恢复 `src/unicode-data.cpp` 内容后，删除旧 obj 和 libllama.a 强制重编译：
```bash
rm -f build/src/CMakeFiles/llama.dir/unicode-data.cpp.obj
rm -f build/src/libllama.a
ninja -C build
```

仅恢复源文件不够——Ninja 的依赖追踪不会检测文件内容变化，必须删除 stale object。

---

## 4. 运行时：libomp.so 加载失败

**问题**: 运行 `llama-cli --version` 报错：
```
Error loading shared library libomp.so: (needed by llama-cli)
Error relocating ... __kmpc_global_thread_num: symbol not found
```

**解决**: 设置 `LD_LIBRARY_PATH` 包含 OpenMP 库路径：
```bash
export LD_LIBRARY_PATH=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos:$LD_LIBRARY_PATH
```

---

## 5. 模型下载：HuggingFace CDN 不可达

**问题**: `hf-mirror.com` API 可访问但文件下载 CDN 连接超时（文件下载走不同 CDN 域）。

**解决**: 从 ModelScope 下载 GGUF 模型（ModelScope CDN 在国内可达）：
```bash
curl -L --connect-timeout 30 --max-time 1800 -# -o models/Qwen3.5-0.8B-Q4_K_M.gguf \
  "https://modelscope.cn/models/unsloth/Qwen3.5-0.8B-GGUF/resolve/master/Qwen3.5-0.8B-Q4_K_M.gguf"
```

**注意**: GitHub 代理（gh-proxy.com）限制文件下载（403），只适合 git clone。实际文件下载需用 ModelScope。

---

## 6. Qwen3.5 架构支持确认

llama.cpp 已原生支持 Qwen3.5 系列：
- `src/models/qwen35.cpp` — dense 版本
- `src/models/qwen35moe.cpp` — MoE 版本

模型元数据确认架构为 `qwen35`（hybrid SSM+Attention），包含：
- 24 layers, 1024 embedding, 8 heads / 2 KV heads (GQA=4)
- SSM 参数: d_conv=4, d_state=128, n_group=16, dt_rank=16, d_inner=2048
- full_attention_interval=4（每 4 层一次 full attention，其余用 SSM/Gated Delta Net）

---

## 7. 推理测试结果

| 项目 | 值 |
|------|-----|
| 模型 | Qwen3.5-0.8B Q4_K_M (497.39 MiB) |
| 量化 | Q4_K - Medium (5.55 BPW) |
| Prompt eval | 76.81 tokens/s |
| Generation | 40.09 tokens/s |
| 总内存 | 4374 MiB (497 model + 3091 context + 786 compute) |
| 平台 | HarmonyOS aarch64, Clang 15.0.4 |
| 构建版本 | b9073-a8fd165fe |

---

## 8. CPU 加速构建：ARM NEON/SVE/i8mm 优化

### 8.1 问题

CMake 无法识别 HarmonyOS 平台（`CMAKE_SYSTEM_PROCESSOR` 为 "unknown"），导致 `GGML_SYSTEM_ARCH` 被设为 "UNKNOWN"，ggml-cpu 走 fallback 到 `GGML_CPU_GENERIC`（无任何 SIMD 优化）。编译 flags 中没有 `-mcpu=native+dotprod+i8mm+sve`。

### 8.2 根因

`ggml/cmake/common.cmake` 中的 `ggml_get_system_arch()` 函数通过 `CMAKE_SYSTEM_PROCESSOR` 正则匹配架构。HarmonyOS 不在 CMake 的已知平台列表中，处理器类型回退为 "unknown"，不匹配 `^(aarch64|arm.*|ARM64)$`。

### 8.3 解决：patch common.cmake 增加编译器目标 fallback

在 `ggml_get_system_arch()` 函数开头加入 compiler target triple 检测：
```cmake
if (NOT CMAKE_SYSTEM_PROCESSOR OR CMAKE_SYSTEM_PROCESSOR STREQUAL "unknown")
    execute_process(
        COMMAND ${CMAKE_C_COMPILER} -dumpmachine
        OUTPUT_VARIABLE COMPILER_TARGET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if (COMPILER_TARGET MATCHES "aarch64|arm")
        set(CMAKE_SYSTEM_PROCESSOR "aarch64")
    elseif (COMPILER_TARGET MATCHES "x86_64|i686|amd64")
        set(CMAKE_SYSTEM_PROCESSOR "x86_64")
    endif()
endif()
```

Clang 在 HarmonyOS 上 `clang -dumpmachine` 返回 `aarch64-unknown-linux-ohos`，匹配到 aarch64。

**注意**：不要用 `CMAKE_TOOLCHAIN_FILE` 设置 `CMAKE_SYSTEM_NAME=Generic` 来解决问题——这会触发 CMake 的 cross-compiling 模式，导致 `check_cxx_source_runs()`（try_run）失败，ARM 特性检测全部被跳过。

### 8.4 加速构建 CMake 配置

**重要提示**：加速构建**不要**在 `CMAKE_C_FLAGS` 中添加 `-B$LINKER_WRAPPER_DIR`！这个参数会影响 CMake 的 `try_run` 测试程序，导致 ARM 特性检测失败（测试程序需要正确执行才能检测 CPU 特性）。

ld.bfd wrapper 只在链接阶段需要，可以通过设置 `CMAKE_LINKER` 或在 `CMAKE_EXE_LINKER_FLAGS` 中配置（如果链接失败才需要）。

```bash
cmake -S . -B build \
  -GNinja \
  -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
  -DCMAKE_CXX_COMPILER=/data/service/hnp/bin/clang++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=ON \
  -DGGML_LLAMAFILE=ON \
  -DGGML_BLAS=OFF \
  -DGGML_CUDA=OFF \
  -DGGML_METAL=OFF \
  -DGGML_VULKAN=OFF \
  -DGGML_OPENCL=OFF \
  -DGGML_SYCL=OFF \
  -DGGML_RPC=OFF \
  -DGGML_ACCELERATE=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_CCACHE=OFF
```

如果链接阶段报错 `libxml2.so.16 not found`，添加 linker flags：
```bash
  -DCMAKE_EXE_LINKER_FLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

关键变更：
- `GGML_NATIVE=ON`（原来是 OFF）→启用 `-mcpu=native` + 特性检测
- `GGML_LLAMAFILE=ON` →启用 llamafile SGEMM 优化内核
- 不再需要 `GGML_CPU_ARM_ARCH` 手动设置（`GGML_NATIVE=ON` 自动检测）
- **不在 `CMAKE_C_FLAGS` 中使用 linker wrapper**，避免影响 try_run 测试

### 8.5 检测到的 ARM 特性

| 特性 | 状态 | 说明 |
|------|------|------|
| dotprod | ✓ | ARMv8.2 INT8 dot product (asimddp) |
| i8mm | ✓ | ARMv8.6 INT8 matrix multiply (vmmlaq_s32) |
| sve | ✓ | Scalable Vector Extension |
| sme | ✗ | Scalable Matrix Extension（CPU 不支持） |

编译 flags: `-mcpu=native+dotprod+i8mm+sve+nosme`

### 8.6 性能对比（9B Q4_K_M 模型）

| 指标 | Generic 构建 | 加速构建 | 提升 |
|------|-------------|---------|------|
| Prompt eval | 6.0-7.5 t/s | 24-31.7 t/s | **~4x** |
| Token 生成 | 4.2-5.4 t/s | 6.9-7.8 t/s | **~40-56%** |
| 模型内存 | 5357 MiB | 5369 MiB | 略增 |
| 总内存 | ~9 GiB | ~9 GiB | 不变 |

**Prompt eval** 提升最显著（~4x），因为 NEON/SVE 优化了 prompt 的批量矩阵运算。**Token 生成** 提升 ~50%，主要来自 dotprod/i8mm 加速 Q4_K 解量化+矩阵乘，以及 llamafile SGEMM 内核。

---

## 总结：HarmonyOS 适配 llama.cpp 的关键 Checklist

1. **克隆**: 用 `gh-proxy.com` 代理，checkout 后检查并恢复空文件
2. **构建**: Ninja + Clang, `GGML_NATIVE=ON`, `GGML_LLAMAFILE=ON`, `LLAMA_BUILD_SERVER=ON`, 静态链接
3. **架构检测**: patch `ggml/cmake/common.cmake` 增加 compiler target fallback，避免 GGML_CPU_GENERIC
4. **不要用 toolchain**: CMAKE_SYSTEM_NAME=Generic 会触发 cross-compile，try_run 失败
5. **链接**: 确保 `unicode-data.cpp` 等生成文件非空，删除 stale obj 强制重编译
6. **运行**: 设置 `LD_LIBRARY_PATH` 包含 libomp.so 路径
7. **下载**: 用 ModelScope 替代 HuggingFace CDN 下载模型文件