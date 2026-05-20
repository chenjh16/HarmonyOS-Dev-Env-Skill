# llama.cpp HarmonyOS (aarch64) Adaptation and End-to-End Testing

## 1. Repository Clone: GitHub direct connection fails, use domestic proxy

**Problem**: `github.com:443` connection timeout (HarmonyOS network environment limitation).

**Solution**: Use `gh-proxy.com` proxy to clone:
```bash
git clone https://gh-proxy.com/https://github.com/ggml-org/llama.cpp.git
```

**Note**: After cloning, some files may checkout as empty (0 bytes), need to manually restore using `git show HEAD:<path>`:
- `src/unicode-data.cpp` (7034 lines → 0 bytes)
- `examples/speculative-simple/speculative-simple.cpp` (348 lines → 0 bytes)

Restore method:
```bash
git show HEAD:src/unicode-data.cpp > /tmpdir/unicode-data.cpp
cp /tmpdir/unicode-data.cpp src/unicode-data.cpp
```

Cannot directly `git show HEAD:src/unicode-data.cpp > src/unicode-data.cpp` due to permission issues in the repository. Need to write to `tmpdir/` first then `cp` over.

---

## 2. CMake Build Configuration

**Problem**: CMake cannot recognize HarmonyOS platform (`System is unknown to cmake`), defaults to generic CPU implementation.

**Solution**: Use Ninja + Clang build, key parameters:
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
  -DLLAMA_BUILD_SERVER=ON \   # llama-cli requires LLAMA_BUILD_SERVER=ON
  -DBUILD_SHARED_LIBS=OFF
```

**Key points**:
- `-GNinja`: `make`'s `-j` parameter fails with mkfifo on HarmonyOS, must use Ninja
- `-DGGML_NATIVE=OFF`: Prevents CMake from detecting unknown platform features causing build failure
- `-DLLAMA_BUILD_SERVER=ON`: `llama-cli` target only included when `LLAMA_BUILD_SERVER=ON` (in `tools/CMakeLists.txt` `add_subdirectory(cli)` is controlled by this switch)
- `-DBUILD_SHARED_LIBS=OFF`: Static linking avoids HarmonyOS dynamic library loading issues

---

## 3. Linker Error: unicode-data empty file causing undefined symbol

**Problem**: Linker stage error:
```
ld.lld: error: undefined symbol: unicode_map_lowercase
ld.lld: error: undefined symbol: unicode_ranges_nfd
ld.lld: error: undefined symbol: unicode_set_whitespace
ld.lld: error: undefined symbol: unicode_ranges_flags
```

**Reason**: During checkout, `src/unicode-data.cpp` became empty (0 bytes), compilation produces invalid obj (824 bytes), linking missing symbol definitions.

**Solution**: Restore `src/unicode-data.cpp` content, then delete old obj and libllama.a to force recompilation:
```bash
rm -f build/src/CMakeFiles/llama.dir/unicode-data.cpp.obj
rm -f build/src/libllama.a
ninja -C build
```

Just restoring source file is not enough - Ninja's dependency tracking doesn't detect file content changes, must delete stale object.

---

## 4. Runtime: libomp.so loading failure

**Problem**: Running `llama-cli --version` error:
```
Error loading shared library libomp.so: (needed by llama-cli)
Error relocating ... __kmpc_global_thread_num: symbol not found
```

**Solution**: Set `LD_LIBRARY_PATH` to include OpenMP library path:
```bash
export LD_LIBRARY_PATH=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos:$LD_LIBRARY_PATH
```

---

## 5. Model Download: HuggingFace CDN unreachable

**Problem**: `hf-mirror.com` API accessible but file download CDN timeout (file download uses different CDN domain).

**Solution**: Download GGUF models from ModelScope (ModelScope CDN reachable in China):
```bash
curl -L --connect-timeout 30 --max-time 1800 -# -o models/Qwen3.5-0.8B-Q4_K_M.gguf \
  "https://modelscope.cn/models/unsloth/Qwen3.5-0.8B-GGUF/resolve/master/Qwen3.5-0.8B-Q4_K_M.gguf"
