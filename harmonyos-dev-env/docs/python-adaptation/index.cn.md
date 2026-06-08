# HarmonyOS Python 包适配指南

> **渐进式披露**：本索引提供高层概述并链接到详细文档片段。从这里开始，然后根据需要深入查看特定主题。

## 包兼容性概览

**169/169 Python 包可用**，9 个无法构建（详见 [packages-cannot-build.cn.md](packages-cannot-build.cn.md)）。

| 类别 | 通过率 | 典型包 | 适配方法 |
|------|--------|--------|----------|
| 纯 Python | 100% | requests, flask, jinja2, httpx, pytest, structlog | 直接 pip install |
| C/C++ 扩展 | 100% | bcrypt, greenlet, hiredis, lz4, zstd, xxhash | CC/CXX + 签名 .so + 后缀重命名 |
| C++ 扩展 (libc++_shared.so) | 100% | python-rapidjson, ujson, cytoolz, contourpy, kiwisolver, matplotlib | CC/CXX + 签名 + patchelf --add-needed libc++_shared.so + 后缀重命名 |
| 混合型 (C 库 + Python 绑定) | 100% | pillow (libjpeg), lxml (libxml2), h5py (HDF5), psycopg2 (libpq), soundfile (libsndfile) | 先编译 C 依赖 → pip install → 签名 .so |
| Rust/PyO3 (maturin) | 100% | cryptography, pydantic-core, rpds-py, tiktoken, orjson, tokenizers, safetensors | maturin build + 签名 + 后缀重命名 |
| Meson 构建 | 100% | pandas, matplotlib | 自动签名 clang 包装器 + mesonpy API |
| 平台检测补丁 | 100% | psutil | 补丁 _common.py + net.c |
| ML/NLP | 100% | tokenizers, safetensors, transformers | Rust 构建 + 纯 Python 补丁 |
| 依赖 Fortran | 0% | scipy | HarmonyOS 无 Fortran 编译器 |
| 依赖 libuv | 0% | uvloop | libuv autoconf 无法在 HarmonyOS 上配置 |

详细分类见 [packages-overview.md](packages-overview.md)，逐包测试结果见 [packages-detailed.md](packages-detailed.md)。

## 适配方法论

所有扩展包适配遵循 5 阶段决策树：

1. **确定包类型** — 纯 Python vs C/C++ vs Rust vs Meson
2. **准备构建环境** — CC/CXX、TMPDIR、链接器包装器、RUSTFLAGS
3. **编译与安装** — pip vs wheel 重命名 vs maturin vs mesonpy
4. **签名与 patchelf** — 代码签名 + NEEDED 修复 + RPATH + libc++_shared.so + supplement.so
5. **验证与运行** — 导入测试 + LD_LIBRARY_PATH + 错误诊断

完整逐步方法论见 [extension-guide.md](extension-guide.md)。

## 特殊适配技术

这些技术适用于特定类别的包：

| 技术 | 适用对象 | 文档片段 |
|------|----------|----------|
| C++ patchelf-签名工作流 | 所有 C++ 扩展 | [extension-guide.md](extension-guide.md) Step 4.5 |
| rustc 自动签名包装器 | orjson, tokenizers, safetensors 及任何带构建脚本的 Rust/PyO3 包 | [rustc-wrapper.md](rustc-wrapper.md) |
| Meson 自动签名 clang 包装器 | pandas, matplotlib | [meson-wrapper.md](meson-wrapper.md) |
| asyncio.current_task 段错误修复 | structlog 及任何 logging+asyncio 包 | [extension-guide.md](extension-guide.md) Step 4.7 |
| maturin 直接构建（非 pip） | HarmonyOS 上所有 Rust/PyO3 包 | [extension-guide.md](extension-guide.md) Phase 3 Strategy D |
| fancy-regex 特性 | tokenizers（替代 onig） | [packages-detailed.md](packages-detailed.md) tokenizers 条目 |
| transformers 版本 + FP8 补丁 | transformers 5.10.2 | [packages-detailed.md](packages-detailed.md) transformers 条目 |
| psutil 平台检测 | psutil | [extension-guide.md](extension-guide.md) psutil 示例 |
| cffi LDFLAGS 重建 | cffi 2.0.0 | [extension-guide.md](extension-guide.md) Step 4.6 |

## 无法构建的包

| 包名 | 原因 | 替代方案 |
|------|------|----------|
| scipy | 需要 gfortran（Fortran 编译器） | 无 — 硬件限制 |
| uvloop | libuv autoconf 无法配置 | 无 — 平台限制 |
| polars | cargo metadata 过于复杂 | 考虑替代方案（pandas 可用） |
| pynacl | libsodium configure 失败（/tmp只读，测试可执行文件需签名） | 考虑替代方案（cryptography 可用） |
| grpcio | C++ 构建过于复杂 | 考虑替代方案（纯 Python grpcio-io） |
| scikit-learn | 需要 scipy | 考虑替代方案（optuna） |
| xgboost | git 子模块无法获取 + OpenMP | 考虑替代方案（optuna） |
| lightgbm | 导入失败（需要 scipy.sparse） | 考虑替代方案（optuna） |
| pyarrow | Apache Arrow C++ 构建过于复杂 | 考虑替代方案（pandas CSV） |

详细错误分析见 [packages-cannot-build.md](packages-cannot-build.md)。

## 已编译原生库

| 库名 | 版本 | 被使用于 |
|------|------|----------|
| libjpeg-turbo | 3.0.4 | pillow |
| libpng | 1.6.48 | pillow |
| libxml2 | 2.14.0 | lxml |
| libxslt | 1.1.42 | lxml |
| libffi | 8 | cffi/cryptography |
| libopenblas | 0.3.28 | PyTorch/numpy |
| libhdf5 | 1.14.6 | h5py |
| libpq | 5.17 | psycopg2 |
| libsndfile | 1.2.2 | soundfile |

详见 [packages-overview.md](packages-overview.md) 已编译原生库章节。

## 快速参考

```bash
# 环境设置（所有扩展构建必需）
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export TMPDIR=$HOME/Claude/tmpdir
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"

# 批量签名包内所有 .so
find ~/.local/lib/python3.12/site-packages/<pkg> -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +

# 重命名 .so 后缀
cd ~/.local/lib/python3.12/site-packages/<pkg>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```