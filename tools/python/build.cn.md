# HarmonyOS 上的 Python 3.12.8 - 完整构建指南

> **English version: build.md**

## 概述

本文档记录了在 HarmonyOS 上从源码构建 Python 3.12.8 的完整过程。主要挑战是系统 Python 无法加载用户安装的扩展模块（.so 文件），因为它是静态链接的，不导出 Python API 符号。

**解决方案**：使用 `-rdynamic` 标志构建 Python 以导出所有符号，从而启用扩展模块加载功能。

## 前置条件

- HarmonyOS SDK（包含 clang 15.0.4）
- 可写的 TMPDIR（HarmonyOS 的 `/tmp` 是只读的）
- 约 500MB 磁盘空间用于构建
- **ld.bfd 包装器**（SDK 的 lld 需要 libxml2.so.16，但该文件不存在）
- **clang 包装器**（configure 测试二进制需要代码签名才能执行）

## 关键：clang 包装器用于 configure

Configure 生成的测试二进制（`conftest`）必须在 HarmonyOS 上代码签名才能执行。创建包装脚本：

```bash
mkdir -p $HOME/Claude/bin

# clang 包装器：自动签名二进制 + 处理 --print-multiarch
cat > $HOME/Claude/bin/clang-wrapper << 'EOF'
#!/bin/sh
REAL_CLANG=/data/service/hnp/bin/clang
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool

# 特殊处理 --print-multiarch 以匹配 PLATFORM_TRIPLET
if echo "$*" | grep -q -- "--print-multiarch"; then
    echo "aarch64-linux-gnu"
    exit 0
fi

"$REAL_CLANG" "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    OUTPUT=""
    PREV=""
    for arg in "$@"; do
        if [ "$PREV" = "-o" ]; then
            OUTPUT="$arg"
            break
        fi
        case "$arg" in -o*) OUTPUT="${arg#-o}"; break ;; esac
        PREV="$arg"
    done
    if [ -n "$OUTPUT" ] && [ -f "$OUTPUT" ]; then
        if file "$OUTPUT" 2>/dev/null | grep -q "ELF"; then
            "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT" -outFile "$OUTPUT.signed" -signAlg SHA256withECDSA 2>/dev/null
            if [ -f "$OUTPUT.signed" ]; then
                mv "$OUTPUT.signed" "$OUTPUT"
                chmod +x "$OUTPUT"
            fi
        fi
    fi
fi
exit $EXIT_CODE
EOF

# clang++ 包装器（类似逻辑）
cat > $HOME/Claude/bin/clang++-wrapper << 'EOF'
#!/bin/sh
REAL_CLANG=/data/service/hnp/bin/clang++
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool

"$REAL_CLANG" "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    OUTPUT=""
    PREV=""
    for arg in "$@"; do
        if [ "$PREV" = "-o" ]; then OUTPUT="$arg"; break; fi
        case "$arg" in -o*) OUTPUT="${arg#-o}"; break ;; esac
        PREV="$arg"
    done
    if [ -n "$OUTPUT" ] && [ -f "$OUTPUT" ] && file "$OUTPUT" 2>/dev/null | grep -q "ELF"; then
        "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT" -outFile "$OUTPUT.signed" -signAlg SHA256withECDSA 2>/dev/null
        [ -f "$OUTPUT.signed" ] && mv "$OUTPUT.signed" "$OUTPUT" && chmod +x "$OUTPUT"
    fi
fi
exit $EXIT_CODE
EOF

chmod +x $HOME/Claude/bin/clang-wrapper $HOME/Claude/bin/clang++-wrapper
```

**为什么需要 --print-multiarch hack？**：
- `clang --print-multiarch` 返回 `aarch64-linux-ohos`
- Configure 的预处理器测试检测到 `aarch64-linux-gnu`
- Configure 要求两者匹配，导致 triplet 错误
- 包装器返回 `aarch64-linux-gnu` 以匹配预处理器结果

## 关键：ld.bfd 包装器

SDK 的 lld 链接器动态链接到 `libxml2.so.16`，该文件在 HarmonyOS 上不存在。您必须使用 ld.bfd 替代：

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

然后在所有 clang 编译命令中使用 `-B$HOME/Claude/lib/linker_wrapper`。

