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
| Rust 扩展 (PyO3) | 有 `Cargo.toml`，使用 maturin | bcrypt, cryptography, orjson | 中高——Rust 工具链 + CC |
| Meson 构建 | 有 `meson.build`，使用 meson-python | pandas, matplotlib | 高——自动签名 wrapper + mesonpy API |

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

适用于 PyO3 架构的包（bcrypt、cryptography 等）：

```bash
# 步骤 1: 通过 cargo 安装 maturin
CC=/data/service/hnp/bin/clang \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
CARGO_HOME=$HOME/.rust \
cargo install maturin

# 步骤 2: 签名 maturin 二进制
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile $HOME/.local/bin/maturin \
  -outFile $HOME/.local/bin/maturin.signed -signAlg SHA256withECDSA
mv $HOME/.local/bin/maturin.signed $HOME/.local/bin/maturin

# 步骤 3: 修复 platform.system() 不匹配（maturin 拒绝 "HarmonyOS" vs Rust "Linux"）
# 创建 sitecustomize.py 补丁 platform.system()
cat > $HOME/.local/lib/python3.12/site-packages/sitecustomize.py << 'EOF'
import platform
_original_system = platform.system
def _patched_system():
    result = _original_system()
    if result == "HarmonyOS":
        return "Linux"
    return result
platform.system = _patched_system
EOF

# 步骤 4: 使用 --no-build-isolation 安装（pip 隔离环境不继承 RUSTFLAGS/CC）
TMPDIR=$HOME/Claude/tmpdir \
CC=/data/service/hnp/bin/clang \
CXX=/data/service/hnp/bin/clang++ \
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -I$HOME/.local/include" \
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L$HOME/.local/lib" \
LD_LIBRARY_PATH="/usr/lib:$HOME/.local/lib:$HOME/.rust/lib:/system/lib64:$LD_LIBRARY_PATH" \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" \
pip install <包名> --no-build-isolation
```

对于还需要 OpenSSL 的包（如 cryptography），添加额外的链接器路径：

```bash
# OpenSSL 依赖的 Rust 包需要额外参数
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper -L/usr/lib -L$HOME/.local/lib" \
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-args=-L/usr/lib -C link-args=-L$HOME/.local/lib" \
PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig" \
```

**HarmonyOS 上 Rust 扩展的关键问题**:
1. **maturin 平台检查**: maturin 比较 `platform.system()`（返回 "HarmonyOS"）与 Rust target OS（"Linux"），不匹配时拒绝构建。用 sitecustomize.py 补丁修复。
2. **pip 构建隔离**: pip 的隔离构建环境不继承 RUSTFLAGS、CC、LD_LIBRARY_PATH。必须使用 `--no-build-isolation`。
3. **cargo 链接器**: HarmonyOS 没有 `cc` 命令；必须设置 `RUSTFLAGS="-C linker=/data/service/hnp/bin/clang"`。
4. **OpenSSL 开发文件**: 系统有 libssl.so.3/libcrypto.so.3 但无头文件/pkg-config。需手动下载头文件并创建 pkg-config 文件。

完整工作示例见 [cryptography-harmonyos.cn.md](cryptography-harmonyos.cn.md)。

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
| `don't match ಠ_ಠ`（maturin） | platform.system() 返回 "HarmonyOS" vs Rust target "Linux" | 创建 sitecustomize.py 补丁 platform.system() |
| `Package openssl was not found`（pkg-config） | 系统无 openssl.pc | 创建 $HOME/.local/lib/pkgconfig/ 下的 pkg-config 文件 |
| `ld.lld: error: unable to find library -lssl` | 链接器找不到 libssl.so | RUSTFLAGS 添加 `-C link-args=-L/usr/lib` + 创建无版本号符号链接 |
| `ModuleNotFoundError: No module named '_cffi_backend'` | .so 后缀不匹配或未签名 | 重命名为 `.cpython-312-aarch64-linux-gnu.so` + 签名 |
| `platform harmonyosHongMengKernel1 is not supported` | sys.platform 不被识别 | 修补平台检测（如 `sys.platform.startswith("harmonyos")` → 视为 Linux） |
| `redefinition of 'sockaddr_storage'` | HarmonyOS SDK 在 linux/socket.h 和 sys/socket.h 中有重复定义 | 在 `#include <linux/if.h>` 前 `#define sockaddr_storage __guard`，然后 `#undef` |
| `Could not invoke sanity check executable: Permission denied` | Meson 构建中间文件未签名 | 创建自动签名 clang 包装器，PIE 可执行文件也需签名 |
| `maturin: platform.system() don't match ಠ_ಠ` | maturin 检测到 HarmonyOS vs Rust Linux target | sitecustomize.py 补丁或直接用 `maturin build` 构建 |
| `.whl is not a supported wheel on this platform` | wheel 文件名中平台标签含空格 | 手动安装到 site-packages |
| `No module named 'typing_inspection'` | 缺少依赖 | `pip install typing_inspection --no-deps` |
| `gfortran: command not found` | HarmonyOS 无 Fortran 编译器 | 无法构建 scipy 或其他依赖 Fortran 的包 |
| `uvloop/libuv configure: cannot guess platform` | libuv autoconf 无法检测 HarmonyOS | 无法构建 uvloop；musl libc 缺少 cpu_set_t、CPU_SETSIZE、mmsghdr |
| `.so 签名后仍崩溃 / ImportError 无错误信息` | C++ 扩展需要 libc++_shared.so | 对所有 .so 文件执行 `patchelf --add-needed libc++_shared.so` |
| `pybind11 pkg-config 未找到` | matplotlib 构建需要 pybind11 pkgconfig | 将 `$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig` 加入 PKG_CONFIG_PATH |

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