```

**Note**: GitHub proxy (gh-proxy.com) limits file downloads (403), only suitable for git clone. Actual file downloads need ModelScope.

---

## 6. Qwen3.5 Architecture Support Confirmation

llama.cpp natively supports Qwen3.5 series:
- `src/models/qwen35.cpp` — dense version
- `src/models/qwen35moe.cpp` — MoE version

Model metadata confirms architecture as `qwen35` (hybrid SSM+Attention), includes:
- 24 layers, 1024 embedding, 8 heads / 2 KV heads (GQA=4)
- SSM parameters: d_conv=4, d_state=128, n_group=16, dt_rank=16, d_inner=2048
- full_attention_interval=4 (every 4 layers full attention, rest use SSM/Gated Delta Net)

---

## 7. Inference Test Results

| Item | Value |
|------|-----|
| Model | Qwen3.5-0.8B Q4_K_M (497.39 MiB) |
| Quantization | Q4_K - Medium (5.55 BPW) |
| Prompt eval | 76.81 tokens/s |
| Generation | 40.09 tokens/s |
| Total memory | 4374 MiB (497 model + 3091 context + 786 compute) |
| Platform | HarmonyOS aarch64, Clang 15.0.4 |
| Build version | b9073-a8fd165fe |

---

## 8. CPU Acceleration Build: ARM NEON/SVE/i8mm Optimization

### 8.1 Problem

CMake cannot recognize HarmonyOS platform (`CMAKE_SYSTEM_PROCESSOR` is "unknown"), causing `GGML_SYSTEM_ARCH` to be set as "UNKNOWN", ggml-cpu falls back to `GGML_CPU_GENERIC` (no SIMD optimization). Compilation flags lack `-mcpu=native+dotprod+i8mm+sve`.

### 8.2 Root Cause

`ggml/cmake/common.cmake`'s `ggml_get_system_arch()` function matches architecture via `CMAKE_SYSTEM_PROCESSOR` regex. HarmonyOS not in CMake's known platform list, processor type falls back to "unknown", doesn't match `^(aarch64|arm.*|ARM64)$`.

### 8.3 Solution: patch common.cmake add compiler target fallback

Add compiler target triple detection at beginning of `ggml_get_system_arch()` function:
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

Clang on HarmonyOS `clang -dumpmachine` returns `aarch64-unknown-linux-ohos`, matches aarch64.

**Note**: Don't use `CMAKE_TOOLCHAIN_FILE` with `CMAKE_SYSTEM_NAME=Generic` to solve - this triggers CMake's cross-compiling mode, causing `check_cxx_source_runs()` (try_run) to fail, ARM feature detection all skipped.

### 8.4 Acceleration Build CMake Configuration

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

Key changes:
- `GGML_NATIVE=ON` (was OFF) → enables `-mcpu=native` + feature detection
- `GGML_LLAMAFILE=ON` → enables llamafile SGEMM optimization kernels
- No longer need `GGML_CPU_ARM_ARCH` manual setting (`GGML_NATIVE=ON` auto-detects)

### 8.5 Detected ARM Features

| Feature | Status | Description |
|---------|--------|-------------|
| dotprod | ✓ | ARMv8.2 INT8 dot product (asimddp) |
| i8mm | ✓ | ARMv8.6 INT8 matrix multiply (vmmlaq_s32) |
| sve | ✓ | Scalable Vector Extension |
| sme | ✗ | Scalable Matrix Extension (CPU doesn't support) |

Compilation flags: `-mcpu=native+dotprod+i8mm+sve+nosme`

### 8.6 Performance Comparison (9B Q4_K_M model)

| Metric | Generic Build | Accelerated Build | Improvement |
|--------|---------------|-------------------|-------------|
| Prompt eval | 6.0-7.5 t/s | 24-31.7 t/s | **~4x** |
| Token generation | 4.2-5.4 t/s | 6.9-7.8 t/s | **~40-56%** |
| Model memory | 5357 MiB | 5369 MiB | Slight increase |
| Total memory | ~9 GiB | ~9 GiB | Unchanged |

**Prompt eval** improvement most significant (~4x), because NEON/SVE optimizes prompt batch matrix operations. **Token generation** improves ~50%, mainly from dotprod/i8mm accelerating Q4_K dequantization+matrix multiply, plus llamafile SGEMM kernels.

---

## Summary: HarmonyOS llama.cpp Adaptation Checklist

1. **Clone**: Use `gh-proxy.com` proxy, check and restore empty files after checkout
2. **Build**: Ninja + Clang, `GGML_NATIVE=ON`, `GGML_LLAMAFILE=ON`, `LLAMA_BUILD_SERVER=ON`, static linking
3. **Architecture detection**: patch `ggml/cmake/common.cmake` add compiler target fallback, avoid GGML_CPU_GENERIC
4. **Don't use toolchain**: CMAKE_SYSTEM_NAME=Generic triggers cross-compile, try_run fails
5. **Link**: Ensure `unicode-data.cpp` etc generated files non-empty, delete stale obj force recompile
6. **Runtime**: Set `LD_LIBRARY_PATH` include libomp.so path
7. **Download**: Use ModelScope instead of HuggingFace CDN for model files

---

## 9. Qwen3.5-9B CoT Model Testing

### 9.1 Model Information

| Item | Value |
|------|-------|
| Model | Qwen3.5-9B Q4_K_M (5.5 GiB) |
| Architecture | qwen35 (hybrid SSM+Attention) |
| CoT Support | Uses `<think>` tags for reasoning |
| Platform | HarmonyOS aarch64, 20 cores |

### 9.2 Reasoning Budget Parameter

CoT models like Qwen3.5-9B require `--reasoning-budget` to control thinking token allocation:

```bash
llama-cli -m models/Qwen3.5-9B-Q4_K_M.gguf \
  -p "Your prompt here" \
  -c 8192 \
  -n 512 \
  --reasoning-budget 128 \
  -st --simple-io --no-warmup
```

**Why `--reasoning-budget` is critical**:
- Without it, CoT models may spend 80-90% of `-n` budget on thinking chain
- Result: very few tokens left for actual output
- With `--reasoning-budget 128`, thinking is limited to ~128 tokens
- Remaining budget available for visible response

### 9.3 9B Model Performance

| Metric | Value |
|--------|-------|
| Prompt eval | 24-31.7 tokens/s (accelerated build) |
| Token generation | 6.9-7.8 tokens/s |
| Model memory | ~5.4 GiB |
| Total memory | ~9 GiB |

### 9.4 Model Quality Tests

All 10 quality tests passed:
- Model loading ✓
- Chinese understanding ✓
- Math reasoning ✓
- Logical deduction ✓
- Code generation (LCS dynamic programming) ✓
- Instruction following ✓
- Japanese ✓
- CoT trap questions ("17 sheep, all but 9 died" → 9) ✓
- World knowledge (Newton's laws) ✓
- Performance benchmark ✓