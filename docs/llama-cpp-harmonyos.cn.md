# llama.cpp HarmonyOS (aarch64) 适配与端到端测试

## 1. 仓库克隆：GitHub 直连失败，使用国内代理

**问题**：`github.com:443` 连接超时（HarmonyOS 网络环境限制）。

**解决方案**：使用 `gh-proxy.com` 代理克隆：
```bash
git clone https://gh-proxy.com/https://github.com/ggml-org/llama.cpp.git
```

**注意**：克隆后，部分文件可能检出为空（0 字节），需要使用 `git show HEAD:<path>` 手动恢复：
- `src/unicode-data.cpp`（7034 行 → 0 字节）
- `examples/speculative-simple/speculative-simple.cpp`（348 行 → 0 字节）

恢复方法：
```bash
git show HEAD:src/unicode-data.cpp > /tmpdir/unicode-data.cpp
cp /tmpdir/unicode-data.cpp src/unicode-data.cpp
```

由于仓库内的权限问题，无法直接执行 `git show HEAD:src/unicode-data.cpp > src/unicode-data.cpp`。需要先写入 `tmpdir/`，然后 `cp` 覆盖。

---

## 2. CMake 构建配置

**问题**：CMake 无法识别 HarmonyOS 平台（`System is unknown to cmake`），默认使用通用 CPU 实现。

**解决方案**：使用 Ninja + Clang 构建，关键参数：
```bash
cmake .. \
  -GNinja \
  -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
  -DCMAKE_CXX_COMPILER=/data/service/hnp/bin/clang++ \
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
  -DLLAMA_BUILD_SERVER=ON \   # llama-cli 需要 LLAMA_BUILD_SERVER=ON
  -DBUILD_SHARED_LIBS=OFF
```

**关键点**：
- `-GNinja`：`make` 的 `-j` 参数在 HarmonyOS 上因 mkfifo 失败，必须使用 Ninja
- `-DGGML_NATIVE=OFF`：防止 CMake 检测未知平台特性导致构建失败
- `-DLLAMA_BUILD_SERVER=ON`：`llama-cli` 目标仅在 `LLAMA_BUILD_SERVER=ON` 时包含（在 `tools/CMakeLists.txt` 中 `add_subdirectory(cli)` 由此开关控制）
- `-DBUILD_SHARED_LIBS=OFF`：静态链接避免 HarmonyOS 动态库加载问题

---

## 3. 链接器错误：unicode-data 空文件导致未定义符号

**问题**：链接阶段错误：
```
ld.lld: error: undefined symbol: unicode_map_lowercase
ld.lld: error: undefined symbol: unicode_ranges_nfd
ld.lld: error: undefined symbol: unicode_set_whitespace
ld.lld: error: undefined symbol: unicode_ranges_flags
```

**原因**：检出时 `src/unicode-data.cpp` 变为空文件（0 字节），编译产生无效 obj（824 字节），链接缺少符号定义。

**解决方案**：恢复 `src/unicode-data.cpp` 内容，然后删除旧的 obj 和 libllama.a 强制重新编译：
```bash
rm -f build/src/CMakeFiles/llama.dir/unicode-data.cpp.obj
rm -f build/src/libllama.a
ninja -C build
```

仅恢复源文件不够——Ninja 的依赖跟踪不会检测文件内容变化，必须删除过期的目标文件。

---

## 4. 运行时：libomp.so 加载失败

**问题**：运行 `llama-cli --version` 错误：
```
Error loading shared library libomp.so: (needed by llama-cli)
Error relocating ... __kmpc_global_thread_num: symbol not found
```

**解决方案**：设置 `LD_LIBRARY_PATH` 包含 OpenMP 库路径：
```bash
export LD_LIBRARY_PATH=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos:$LD_LIBRARY_PATH
```

---

## 5. 模型下载：HuggingFace CDN 不可达

**问题**：`hf-mirror.com` API 可访问但文件下载 CDN 超时（文件下载使用不同的 CDN 域名）。