## 源码下载

```bash
cd $HOME/Claude/python-build
wget https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tar.xz
tar xf Python-3.12.8.tar.xz
cd Python-3.12.8
```

## 构建步骤

### 步骤 1：修复 configure 以适配 HarmonyOS

HarmonyOS 与标准 Linux 有一些差异，需要修改 configure 脚本：

```bash
# 修复 1：临时目录（HarmonyOS 的 /tmp 是只读的）
sed -i 's|mktemp -d "./confXXXXXX"|mktemp -d "${TMPDIR:-$HOME/Claude/tmpdir}/confXXXXXX"|g' configure
sed -i 's|umask 077 && mkdir "$tmp"|mkdir "$tmp"|g' configure

# 修复 2：平台三元组（config.guess 无法识别 HarmonyOS）
echo '#!/bin/sh
echo "aarch64-linux-gnu"' > config.guess
chmod +x config.guess
```

### 步骤 2：配置

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
LINKER_WRAPPER_DIR=$HOME/Claude/lib/linker_wrapper

TMPDIR=$HOME/Claude/tmpdir \
CC=$HOME/Claude/bin/clang-wrapper \
CXX=$HOME/Claude/bin/clang++-wrapper \
CFLAGS="--sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR" \
CXXFLAGS="--sysroot=$SYSROOT -B$LINKER_WRAPPER_DIR" \
LDFLAGS="--sysroot=$SYSROOT -L$SYSROOT/usr/lib/aarch64-linux-ohos -rdynamic -B$LINKER_WRAPPER_DIR" \
./configure \
  --prefix=$HOME/.local \
  --disable-shared \
  --host=aarch64-linux-gnu \
  --build=aarch64-linux-gnu
```

**关键参数说明**：
- `-rdynamic`：**关键** - 导出所有符号以支持扩展模块加载
- `-B$LINKER_WRAPPER_DIR`：**关键** - 绕过损坏的 lld，使用 ld.bfd
- `--sysroot`：HarmonyOS SDK sysroot 路径
- `--disable-shared`：仅构建可执行文件，不构建 libpython.so（HarmonyOS 缺少 libdl.so/libm.so）
- `CC/CXX`：**关键** - 使用包装脚本，不是直接 clang
- `--host/--build`：设置三元组为 `aarch64-linux-gnu` 以避免三元组不匹配

### 步骤 3：修复 pyconfig.h 以解决 HarmonyOS 缺失的功能

```bash
# 等待 configure 完成后，修复 pyconfig.h
sed -i 's/#define HAVE_LIBINTL_H 1/\/* #undef HAVE_LIBINTL_H *\//' pyconfig.h
sed -i 's/#define HAVE_LINUX_CAN_RAW_FD_FRAMES 1/\/* #undef HAVE_LINUX_CAN_RAW_FD_FRAMES *\//' pyconfig.h
sed -i 's/#define HAVE_LINUX_CAN_RAW_JOIN_FILTERS 1/\/* #undef HAVE_LINUX_CAN_RAW_JOIN_FILTERS *\//' pyconfig.h
```

### 步骤 4：构建

```bash
make python.exe
```

这将生成 `python.exe`（约 40MB）。

### 步骤 5：签名二进制文件

所有 ELF 二进制文件在 HarmonyOS 上执行前必须签名：

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile python.exe \
  -outFile python_signed \
  -signAlg SHA256withECDSA
chmod 755 python_signed
```

### 步骤 6：安装

```bash
# 创建目录
mkdir -p $HOME/.local/bin
mkdir -p $HOME/.local/lib/python3.12
mkdir -p $HOME/.local/include/python3.12
mkdir -p $HOME/.local/lib/python3.12/lib-dynload

# 安装二进制文件
cp python_signed $HOME/.local/bin/python3.12
ln -sf python3.12 $HOME/.local/bin/python3
ln -sf python3.12 $HOME/.local/bin/python

# 安装标准库
cp -r Lib/* $HOME/.local/lib/python3.12/

# 安装头文件（用于构建扩展模块）
cp -r Include/* $HOME/.local/include/python3.12/
cp pyconfig.h $HOME/.local/include/python3.12/

# 安装静态库
cp libpython3.12.a $HOME/.local/lib/
```

