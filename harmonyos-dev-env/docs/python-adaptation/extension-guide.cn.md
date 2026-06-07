# HarmonyOS Python 扩展模块适配指南

本指南提供了在 HarmonyOS 上适配包含 C、C++ 或 Rust 扩展（`.so` 动态库）的 Python 包的分步通用方法。

纯 Python 包（requests、flask、jinja2 等）无需任何适配即可工作——直接 `pip install` 即可。本指南仅涵盖包含原生扩展的包。

## 阶段 1：判断包类型

| 类型 | 检测方法 | 示例 | 适配难度 |
|------|-----------|---------|---------------------|
| Pure Python | wheel 中无 `.so`，无 `setup.py` 编译步骤 | requests, flask | 无 — 直接 pip install |
| C/C++ extension | `setup.py` 含 `ext_modules`，或 wheel 包含 `.so` | numpy, greenlet, cffi | 中等 — 设置 CC/CXX，签名 .so |
| Mixed (C lib + Python binding) | 需要外部 C 库 | pillow (libjpeg), lxml (libxml2) | 高 — 先编译 C 依赖 |
| Rust extension (PyO3) | 存在 `Cargo.toml`，使用 maturin | pydantic-core, cryptography, rpds-py, tiktoken | 中高 — Rust 工具链 + CC + 构建脚本签名 |
| Meson-based | 存在 `meson.build`，使用 meson-python | pandas, matplotlib | 高 — 自动签名包装器 + mesonpy API |

**快速检查**：查看包的 PyPI 页面或 GitHub 仓库。如果它有包含 `Extension()` 调用的 `setup.py`、`Cargo.toml`、或 wheel 中的 `.so` 文件，则需要适配。

## 阶段 2：准备构建环境

所有扩展构建都需要这些环境变量：

```bash
# 所有 C/C++ 扩展构建必需
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++

# HarmonyOS 必需（/tmp 只读）
export TMPDIR=$HOME/Claude/tmpdir

# C++ 构建必需（SDK lld 损坏，必须使用 ld.bfd 包装器）
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

**Rust 扩展额外需要**：
```bash
# Cargo 链接器配置（HarmonyOS 没有 'cc'）
export RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"
```

或添加到 `.cargo/config.toml`：
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
```

**构建系统约束**：
- 并行构建使用 **Ninja**（`make -j` 失败，因为 `mkfifo` 返回 EPERM）
- 不要将 `CMAKE_TOOLCHAIN_FILE` 与 `CMAKE_SYSTEM_NAME` 一起使用 —— 会触发交叉编译模式导致 `try_run()` 失败

## 阶段 3：编译与安装

### 策略 A：直接 pip install（简单 C/C++ 扩展）

对于 numpy、bcrypt、greenlet 等扩展自包含的包：

```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
TMPDIR=$HOME/Claude/tmpdir \
pip install <package>
```

如果 pip 找不到兼容的 wheel，它将从源码构建。CC/CXX 环境变量确保使用 clang 而非缺失的 gcc。

### 策略 B：Wheel 平台标签重命名（numpy 模式）

某些包提供了 wheel 但平台标签不兼容。重命名 wheel：

```bash
# 下载 wheel
pip download numpy

# 重命名平台标签
mv numpy-2.x-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl \
   numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl

# 安装重命名后的 wheel
pip install numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl
```

### 策略 C：先编译 C 依赖（pillow/lxml 模式）

对于依赖 HarmonyOS 上不可用的外部 C 库的包：

```bash
# 步骤 1：编译 C 依赖（示例：pillow 的 libjpeg-turbo）
mkdir -p $HOME/Claude/tmpdir
cd libjpeg-turbo-3.0.4
cmake -GNinja \
  -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
  -DCMAKE_C_FLAGS="-B$HOME/Claude/lib/linker_wrapper" \
  -DCMAKE_INSTALL_PREFIX=$HOME/.local \
  -DENABLE_SHARED=ON \
  -DWITH_SIMD=ON \
  ..
ninja && ninja install

# 步骤 2：签名编译后的 .so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/libjpeg.so -outFile $HOME/.local/lib/libjpeg.so.signed
mv $HOME/.local/lib/libjpeg.so.signed $HOME/.local/lib/libjpeg.so

# 步骤 3：pip install Python 包（通过 LD_LIBRARY_PATH 找到 C 库）
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
pip install pillow
```

