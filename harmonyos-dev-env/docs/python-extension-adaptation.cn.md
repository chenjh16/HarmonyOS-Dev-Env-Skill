# HarmonyOS Python 扩展模块适配指南

本指南提供了一套通用的、面向 Agent 的方法论，用于适配在 HarmonyOS 上包含 C、C++ 或 Rust 扩展（`.so` 动态库）的 Python 包。它提炼了我们适配 numpy、pillow、lxml、bcrypt、greenlet 和 PyTorch 的经验模式。

纯 Python 包（requests、flask、jinja2 等）无需适配——直接 `pip install` 即可。本指南仅覆盖包含原生扩展的包。

## 阶段 1: 判断包类型

开始前，先判断包属于哪个类别：

| 类型 | 判断方法 | 示例 | 适配难度 |
|------|----------|------|----------|
| 纯 Python | wheel 中无 `.so`，无编译步骤 | requests, flask | 无——直接 pip install |
| C/C++ 扩展 | `setup.py` 有 `ext_modules`，或 wheel 包含 `.so` | numpy, greenlet, cffi | 中——设置 CC/CXX，签名 .so |
| 混合依赖（C 库 + Python 绑定） | 需要外部 C 库 | pillow (libjpeg), lxml (libxml2) | 高——需先编译 C 依赖 |
| Rust 扩展 (PyO3) | 有 `Cargo.toml`，使用 maturin | bcrypt, cryptography | 中高——Rust 工具链 + CC |

**快速判断**: 查看 PyPI 页面或 GitHub 仓库。如果有 `setup.py` 的 `Extension()` 调用、`Cargo.toml`，或 wheel 中有 `.so` 文件，就需要适配。

## 阶段 2: 准备构建环境

所有扩展构建都需要这些环境变量：

```bash
# 所有 C/C++ 扩展构建必须设置
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++

# HarmonyOS 必须设置（/tmp 只读）
export TMPDIR=$HOME/Claude/tmpdir

# C++ 构建必须设置（SDK lld 损坏，必须使用 ld.bfd 封装）
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"
```

**Rust 扩展还需**:
```bash
# Cargo 链接器配置（HarmonyOS 上没有 cc）
export RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"
```

或在 `.cargo/config.toml` 中添加：
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
```

**构建系统约束**:
- 使用 **Ninja** 进行并行构建（`make -j` 因 `mkfifo` 返回 EPERM 而失败）
- 不要将 `CMAKE_TOOLCHAIN_FILE` 配合 `CMAKE_SYSTEM_NAME` 使用——会触发交叉编译模式导致 `try_run()` 失败

## 阶段 3: 编译安装

### 策略 A: 直接 pip install（简单 C/C++ 扩展）

适用于 numpy、bcrypt、greenlet 等扩展自包含的包：

```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
TMPDIR=$HOME/Claude/tmpdir \
pip install <包名>
```

如果 pip 找不到兼容的 wheel，它会从源码构建。CC/CXX 环境变量确保使用 clang 而非缺失的 gcc。

### 策略 B: Wheel 平台标签重命名（numpy 模式）

部分包提供 wheel 但平台标签不兼容。重命名 wheel：

```bash
# 下载 wheel
pip download numpy

# 重命名平台标签
mv numpy-2.x-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl \
   numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl

# 安装重命名后的 wheel
pip install numpy-2.x-cp312-cp312-harmonyos_hongmeng_kernel_1_12_0_aarch64.whl
```

### 策略 C: 先编译 C 依赖库（pillow/lxml 模式）

适用于依赖 HarmonyOS 上不存在的 C 库的包：

```bash
# 步骤 1: 编译 C 依赖（示例：pillow 的 libjpeg-turbo）
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

# 步骤 2: 签名编译的 .so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/lib/libjpeg.so -outFile $HOME/.local/lib/libjpeg.so.signed
mv $HOME/.local/lib/libjpeg.so.signed $HOME/.local/lib/libjpeg.so

# 步骤 3: pip install Python 包（通过 LD_LIBRARY_PATH 找到 C 库）
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ \
pip install pillow
```

### 策略 D: Rust 扩展（maturin 构建）

适用于 PyO3 架构的包：

```bash
# 安装 maturin
pip install maturin

# 构建 wheel
maturin build --release --target aarch64-unknown-linux-ohos \
  --cargo-flags="-C linker=/data/service/hnp/bin/clang"

# 安装构建的 wheel
pip install target/wheels/<包名>-*.whl
```

### .so 后缀修复

pip install 后，扩展模块可能后缀不正确。我们的 Python 需要 `.cpython-312-aarch64-linux-gnu.so`：

```bash
cd $HOME/.local/lib/python3.12/site-packages/<包名>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```

## 阶段 4: 代码签名与 Patchelf 修复（最关键）

这是大多数适配失败的阶段。所有 `.so` 文件必须签名，且可能需要 patchelf 修复。

### 步骤 4.1: 批量代码签名

查找并签名包目录中的所有 .so 文件：

```bash
SIGN_DIR=$HOME/.local/lib/python3.12/site-packages/<包名>

# 先清除残留的 .codesign 段（防止签名失败）
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

# 同时签名编译的 C 依赖库
find "$HOME/.local/lib" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
      -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +
```

### 步骤 4.2: Patchelf NEEDED 路径前缀修复

如果包用 Ninja/CMake 构建，其 `.so` 文件的 NEEDED 条目可能带有 `lib/` 前缀（如 `lib/libfoo.so` 而非 `libfoo.so`）。动态链接器将找不到这些。

**诊断**:
```bash
/data/service/hnp/bin/llvm-readelf -d <包名>.so | grep NEEDED
# 如果看到 "lib/libtorch_cpu.so" 这样的条目而非 "libtorch_cpu.so"，需要修复
```

**修复**:
```bash
find "$SIGN_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    # 去除 NEEDED 条目的 "lib/" 前缀
    /data/service/hnp/bin/patchelf --replace-needed lib/libfoo.so libfoo.so "$f"
    # 设置 RUNPATH 使链接器能找到依赖
    /data/service/hnp/bin/patchelf --set-rpath '\''$ORIGIN:$HOME/.local/lib'\'' "$f"
  done
' sh {} +
```

### 步骤 4.3: Patchelf —add-needed 补充隐藏符号

如果包使用 `-fvisibility=hidden` 编译，某些其他 `.so` 依赖的符号可能从动态符号表中消失。

**诊断**:
```bash
/data/service/hnp/bin/llvm-nm -D <主库>.so | grep "<缺失符号>"
# 如果期望的符号不在，需要补充库
```

**修复**（supplement.so 模式，来自 PyTorch 适配）:
```bash
# 1. 创建缺失符号的 stub 实现
cat > supplement.c << 'EOF'
void missing_symbol_1() {}
void missing_symbol_2() {}
EOF

# 2. 编译补充 .so
/data/service/hnp/bin/clang -B$HOME/Claude/lib/linker_wrapper -shared \
  -o lib<包名>_supplement.so supplement.c

# 3. 添加为 NEEDED 依赖
/data/service/hnp/bin/patchelf --add-needed lib<包名>_supplement.so <主库>.so

# 4. 签名两个文件
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile lib<包名>_supplement.so -outFile signed && mv signed lib<包名>_supplement.so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <主库>.so -outFile signed && mv signed <主库>.so
```

## 阶段 5: 验证运行

### 步骤 5.1: 添加依赖库路径到 LD_LIBRARY_PATH

```bash
# 对于有编译 C 依赖的包
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# 对于 .so 在非标准路径的包（如 PyTorch）
export LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/<包名>/lib:$LD_LIBRARY_PATH
```

### 步骤 5.2: 导入测试

```bash
python3 -c "import <包名>; print('<包名> 导入成功')"
```

### 常见错误诊断表

| 错误 | 原因 | 修复 |
|------|------|------|
| `ImportError: dynamic module does not define module export function` | .so 后缀不匹配 | 重命名为 `.cpython-312-aarch64-linux-gnu.so` |
| `OSError: <包名>.so: cannot open shared object file` | 缺少 NEEDED 库 / RPATH 错误 | 添加 lib 到 LD_LIBRARY_PATH 或 `patchelf --set-rpath` |
| `Symbol not found: decref/incref/invoke_parallel` | `-fvisibility=hidden` 隐藏符号 | 创建 supplement.so，`patchelf --add-needed` |
| `Error loading shared library lib/libfoo.so` | NEEDED 带 `lib/` 前缀 | `patchelf --replace-needed lib/libfoo.so libfoo.so` |
| `cc: command not found` / `c++: command not found` | 系统无 gcc | 设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` |
| `Operation not permitted` (mkfifo) | HarmonyOS 上 make -j 失败 | 使用 Ninja |
| `.so 加载失败 / 无错误信息崩溃` | .so 未签名 | `binary-sign-tool sign -selfSign 1` |
| `undefined symbol: PyFloat_FromDouble` | 系统 Python 静态链接 | 使用 `-rdynamic` Python（`$HOME/.local/bin/python3`） |

## 按难度分类的适配示例

### 简单：纯 C 扩展（bcrypt, greenlet）

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

1. 从源码编译 C 依赖（libjpeg-turbo, libxml2 等）
2. 签名编译的 .so
3. 设置 CC/CXX 后 `pip install` Python 包
4. 修复 .so 后缀（如需要）
5. 签名所有包 .so 文件
6. 将 `$HOME/.local/lib` 添加到 LD_LIBRARY_PATH

### 困难：复杂 C++ 框架（PyTorch）

1. 使用 CMake + Ninja 构建（不用 make -j）
2. 使用轻量级工具链文件（无 CMAKE_SYSTEM_NAME）
3. 修复所有 5 个 patchelf 问题：NEEDED 前缀、RPATH、隐藏符号（supplement.so）
4. 批量签名所有 .so 文件（包括构建工具如 protoc）
5. 为 torch/lib 设置 LD_LIBRARY_PATH

## 关键规则总结

1. **所有 `.so` 文件必须签名**——未签名的 .so 会导致 Python 崩溃且无错误信息
2. **始终设置 CC/CXX**——HarmonyOS 没有 gcc，只有 clang
3. **始终设置 TMPDIR**——`/tmp` 是只读的
4. **C++ 编译始终添加 `-B$HOME/Claude/lib/linker_wrapper`**——SDK lld 损坏
5. **检查 .so 后缀**——必须是 `.cpython-312-aarch64-linux-gnu.so`
6. **用 `llvm-readelf -d` 检查 NEEDED 条目**——用 patchelf 修复 `lib/` 前缀
7. **用 `llvm-nm -D` 检查符号可见性**——用 supplement.so 修复隐藏符号
8. **使用 Ninja，不用 make -j**——HarmonyOS 上 mkfifo 返回 EPERM
9. **使用 `-rdynamic` Python**——系统 Python 静态链接，无法加载 .so 扩展