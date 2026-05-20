# Python 环境详情

## Python 安装

**唯一源**: `$HOME/.local/bin/python3` (Python 3.12.8)

```
Python 3.12.8 @ $HOME/.local/
├── bin/python3          # 主程序（-rdynamic 编译）
├── lib/python3.12/      # 标准库
│   ├── lib-dynload/     # 扩展模块（需签名）
│   └── site-packages/   # pip 安装包
└── include/python3.12/  # 头文件（编译扩展用）
```

**关键特性**:
- 使用 `-rdynamic` 编译，导出 1521 个 Py 符号
- 可加载用户目录的签名 .so 扩展模块
- pip 直接运行，无需 wrapper
- pillow 11.3.0 图像处理可用
- lxml 6.0.0 XML/XSLT处理可用

## Shell 配置

`~/.zshenv`:
```bash
export PATH="$HOME/.local/bin:$PATH"
export TMPDIR="$HOME/Claude/tmpdir"
export LD_LIBRARY_PATH="$HOME/.local/lib:/system/lib64"
```

**注意**: `$HOME/.local/lib` 已包含在 LD_LIBRARY_PATH 中，lxml 和其他动态库扩展可正常加载。

## pip 配置

`~/.pip/pip.conf`:
```
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
```

## 包安装状态

| 包类型 | 可用性 | 说明 |
|--------|--------|------|
| 纯 Python | ✅ | pip install 直接可用 |
| numpy | ✅ | 需要 wheel 重命名 + 签名 |
| C/C++ 扩展 | ✅ | 设置 CC/CXX 环境变量 |
| Rust 扩展 | ✅ | 设置 CC/CXX 环境变量 |
| pillow | ✅ | 编译 libjpeg/libpng 源码 |
| lxml | ✅ | 编译 libxml2/libxslt 源码，需 LD_LIBRARY_PATH |

## C/C++/Rust 扩展包安装

pip 构建 C/C++/Rust 扩展时需要设置编译器环境变量:

```bash
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
pip install <package>
```

**已验证工作的包**:
- bcrypt (Rust crate) — 编译成功后签名 .so
- greenlet (C++ extension) — 编译成功后签名 .so
- sqlalchemy — 纯 Python，依赖 greenlet
- pillow — 编译 libjpeg-turbo 3.0.4 + libpng 1.6.48
- lxml — 编译 libxml2 2.14.0 + libxslt 1.1.42

**失败的包**:
- curses — autoconf 不识别 'ohos' triplet，需修改 config.sub

## numpy 安装步骤

1. **重命名 wheel**: 平台标识 `harmonyos_hongmeng_kernel_1_12_0_aarch64`
2. **签名扩展模块**: 后缀 `.cpython-312-aarch64-linux-gnu.so`

## pillow 安装步骤

pillow 需要先编译 libjpeg-turbo 和 libpng:

1. **编译 libjpeg-turbo 3.0.4**:
   ```bash
   cmake -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

2. **编译 libpng 1.6.48**:
   ```bash
   cmake -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

3. **安装 pillow**:
   ```bash
   CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install pillow
   ```

4. **重命名扩展模块**:
   ```bash
   cd ~/.local/lib/python3.12/site-packages/PIL
   for f in *.cpython-312.so; do
     mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
   done
   ```

5. **签名扩展模块**:
   ```bash
   for f in *.cpython-312-aarch64-linux-gnu.so; do
     /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}_signed"
     mv "${f}_signed" "$f"
   done
   ```

## lxml 安装步骤

lxml 需要先编译 libxml2, libxslt 和 libexslt:

1. **编译 libxml2 2.14.0**:
   ```bash
   cmake -DLIBXML2_WITH_PYTHON=OFF -DCMAKE_SYSTEM_NAME=Linux \
     -DCMAKE_C_COMPILER=/data/service/hnp/bin/clang \
     --sysroot=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot \
     -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
   make && make install
   ```

2. **编译 libxslt 1.1.42** (需要手动创建 xsltconfig.h):
   ```bash
   # 创建 xsltconfig.h 添加 WITH_PROFILER=1
   # 使用 clang 编译各模块，链接为 libxslt.so 和 libexslt.so
   ```

3. **安装 lxml**:
   ```bash
   CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install lxml
   ```

   **注意**: `$HOME/.local/lib` 已在 `LD_LIBRARY_PATH` 中配置，无需额外设置。

4. **重命名和签名扩展模块** (同 pillow)

## 扩展模块编译模板

```bash
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot

/data/service/hnp/bin/clang -shared --sysroot=$SYSROOT \
  -I$HOME/.local/include/python3.12 \
  -I./Include \
  -I./Include/internal \
  -DPy_BUILD_CORE_MODULE \
  -o module.cpython-312-aarch64-linux-gnu.so \
  source.c

# 签名
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign module.so module_tmp.so
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile module_tmp.so -outFile module_signed.so
```

## 常见问题

### Q: 为什么不用系统 Python？

系统 Python (`/data/service/hnp/bin/python3`) 静态链接，不导出 Py 符号，无法加载用户目录的 .so 扩展模块。

### Q: pip 安装的 C 扩展包为什么不工作？

pip wheel 中的 .so 文件可能依赖 `libpython3.12.so.1.0`，本地静态编译的 Python 不提供此动态库。

### Q: 如何验证符号导出？

```bash
nm -D ~/.local/bin/python3 | grep " T " | grep Py | wc -l
# 输出: 1521
```

### Q: bcrypt/greenlet 等包编译失败怎么办？

设置 `CC` 和 `CXX` 环境变量指向 clang:
```bash
CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++ pip install bcrypt
```

### Q: pillow 安装失败怎么办？

pillow 需要 libjpeg 和 libpng 开发库，SDK 不提供。需从源码编译:
- libjpeg-turbo 3.0.4 → `~/.local/lib/libjpeg.a`
- libpng 1.6.48 → `~/.local/lib/libpng16.a`

### Q: lxml 报错 "libxml2.so.16 not found" 怎么办？

确保 `LD_LIBRARY_PATH` 包含 `$HOME/.local/lib`:
```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
```

此设置已在 `~/.zshenv` 中配置。

### Q: curses 模块能用吗？

不能。ncurses 的 configure 脚本不识别 HarmonyOS (ohos) 目标三元组，需要修改 config.sub 文件。

## 相关文档

- [python-packages-harmonyos.md](python-packages-harmonyos.md) — 包兼容性完整报告