### 困难：带 C 依赖的 Rust 扩展（cryptography）

1. 从源码编译 libffi（无 autotools，处理 FFI_HIDDEN C/汇编分离，删除 memcpy→bcopy 宏）
2. 安装 cffi（签名 + 重命名 .so 后缀）
3. cargo install maturin（签名二进制）
4. 通过 sitecustomize.py 修复 maturin platform.system() 检查
5. 下载 OpenSSL 头文件 + 创建 pkg-config 文件 + 无版本号符号链接
6. 使用 --no-build-isolation 和完整环境变量（CC、RUSTFLAGS、PKG_CONFIG_PATH、LDFLAGS 含 -L/usr/lib）pip install cryptography
7. 签名 cryptography .so 扩展

完整细节见 [cryptography-harmonyos.cn.md](cryptography-harmonyos.cn.md)。

### 中等：平台检测补丁（psutil）

psutil 使用 `sys.platform.startswith("linux")` 来检测 Linux。HarmonyOS 返回 `"harmonyos"`，不匹配。

1. 下载源码：`pip download psutil --no-binary :all:`
2. 修补 `_common.py`：将 `LINUX = sys.platform.startswith("linux")` 改为 `LINUX = sys.platform.startswith("linux") or sys.platform.startswith("harmonyos")`
3. 修补 `psutil/arch/linux/net.c`：在 `#include <linux/if.h>` 前用 #define 防止 `sockaddr_storage` 重定义冲突：
   ```c
   #define sockaddr_storage __harmonyos_sockaddr_storage
   #include <linux/if.h>
   #undef sockaddr_storage
   ```
   （HarmonyOS SDK 在 `sys/socket.h` 和 `linux/socket.h` 中都定义了 `struct sockaddr_storage`，当 `linux/if.h` 包含 `linux/socket.h` 时导致重定义错误）
4. 构建：`CC=/data/service/hnp/bin/clang CFLAGS="-B$HOME/Claude/lib/linker_wrapper" python3 setup.py build`
5. 安装：`python3 setup.py install --skip-build`
6. 如需要，手动复制 Python 文件：`cp -r psutil/*.py $HOME/.local/lib/python3.12/site-packages/psutil/`
7. 签名包目录中所有 .abi3.so 文件

### 中等：Rust 扩展 maturin 直接构建（pydantic v2）

pip 的构建隔离会破坏 HarmonyOS 上的 maturin（不继承 CC/RUSTFLAGS）。直接用 maturin 构建 pydantic-core。

1. 下载源码并解压
2. 直接用 maturin 构建：`maturin build --release --interpreter $HOME/.local/bin/python3`
3. 提取 wheel，签名 .so，重命名后缀：`.cpython-312.so` → `.cpython-312-aarch64-linux-gnu.so`
4. 修复 WHEEL 文件的平台标签（将空格替换为下划线）
5. 手动安装到 site-packages（pip 无法安装 HarmonyOS 标签的 wheel）
6. 安装 pydantic 和 fastapi：`pip install pydantic fastapi --no-deps`

**关键洞察**：maturin 生成 `.cpython-312.so` 后缀，但 HarmonyOS Python 期望 `.cpython-312-aarch64-linux-gnu.so`。必须在签名后重命名。另外 maturin wheel 文件名中的平台标签含空格——pip 会拒绝。需要手动安装。

### 中等：Rust 序列化 maturin 直接构建（orjson）

orjson 是高性能 JSON 序列化库，基于 Rust/PyO3 构建。构建模式与 pydantic-core 相同。