**解决方案**：从 ModelScope 下载 GGUF 模型（ModelScope CDN 在中国可达）：
```bash
curl -L --connect-timeout 30 --max-time 1800 -# -o models/Qwen3.5-0.8B-Q4_K_M.gguf \
  "https://modelscope.cn/models/unsloth/Qwen3.5-0.8B-GGUF/resolve/master/Qwen3.5-0.8B-Q4_K_M.gguf"
```

**注意**：GitHub 代理（gh-proxy.com）限制文件下载（403），仅适用于 git clone。实际文件下载需要使用 ModelScope。

---

## 6. Qwen3.5 架构支持确认

llama.cpp 原生支持 Qwen3.5 系列：
- `src/models/qwen35.cpp` — dense 版本
- `src/models/qwen35moe.cpp` — MoE 版本

模型元数据确认架构为 `qwen35`（混合 SSM+Attention），包含：
- 24 层，1024 嵌入维度，8 个注意力头 / 2 个 KV 头（GQA=4）
- SSM 参数：d_conv=4, d_state=128, n_group=16, dt_rank=16, d_inner=2048
- full_attention_interval=4（每 4 层全注意力，其余使用 SSM/Gated Delta Net）

---

## 7. 推理测试结果

| 项目 | 数值 |
|------|-----|
| 模型 | Qwen3.5-0.8B Q4_K_M (497.39 MiB) |
| 量化 | Q4_K - Medium (5.55 BPW) |
| 提示词评估 | 76.81 tokens/s |
| 生成 | 40.09 tokens/s |
| 总内存 | 4374 MiB (497 模型 + 3091 上下文 + 786 计算) |
| 平台 | HarmonyOS aarch64, Clang 15.0.4 |
| 构建版本 | b9073-a8fd165fe |

---

## 8. CPU 加速构建：ARM NEON/SVE/i8mm 优化

### 8.1 问题

CMake 无法识别 HarmonyOS 平台（`CMAKE_SYSTEM_PROCESSOR` 为 "unknown"），导致 `GGML_SYSTEM_ARCH` 被设置为 "UNKNOWN"，ggml-cpu 回退到 `GGML_CPU_GENERIC`（无 SIMD 优化）。编译标志缺少 `-mcpu=native+dotprod+i8mm+sve`。

### 8.2 根本原因

`ggml/cmake/common.cmake` 的 `ggml_get_system_arch()` 函数通过 `CMAKE_SYSTEM_PROCESSOR` 正则匹配架构。HarmonyOS 不在 CMake 已知平台列表中，处理器类型回退为 "unknown"，不匹配 `^(aarch64|arm.*|ARM64)$`。

### 8.3 解决方案：修补 common.cmake 添加编译器目标回退

在 `ggml_get_system_arch()` 函数开头添加编译器目标三元组检测：
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

HarmonyOS 上 Clang 的 `clang -dumpmachine` 返回 `aarch64-unknown-linux-ohos`，匹配 aarch64。

**注意**：不要使用 `CMAKE_TOOLCHAIN_FILE` 配合 `CMAKE_SYSTEM_NAME=Generic` 来解决——这会触发 CMake 的交叉编译模式，导致 `check_cxx_source_runs()`（try_run）失败，ARM 特性检测全部被跳过。

### 8.4 加速构建 CMake 配置

**重要提示**：加速构建**不要**在 `CMAKE_C_FLAGS` 中添加 `-B$LINKER_WRAPPER_DIR`！这个参数会影响 CMake 的 `try_run` 测试程序，导致 ARM 特性检测失败（测试程序需要正确执行才能检测 CPU 特性）。

