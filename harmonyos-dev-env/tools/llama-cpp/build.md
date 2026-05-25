# llama.cpp HarmonyOS (aarch64) Adaptation and End-to-End Testing

> **中文版本见 build.cn.md**

## 1. Repository Clone: Direct GitHub Connection Does Not Work, Use Proxy

**Problem**: `github.com:443` connection timeout (HarmonyOS network environment limitation).

**Solution**: Use `gh-proxy.com` proxy for cloning:
```bash
git clone https://gh-proxy.com/https://github.com/ggml-org/llama.cpp.git
```

**Note**: After cloning, some files fail to checkout (empty files), need to manually restore with `git show HEAD:<path>`. Affected files:
- `src/unicode-data.cpp` (7034 lines -> 0 bytes)
- `examples/speculative-simple/speculative-simple.cpp` (348 lines -> 0 bytes)

Restoration method:
```bash
git show HEAD:src/unicode-data.cpp > /tmpdir/unicode-data.cpp
cp /tmpdir/unicode-data.cpp src/unicode-data.cpp
```
Cannot directly `git show HEAD:src/unicode-data.cpp > src/unicode-data.cpp`, as that path has permission issues in the repository that cause write failure. Need to write to `tmpdir/` first then `cp` over.

---

## 2. Key Prerequisite: ld.bfd Wrapper

**Important**: SDK's lld requires `libxml2.so.16`, which does not exist on HarmonyOS. You must create an ld.bfd wrapper:

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

---

## 3. CMake Build Configuration

**Problem**: CMake cannot recognize the HarmonyOS platform (`System is unknown to cmake`), defaults to generic CPU implementation.

**Solution**: Build with Ninja + Clang, key parameters:
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

**Key points**:
- `-GNinja`: `make`'s `-j` parameter fails on HarmonyOS because mkfifo returns "Operation not permitted", must use Ninja
- `-DGGML_NATIVE=OFF`: Prevents CMake from trying to detect unknown platform features which would cause build failure
- `-DLLAMA_BUILD_SERVER=ON`: The `llama-cli` target is only included when `LLAMA_BUILD_SERVER=ON` (in `tools/CMakeLists.txt`, `add_subdirectory(cli)` is controlled by this switch)
- `-DBUILD_SHARED_LIBS=OFF`: Static linking to avoid HarmonyOS dynamic library loading issues

---

## 4. Link Error: Empty unicode-data File Causes Undefined Symbol

**Problem**: Link stage error:
```
ld.lld: error: undefined symbol: unicode_map_lowercase
ld.lld: error: undefined symbol: unicode_ranges_nfd
ld.lld: error: undefined symbol: unicode_set_whitespace
ld.lld: error: undefined symbol: unicode_ranges_flags
```

**Cause**: During checkout, `src/unicode-data.cpp` became an empty file (0 bytes), producing an invalid obj (824 bytes) after compilation, missing symbol definitions at link time.

**Solution**: After restoring `src/unicode-data.cpp` content, delete the old obj and libllama.a to force recompilation:
```bash
rm -f build/src/CMakeFiles/llama.dir/unicode-data.cpp.obj
rm -f build/src/libllama.a
ninja -C build
```

Just restoring the source file is not enough — Ninja's dependency tracking does not detect file content changes, stale objects must be deleted.

---

## 5. Runtime: libomp.so Loading Failure

**Problem**: Running `llama-cli --version` produces error:
```
Error loading shared library libomp.so: (needed by llama-cli)
Error relocating ... __kmpc_global_thread_num: symbol not found
```

**Solution**: Set `LD_LIBRARY_PATH` to include the OpenMP library path:
```bash
export LD_LIBRARY_PATH=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos:$LD_LIBRARY_PATH
```

---

## 6. Model Download: HuggingFace CDN Not Reachable

**Problem**: `hf-mirror.com` API is accessible but file download CDN connection times out (file downloads use a different CDN domain).

**Solution**: Download GGUF models from ModelScope (ModelScope CDN is reachable in China):
```bash
curl -L --connect-timeout 30 --max-time 1800 -# -o models/Qwen3.5-0.8B-Q4_K_M.gguf \
  "https://modelscope.cn/models/unsloth/Qwen3.5-0.8B-GGUF/resolve/master/Qwen3.5-0.8B-Q4_K_M.gguf"
```

**Note**: GitHub proxy (gh-proxy.com) restricts file downloads (403), only suitable for git clone. Actual file downloads need to use ModelScope.

---

## 7. Qwen3.5 Architecture Support Confirmation

llama.cpp natively supports the Qwen3.5 series:
- `src/models/qwen35.cpp` — dense version
- `src/models/qwen35moe.cpp` — MoE version

Model metadata confirms architecture is `qwen35` (hybrid SSM+Attention), including:
- 24 layers, 1024 embedding, 8 heads / 2 KV heads (GQA=4)
- SSM parameters: d_conv=4, d_state=128, n_group=16, dt_rank=16, d_inner=2048
- full_attention_interval=4 (full attention every 4 layers, remaining use SSM/Gated Delta Net)

---

## 8. Inference Test Results