### 策略 D：Rust 扩展（maturin 直接构建）

**关键**：在 HarmonyOS 上，pip 的构建隔离会破坏 maturin。maturin 构建后端使用 HNP 系统 Python（`/data/service/hnp/python.org/python_3.12/bin/python3.12`），它没有 sitecustomize.py 补丁，导致 maturin 平台检查失败。必须直接用 maturin 构建。

```bash
# 步骤 1：通过 cargo 安装 maturin
CC=/data/service/hnp/bin/clang \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
CARGO_HOME=$HOME/.rust \
cargo install maturin

# 步骤 2：签名 maturin 二进制文件
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/maturin \
  -outFile $HOME/.local/bin/maturin.signed -signAlg SHA256withECDSA
mv $HOME/.local/bin/maturin.signed $HOME/.local/bin/maturin

# 步骤 3：修复 platform.system() 不匹配（maturin 拒绝 "HarmonyOS" 而 Rust 是 "Linux"）
# 这由 sitecustomize.py 补丁处理（已安装）

# 步骤 4：直接用 maturin 构建（不是 pip install）
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-B$HOME/Claude/lib/linker_wrapper" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# 对于需要 OpenSSL 的包：
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L/usr/lib -L$HOME/.local/lib" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# 对于 tokenizers，添加 fancy-regex feature：
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3 --features fancy-regex
```

**HarmonyOS 上 Rust 扩展的关键问题**：
1. **maturin 平台检查**：maturin 比较 `platform.system()`（返回 "HarmonyOS"）与 Rust 目标 OS（"Linux"）并拒绝不匹配。通过 sitecustomize.py 补丁修复。
2. **pip 构建隔离**：pip 的隔离构建环境不继承 RUSTFLAGS、CC、LD_LIBRARY_PATH。必须直接用 maturin 构建。
3. **cargo 链接器**：HarmonyOS 没有 `cc` 命令；必须设置 `RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"`。
4. **OpenSSL 开发文件**：系统有 libssl.so.3/libcrypto.so.3 但没有头文件/pkg-config。需要手动下载头文件并创建 pkg-config 文件。
5. **构建脚本签名循环**：有 Cargo 构建脚本的包（orjson、tokenizers、safetensors）需要 rustc 自动签名包装器 —— 参见 [rustc-wrapper.md](rustc-wrapper.md)。
6. **abi3 wheel**：某些 Rust/PyO3 包（tokenizers、safetensors）生成带 `.abi3.so` 后缀的 abi3 wheel，不需要重命名为 `.cpython-312-aarch64-linux-gnu.so`。
7. **fancy-regex feature**：tokenizers 需要 `onig` 或 `fancy-regex` 之一。onig（C oniguruma 库）在 HarmonyOS 上无法编译。使用 `fancy-regex` 替代：`maturin build --features fancy-regex`。

### .so 后缀修复

pip install 后，扩展模块可能有错误的后缀。我们的 Python 期望 `.cpython-312-aarch64-linux-gnu.so`：

```bash
cd $HOME/.local/lib/python3.12/site-packages/<package>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

**注意**：abi3 wheel 使用 `.abi3.so` 后缀，兼容所有 Python 3.x 版本 —— 无需重命名。

## 阶段 4：代码签名与 Patchelf 修复（最关键）

这是大多数适配失败的阶段。所有 `.so` 文件必须签名且可能需要 patchelf 修复。

### 步骤 4.1：批量代码签名

```bash
SIGN_DIR=$HOME/.local/lib/python3.12/site-packages/<package>

# 先删除过期的 .codesign 节（防止签名失败）
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
  done
' sh {} +