ld.bfd wrapper 只在链接阶段需要。如果链接失败报 `libxml2.so.16 not found`，添加 linker flags：
```bash
  -DCMAKE_EXE_LINKER_FLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

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

关键变更：
- `GGML_NATIVE=ON`（原来是 OFF）→ 启用 `-mcpu=native` + 特性检测
- `GGML_LLAMAFILE=ON` → 启用 llamafile SGEMM 优化内核
- 不再需要手动设置 `GGML_CPU_ARM_ARCH`（`GGML_NATIVE=ON` 自动检测）
- **不在 `CMAKE_C_FLAGS` 中使用 linker wrapper**，避免影响 try_run 测试

### 8.5 检测到的 ARM 特性

| 特性 | 状态 | 描述 |
|---------|--------|-------------|
| dotprod | ✓ | ARMv8.2 INT8 点积（asimddp）|
| i8mm | ✓ | ARMv8.6 INT8 矩阵乘法（vmmlaq_s32）|
| sve | ✓ | 可伸缩向量扩展 |
| sme | ✗ | 可伸缩矩阵扩展（CPU 不支持）|

编译标志：`-mcpu=native+dotprod+i8mm+sve+nosme`

### 8.6 性能对比（9B Q4_K_M 模型）

| 指标 | 通用构建 | 加速构建 | 提升 |
|--------|---------------|-------------------|-------------|
| 提示词评估 | 6.0-7.5 t/s | 24-31.7 t/s | **~4 倍** |
| Token 生成 | 4.2-5.4 t/s | 6.9-7.8 t/s | **~40-56%** |
| 模型内存 | 5357 MiB | 5369 MiB | 略有增加 |
| 总内存 | ~9 GiB | ~9 GiB | 无变化 |

**提示词评估**提升最显著（~4 倍），因为 NEON/SVE 优化了提示词批量矩阵运算。**Token 生成**提升约 50%，主要来自 dotprod/i8mm 加速 Q4_K 反量化+矩阵乘法，以及 llamafile SGEMM 内核。

---

## 总结：HarmonyOS llama.cpp 适配检查清单

1. **克隆**：使用 `gh-proxy.com` 代理，检出后检查并恢复空文件
2. **构建**：Ninja + Clang，`GGML_NATIVE=ON`，`GGML_LLAMAFILE=ON`，`LLAMA_BUILD_SERVER=ON`，静态链接
3. **架构检测**：修补 `ggml/cmake/common.cmake` 添加编译器目标回退，避免 GGML_CPU_GENERIC
4. **不要使用 toolchain**：CMAKE_SYSTEM_NAME=Generic 触发交叉编译，try_run 失败
5. **链接**：确保 `unicode-data.cpp` 等生成文件非空，删除过期 obj 强制重编译
6. **运行时**：设置 `LD_LIBRARY_PATH` 包含 libomp.so 路径
7. **下载**：使用 ModelScope 而非 HuggingFace CDN 下载模型文件

---

## 9. Qwen3.5-9B CoT 模型测试

### 9.1 模型信息

| 项目 | 数值 |
|------|-------|
| 模型 | Qwen3.5-9B Q4_K_M (5.5 GiB) |
| 架构 | qwen35（混合 SSM+Attention）|
| CoT 支持 | 使用 `<think>` 标签进行推理 |
| 平台 | HarmonyOS aarch64，20 核 |

### 9.2 推理预算参数

CoT 模型（如 Qwen3.5-9B）需要 `--reasoning-budget` 来控制思考 token 分配：

```bash
llama-cli -m models/Qwen3.5-9B-Q4_K_M.gguf \
  -p "你的提示词" \
  -c 8192 \
  -n 512 \
  --reasoning-budget 128 \
  -st --simple-io --no-warmup
```

**为什么 `--reasoning-budget` 关键**：
- 不加此参数时，CoT 模型可能将 80-90% 的 `-n` 预算用于思考链
- 结果：实际输出只剩几十个 token
- 加上 `--reasoning-budget 128`，思考链被限制在约 128 token
- 剩余预算用于可见响应

### 9.3 9B 模型性能

| 指标 | 数值 |
|------|-------|
| 提示词评估 | 24-31.7 tokens/s（加速构建）|
| Token 生成 | 6.9-7.8 tokens/s |
| 模型内存 | ~5.4 GiB |
| 总内存 | ~9 GiB |

### 9.4 模型质量测试

全部 10 项质量测试通过：
- 模型加载 ✓
- 中文理解 ✓
- 数学推理 ✓
- 逻辑推导 ✓
- 代码生成（LCS 动态规划）✓
- 指令遵循 ✓
- 日语 ✓
- CoT 陷阱题（"17只羊，除了9只都死了" → 9只）✓
- 世界知识（牛顿三定律）✓
- 性能基准 ✓