1. 下载源码：`pip download orjson --no-binary :all:`
2. 直接用 maturin 构建：`maturin build --release --interpreter $HOME/.local/bin/python3`
3. 提取 wheel，签名 .so，重命名后缀：`.cpython-312.so` → `.cpython-312-aarch64-linux-gnu.so`
4. 修复 WHEEL 文件的平台标签（将空格替换为下划线）
5. 手动安装到 site-packages（pip 无法安装 HarmonyOS 标签的 wheel）

**e2e 测试结果（7/7）**：基础序列化、datetime、numpy 数组、UTF-8、UUID、排序键+美化打印、性能对比。

**关键洞察**：与 pydantic-core 相同的 maturin 模式——.so 后缀重命名 + WHEEL 标签修复 + 手动安装。不需要额外的 C 依赖。

### 中等：Meson 构建自动签名包装器（pandas）

Meson 构建需要在配置阶段执行 sanity check 二进制文件。在 HarmonyOS 上，未签名的二进制无法执行。

1. 在 `$HOME/Claude/lib/meson_wrapper/clang` 创建自动签名 clang 包装器：
   ```bash
   #!/bin/sh
   REAL_CC=/data/service/hnp/bin/clang
   SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool
   TMPDIR="$HOME/Claude/tmpdir"
   # 从命令行解析 -o 参数
   OUTPUT_FILE="" # ... 解析逻辑 ...
   $REAL_CC "$@"
   # 如果输出是 ELF 且不是 .o/.so/.a，自动签名
   # 注意：PIE 可执行文件的 Type 是 DYN，不是 EXEC——也必须签名
   # ...签名逻辑...
   ```
2. 创建 meson native.ini，将 CC/CXX 指向包装器脚本
3. 使用 mesonpy 构建：`python3 -c "import mesonpy; mesonpy.build_wheel('...')"`
4. 签名结果 wheel 中的所有 .so
5. 手动安装到 site-packages

**关键洞察**：包装器必须签名所有 ELF 输出（包括 PIE/DYN 类型），不能只签 EXEC 类型。Meson 的 sanity_check 是 PIE 可执行文件。

### 中等：带 C++ 依赖的 Meson 构建（matplotlib）

matplotlib 使用 mesonpy 构建系统，包含基于 pybind11 的 C++ 扩展（kiwisolver）和 C 扩展（contourpy）。构建需要额外的 pkg-config 和构建依赖。

1. 安装构建依赖：
   ```bash
   pip install meson-python setuptools_scm pybind11 ninja
   # setuptools_scm 需要 vcs_versioning 插件
   pip install setuptools_scm_git_archive  # 或等效的 vcs 插件
   ```

2. 设置 PKG_CONFIG_PATH 以找到 pybind11：
   ```bash
   export PKG_CONFIG_PATH=$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig:$PKG_CONFIG_PATH
   ```

3. 使用 mesonpy Python API 构建（与 pandas 相同的自动签名 clang 包装器）：
   ```bash
   python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/matplotlib_src')"
   ```

4. 提取 wheel，然后对每个 .so 文件（共 8 个）：
   ```bash
   # 签名所有 .so 文件
   find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
     for f do
       /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
       mv "${f}.signed" "$f"
     done
   ' sh {} +

   # 添加 libc++_shared.so 作为 NEEDED 依赖（C++ 扩展需要）
   find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
     for f do
       /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
     done
   ' sh {} +

   # 重命名 .so 后缀
   for f in *.cpython-312.so; do
     mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
   done
   ```

5. 手动安装到 site-packages

**e2e 测试结果（6/6）**：折线图（savefig）、直方图、散点图、柱状图、子图、等高线图。

**关键洞察**：matplotlib 的 C++ 扩展（基于 pybind11 的 kiwisolver、C 语言的 contourpy）需要通过 patchelf 添加 `libc++_shared.so`，因为 HarmonyOS 的 Python 不导出 C++ 运行时符号。还需要将 pybind11 的 pkgconfig 路径加入 PKG_CONFIG_PATH，以及 setuptools_scm 配合 vcs_versioning 进行版本检测。

### 简单：Node.js WASM32 回退方案（sharp）

sharp 没有 openharmony-arm64 预编译二进制。WASM32 模式可以作为功能完整（但较慢）的回退方案。

1. `npm install sharp`（安装基础包，但原生模块失败）
2. `npm install --force @img/sharp-wasm32`（安装 WASM32 回退）
3. sharp 自动检测 WASM32 模块并使用它

**性能**：WASM32 比原生 libvips 慢约 5-10 倍，但所有图像操作（resize、格式转换、metadata、stats）均正常工作。

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