# 签名所有 .so 文件
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +
```

### 步骤 4.2：Patchelf NEEDED 路径前缀修复

如果包是用 Ninja/CMake 构建的，其 `.so` 文件可能有带 `lib/` 前缀的 NEEDED 条目：

**诊断**：
```bash
/data/service/hnp/bin/llvm-readelf -d <package>.so | grep NEEDED
# 如果看到 "lib/libtorch_cpu.so" 而不是 "libtorch_cpu.so"，需要修复
```

**修复**：
```bash
/data/service/hnp/bin/patchelf --replace-needed lib/libfoo.so libfoo.so "$f"
/data/service/hnp/bin/patchelf --set-rpath '$ORIGIN:$HOME/.local/lib' "$f"
```

### 步骤 4.3：Patchelf --add-needed 修复隐藏符号

如果包用 `-fvisibility=hidden` 编译，某些符号可能缺失：

**诊断**：
```bash
/data/service/hnp/bin/llvm-nm -D <main_lib>.so | grep "<missing_symbol>"
```

**修复**（来自 PyTorch 适配的 supplement.so 模式）：
```bash
# 1. 创建桩实现
cat > supplement.c << 'EOF'
void missing_symbol_1() {}
void missing_symbol_2() {}
EOF

# 2. 编译 supplement .so
/data/service/hnp/bin/clang -B$HOME/Claude/lib/linker_wrapper -shared \
  -o lib<package>_supplement.so supplement.c

# 3. 添加为 NEEDED 依赖
/data/service/hnp/bin/patchelf --add-needed lib<package>_supplement.so <main_lib>.so

# 4. 签名两者
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile lib<package>_supplement.so -outFile signed && mv signed lib<package>_supplement.so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <main_lib>.so -outFile signed && mv signed <main_lib>.so
```

### 步骤 4.4：Rust/PyO3 构建脚本签名循环

参见专门指南：[rustc-wrapper.md](rustc-wrapper.md)

### 步骤 4.5：C++ 扩展 Patchelf-Sign 工作流（libc++_shared.so）

C++ 扩展包需要 `libc++_shared.so` 提供 C++ 运行时符号。然而，`patchelf` 无法修改已签名的 .so 文件。

**工作流**：剥离 codesign → patchelf → 重新签名 → 重命名后缀

```bash
SIGN_DIR=$HOME/.local/lib/python3.12/site-packages/<package>

# 步骤 1：剥离 .codesign 节（patchelf 需要未签名的 ELF）
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
  done
' sh {} +

# 步骤 2：添加 libc++_shared.so 为 NEEDED 依赖
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
  done
' sh {} +

# 步骤 3：重新签名所有 .so 文件
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA
    mv "${f}.signed" "$f"
  done
' sh {} +

# 步骤 4：重命名后缀
cd "$SIGN_DIR"
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

**关键点**：顺序很重要 —— `llvm-objcopy --remove-section .codesign` 必须在 `patchelf` 之前，`binary-sign-tool sign` 必须在 patchelf 之后。

### 步骤 4.6：cffi 重建（带 LDFLAGS 指定 libffi 路径）

cffi 2.0.0 构建时需要 `libffi.so.8`。在 HarmonyOS 上，libffi 位于 `$HOME/.local/lib/libffi.so.8`（从源码编译）。

```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
LDFLAGS="-L$HOME/.local/lib -L/usr/lib -B$HOME/Claude/lib/linker_wrapper" \
TMPDIR=$HOME/Claude/tmpdir \
pip install cffi --no-binary :all:

# 安装后：签名 _cffi_backend.so 并重命名后缀
cd $HOME/.local/lib/python3.12/site-packages/_cffi_backend*
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile _cffi_backend.cpython-312.so \
  -outFile _cffi_backend.cpython-312.so.signed -signAlg SHA256withECDSA
mv _cffi_backend.cpython-312.so.signed _cffi_backend.cpython-312-aarch64-linux-gnu.so
```

### 步骤 4.7：asyncio.current_task 段错误修复

`asyncio.current_task()` 在 HarmonyOS 上于异步上下文之外调用时会段错误。这影响任何使用 Python logging 模块并启用 asyncio 任务跟踪的包（structlog 等）。

**诊断**：导入时崩溃并出现段错误（无 Python 回溯）。崩溃发生在 `logging/__init__.py` 约第 375 行，那里调用了 `self.taskName = asyncio.current_task().get_name()`。

**修复**：
```bash
# 补丁 logging/__init__.py：将 logAsyncioTasks 从 True 改为 False
sed -i 's/logAsyncioTasks = True/logAsyncioTasks = False/' \
  $HOME/.local/lib/python3.12/logging/__init__.py

# 同时在 sitecustomize.py 中添加 sys._logAsyncioTasks = False
echo '' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
echo '# Disable asyncio task tracking in logging to avoid crash on HarmonyOS' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
echo 'sys._logAsyncioTasks = False' >> $HOME/.local/lib/python3.12/site-packages/sitecustomize.py
```