| Item | Value |
|------|-------|
| Model | Qwen3.5-0.8B Q4_K_M (497.39 MiB) |
| Quantization | Q4_K - Medium (5.55 BPW) |
| Prompt eval | 76.81 tokens/s |
| Generation | 40.09 tokens/s |
| Total memory | 4374 MiB (497 model + 3091 context + 786 compute) |
| Platform | HarmonyOS aarch64, Clang 15.0.4 |
| Build version | b9073-a8fd165fe |

---

## 9. CPU Accelerated Build: ARM NEON/SVE/i8mm Optimization

### 9.1 Problem

CMake cannot recognize the HarmonyOS platform (`CMAKE_SYSTEM_PROCESSOR` is "unknown"), causing `GGML_SYSTEM_ARCH` to be set to "UNKNOWN", and ggml-cpu falls back to `GGML_CPU_GENERIC` (no SIMD optimization at all). Compile flags do not include `-mcpu=native+dotprod+i8mm+sve`.

### 9.2 Root Cause

The `ggml_get_system_arch()` function in `ggml/cmake/common.cmake` matches architectures via `CMAKE_SYSTEM_PROCESSOR` regex. HarmonyOS is not in CMake's known platform list, the processor type falls back to "unknown", and does not match `^(aarch64|arm.*|ARM64)$`.

### 9.3 Solution: Patch common.cmake to Add Compiler Target Fallback

Add compiler target triple detection at the beginning of the `ggml_get_system_arch()` function:
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

Clang on HarmonyOS returns `aarch64-unknown-linux-ohos` from `clang -dumpmachine`, matching to aarch64.

**Note**: Do not use `CMAKE_TOOLCHAIN_FILE` with `CMAKE_SYSTEM_NAME=Generic` to solve this problem — this triggers CMake's cross-compiling mode, causing `check_cxx_source_runs()` (try_run) failures, and all ARM feature detection is skipped.

### 9.4 Accelerated Build CMake Configuration

**Important note**: For the accelerated build, **do not** add `-B$LINKER_WRAPPER_DIR` to `CMAKE_C_FLAGS`! This parameter affects CMake's `try_run` test programs, causing ARM feature detection to fail (test programs must execute correctly to detect CPU features).

The ld.bfd wrapper is only needed at the link stage, and can be configured via `CMAKE_LINKER` or in `CMAKE_EXE_LINKER_FLAGS` (only needed if linking fails).

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

If link stage errors with `libxml2.so.16 not found`, add linker flags:
```bash
  -DCMAKE_EXE_LINKER_FLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

Key changes:
- `GGML_NATIVE=ON` (previously OFF) -> enables `-mcpu=native` + feature detection
- `GGML_LLAMAFILE=ON` -> enables llamafile SGEMM optimization kernels
- No longer need manual `GGML_CPU_ARM_ARCH` setting (`GGML_NATIVE=ON` auto-detects)
- **Do not use linker wrapper in `CMAKE_C_FLAGS`**, to avoid affecting try_run tests

### 9.5 Detected ARM Features

| Feature | Status | Description |
|---------|--------|-------------|
| dotprod | Yes | ARMv8.2 INT8 dot product (asimddp) |
| i8mm | Yes | ARMv8.6 INT8 matrix multiply (vmmlaq_s32) |
| sve | Yes | Scalable Vector Extension |
| sme | No | Scalable Matrix Extension (CPU does not support) |

Compile flags: `-mcpu=native+dotprod+i8mm+sve+nosme`

### 9.6 Performance Comparison (9B Q4_K_M Model)

| Metric | Generic Build | Accelerated Build | Improvement |
|--------|--------------|-------------------|-------------|
| Prompt eval | 6.0-7.5 t/s | 24-31.7 t/s | **~4x** |
| Token generation | 4.2-5.4 t/s | 6.9-7.8 t/s | **~40-56%** |
| Model memory | 5357 MiB | 5369 MiB | Slight increase |
| Total memory | ~9 GiB | ~9 GiB | No change |

**Prompt eval** improvement is most significant (~4x), because NEON/SVE optimizes prompt batch matrix operations. **Token generation** improved ~50%, mainly from dotprod/i8mm accelerating Q4_K dequantization + matrix multiplication, and llamafile SGEMM kernels.

---

## Summary: Key Checklist for Adapting llama.cpp on HarmonyOS

1. **Clone**: Use `gh-proxy.com` proxy, check and restore empty files after checkout
2. **Build**: Ninja + Clang, `GGML_NATIVE=ON`, `GGML_LLAMAFILE=ON`, `LLAMA_BUILD_SERVER=ON`, static linking
3. **Architecture detection**: Patch `ggml/cmake/common.cmake` to add compiler target fallback, avoid GGML_CPU_GENERIC
4. **Do not use toolchain**: CMAKE_SYSTEM_NAME=Generic triggers cross-compile mode, try_run fails
5. **Link**: Ensure `unicode-data.cpp` and other generated files are non-empty, delete stale obj to force recompilation
6. **Runtime**: Set `LD_LIBRARY_PATH` to include libomp.so path
7. **Download**: Use ModelScope instead of HuggingFace CDN for downloading model files