### 步骤 7：构建必要的扩展模块

需要构建两个关键扩展模块才能使 pip 正常工作：

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
PYTHON_INCLUDE=$HOME/.local/include/python3.12

# 构建 _pickle
/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$PYTHON_INCLUDE \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o _pickle.so \
  ./Modules/_pickle.c \
  -L$SYSROOT/usr/lib/aarch64-linux-ohos

# 构建 _datetime  
/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$PYTHON_INCLUDE \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o _datetime.so \
  ./Modules/_datetimemodule.c \
  -L$SYSROOT/usr/lib/aarch64-linux-ohos

# 签名并安装
for module in _pickle _datetime; do
  /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign ${module}.so ${module}_unsigned.so
  /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
    -inFile ${module}_unsigned.so \
    -outFile $HOME/.local/lib/python3.12/lib-dynload/${module}.cpython-312-aarch64-linux-gnu.so \
    -signAlg SHA256withECDSA
done
```

### 步骤 8：安装 pip

```bash
# 下载 get-pip.py
curl -L https://bootstrap.pypa.io/get-pip.py -o $HOME/Claude/tmpdir/get-pip.py

# 安装 pip
$HOME/.local/bin/python3 $HOME/Claude/tmpdir/get-pip.py

# 配置 pip 镜像源
mkdir -p $HOME/.pip
echo '[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple' > $HOME/.pip/pip.conf
```

### 步骤 9：配置 sysconfigdata

```bash
# 复制并重命名 sysconfigdata 以适配 HarmonyOS 平台名称
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/_sysconfigdata__linux_.py \
   $HOME/.local/lib/python3.12/_sysconfigdata__harmonyosHongMengKernel1_aarch64-linux-ohos.py
```

## 验证

```bash
# 测试 Python 版本
python3 --version
# Python 3.12.8

# 测试扩展模块加载
python3 -c "import pickle; print(pickle.dumps([1,2,3]))"
# b'\x80\x04\x95...

# 测试 datetime
python3 -c "import datetime; print(datetime.datetime.now())"
# 2026-05-18 ...

# 测试 pip
python3 -m pip --version
# pip 24.3.1 from ...
```

## 符号导出对比

| Python 构建 | 导出的 Py 符号数 | 扩展模块加载 |
|--------------|---------------------|-------------------|
| 系统 Python（静态） | 0 | 权限被拒绝 |
| 本地 Python（-rdynamic） | 948+ | 成功 |

验证命令：
```bash
nm -D $HOME/.local/bin/python3 | grep " T " | grep Py | wc -l
# 948
```

## 安装 numpy

对于 numpy，使用预构建 wheel 包的方式。**注意**：PyPI 没有 `harmonyos_aarch64` 平台，使用兼容的 `manylinux2014_aarch64`：

```bash
# 为 aarch64 下载 numpy wheel 包（manylinux 兼容）
pip download numpy --platform manylinux2014_aarch64 --python-version 312 --only-binary=:all: --no-deps

# 直接安装（无需重命名，manylinux wheel 在 HarmonyOS 上可用）
pip install numpy-*-manylinux2014_aarch64.whl --no-deps

# 签名所有 numpy 扩展模块（HarmonyOS 必需）
cd $HOME/.local/lib/python3.12/site-packages/numpy
find . -name "*.so" -exec /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile {} -outFile {}.signed -signAlg SHA256withECDSA \; -exec mv {}.signed {} \;
```

或者直接从 PyPI 镜像安装：
```bash
pip install numpy --no-deps
# 然后按上述方法签名扩展模块
```

## 已知限制

1. **curses 模块**：ncurses 的 configure 无法识别 HarmonyOS 三元组
2. **locale 支持**：有限（缺少 pt_BR、collate、ctype 等 locale）
3. **BLAS/LAPACK**：SDK 中不可用，影响 numpy 性能

## 构建时间

- 配置：约 5 分钟
- 构建 python.exe：约 15 分钟（单线程）
- 扩展模块：每个约 2 分钟
- 总计：约 30 分钟

## 磁盘空间

- 源码：20MB（tar.xz）
- 构建：400MB
- 安装：60MB