**何时应用**：如果任何包在导入时段错误崩溃且无 Python 回溯，检查它是否使用 `logging` + `asyncio`。这是一个系统级修复。

## 阶段 5：验证与运行

### 步骤 5.1：将依赖库添加到 LD_LIBRARY_PATH

```bash
# 对于有编译 C 依赖的包
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# 对于 .so 在非标准位置的包（例如 PyTorch）
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/<package>/lib:$LD_LIBRARY_PATH
```

### 步骤 5.2：导入测试

```bash
python3 -c "import <package>; print('<package> imported successfully')"
```

### 常见错误诊断

| Error | Cause | Fix |
|-------|-------|-----|
| `ImportError: dynamic module does not define module export function` | .so 后缀不匹配 | 重命名为 `.cpython-312-aarch64-linux-gnu.so` |
| `OSError: <package>.so: cannot open shared object file` | 缺失 NEEDED 库 / 错误 RPATH | 添加库到 LD_LIBRARY_PATH 或 `patchelf --set-rpath` |
| `Symbol not found: decref/incref/invoke_parallel` | `-fvisibility=hidden` 隐藏符号 | 创建 supplement.so，`patchelf --add-needed` |
| `Error loading shared library lib/libfoo.so` | NEEDED 有 `lib/` 前缀 | `patchelf --replace-needed lib/libfoo.so libfoo.so` |
| `cc: command not found` / `c++: command not found` | 系统没有 gcc | 设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` |
| `Operation not permitted` (mkfifo) | make -j 在 HarmonyOS 上失败 | 使用 Ninja 替代 |
| `unittest.SkipTest: cannot load extension module` | .so 未签名 | `binary-sign-tool sign -selfSign 1` |
| `undefined symbol: PyFloat_FromDouble` | 系统 Python 是静态链接的 | 使用我们位于 `$HOME/.local/bin/python3` 的 `-rdynamic` Python |
| `don't match ಠ_ಠ` (maturin) | platform.system() 返回 "HarmonyOS" | sitecustomize.py 补丁或 maturin 直接构建 |
| `Package openssl was not found` (pkg-config) | 系统没有 openssl.pc | 在 $HOME/.local/lib/pkgconfig 创建 pkg-config 文件 |
| `ld.lld: error: unable to find library -lssl` | 链接器找不到 libssl.so | 添加 `-C link-args=-L/usr/lib` 到 RUSTFLAGS + 创建无版本号符号链接 |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so 后缀不匹配或未签名 | 重命名 + 签名 |
| `platform harmonyosHongMengKernel1 is not supported` | sys.platform 未被识别 | 补丁平台检测将其视为 Linux |
| `redefinition of 'sockaddr_storage'` | linux/socket.h 和 sys/socket.h 中结构体重复 | `#define sockaddr_storage __guard` 在 `#include <linux/if.h>` 之前，然后 `#undef` |
| `Could not invoke sanity check executable: Permission denied` | Meson 构建中间产物未签名 | 创建自动签名 clang 包装器 |
| `.whl is not a supported wheel on this platform` | Wheel 文件名中平台标签有空格 | 手动安装到 site-packages |
| `gfortran: command not found` | HarmonyOS 没有 Fortran 编译器 | 无法构建 scipy 或其他 Fortran 包 |
| `.so crashes with no error / ImportError after signing` | C++ 扩展需要 libc++_shared.so | `patchelf --add-needed libc++_shared.so` |
| `Segfault on import (no Python traceback)` | asyncio.current_task() 在异步上下文外崩溃 | 补丁 logging/__init__.py + sitecustomize.py |
| `-lffi: No such file or directory` | 链接器找不到 libffi.so.8 | 构建 cffi 时添加 `LDFLAGS="-L$HOME/.local/lib"` |
| `patchelf: Operation not permitted` on .so | patchelf 无法修改已签名的 .so | 先剥离 codesign：`llvm-objcopy --remove-section=.codesign` → patchelf → 重新签名 |
| `_ZdlPv: symbol not found` / `operator delete` | C++ 扩展缺失 libc++_shared.so | `patchelf --add-needed libc++_shared.so`（使用步骤 4.5 工作流） |
| `pybind11 pkg-config not found` | matplotlib 构建需要 pybind11 pkgconfig | 添加 pybind11 share/pkgconfig 到 PKG_CONFIG_PATH |

## 按难度分类的适配示例

### 简单：简单 C 扩展（bcrypt, greenlet）

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export TMPDIR=$HOME/Claude/tmpdir
pip install bcrypt
# 查找并签名 .so
find ~/.local/lib/python3.12/site-packages/bcrypt -name "*.so" | \
  xargs -I{} /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile {} -outFile {}.s && \
  find ~/.local/lib/python3.12/site-packages/bcrypt -name "*.so.s" | \
  while read f; do mv "$f" "${f%.s}"; done
python3 -c "import bcrypt; print(bcrypt.hashpw('test', bcrypt.gensalt()))"
```

### 中等：有 C 依赖的包（pillow, lxml）

1. 从源码编译 C 依赖（libjpeg-turbo、libxml2 等）
2. 签名编译后的 .so
3. 设置 CC/CXX 后 `pip install` Python 包
4. 如需要，修复 .so 后缀
5. 签名所有包的 .so 文件
6. 将 `$HOME/.local/lib` 添加到 LD_LIBRARY_PATH

### 中等：平台检测补丁（psutil）

psutil 使用 `sys.platform.startswith("linux")` 检测 Linux。HarmonyOS 返回 `"harmonyos"`，不匹配。

1. 下载源码：`pip download psutil --no-binary :all:`
2. 补丁 `_common.py`：`LINUX = sys.platform.startswith("linux") or sys.platform.startswith("harmonyos")`
3. 补丁 `psutil/arch/linux/net.c`：防护 sockaddr_storage 重定义：
   ```c
   #define sockaddr_storage __harmonyos_sockaddr_storage
   #include <linux/if.h>
   #undef sockaddr_storage
   ```
4. 构建：`CC=/data/service/hnp/bin/clang CFLAGS="-B$HOME/Claude/lib/linker_wrapper" python3 setup.py build`
5. 安装：`python3 setup.py install --skip-build`
6. 签名所有 .abi3.so 文件

### 中等：通过 maturin 直接构建 Rust 扩展（pydantic v2）

参见阶段 3 的策略 D。要点：
- 直接用 `maturin build --release --interpreter $HOME/.local/bin/python3` 构建 pydantic-core
- 签名 .so，将后缀重命名为 `.cpython-312-aarch64-linux-gnu.so`
- 修复 WHEEL 平台标签（空格 → 下划线）
- 手动安装到 site-packages
- 然后 `pip install pydantic fastapi --no-deps`

### 困难：有构建脚本签名循环的 Rust 扩展（orjson）

使用 rustc 自动签名包装器 —— 参见 [rustc-wrapper.md](rustc-wrapper.md)。orjson 特定的额外步骤：预编译 yyjson.c 为 `libyyjson.a` 并从 Cargo.toml 中移除 `cc` crate 依赖。

### 中等：Meson 构建（pandas, matplotlib）

参见 [meson-wrapper.md](meson-wrapper.md) 了解自动签名 clang 包装器技术。

### 困难：复杂 C++ 框架（PyTorch）

参见 [pytorch-harmonyos.md](../pytorch-harmonyos.md) 了解完整的 15 步适配指南。

## 关键规则总结

1. **所有 `.so` 文件必须签名** —— 未签名的 .so 会使 Python 崩溃且无错误信息
2. **始终设置 CC/CXX** —— HarmonyOS 没有 gcc，只有 clang
3. **始终设置 TMPDIR** —— `/tmp` 是只读的
4. **始终为 C++ 编译添加 `-B$HOME/Claude/lib/linker_wrapper`** —— SDK lld 是坏的
5. **检查 .so 后缀** —— 必须是 `.cpython-312-aarch64-linux-gnu.so`（abi3 wheel 使用 `.abi3.so`）
6. **用 `llvm-readelf -d` 检查 NEEDED 条目** —— 用 patchelf 修复 `lib/` 前缀
7. **用 `llvm-nm -D` 检查符号可见性** —— 用 supplement.so 修复隐藏符号
8. **使用 Ninja，不用 make -j** —— mkfifo 在 HarmonyOS 上返回 EPERM
9. **使用我们的 `-rdynamic` Python** —— 系统 Python 是静态链接的，无法加载 .so 扩展