# HarmonyOS Python 包兼容性报告

## 测试日期：2026-05-20（已更新）

## 环境

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- 平台: HarmonyOS HongMeng Kernel 1.12.0, aarch64

## 结果汇总

| 类别 | 通过 | 失败 | 备注 |
|----------|------|------|-------|
| 核心 Python | 5/5 | 0 | pickle, datetime, ctypes, json, hashlib |
| 数据处理 | 4/4 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy |
| 图像处理 | 1/1 | 0 | pillow 12.2.0 (已编译 libjpeg/libpng) |
| XML 处理 | 1/1 | 0 | lxml 6.1.0 (已编译 libxml2/libxslt) |
| Web/HTTP | 4/4 | 0 | requests, urllib3, flask, werkzeug |
| 模板引擎 | 2/2 | 0 | jinja2, markupsafe |
| CLI/工具 | 4/4 | 0 | click, six, colorama, tqdm |
| 安全 | 3/3 | 0 | itsdangerous, blinker, bcrypt |
| 数据库 | 1/1 | 0 | sqlalchemy (含 greenlet) |
| 构建工具 | 4/4 | 0 | setuptools, wheel, cython, packaging |
| 其他 | 5/5 | 0 | certifi, charset_normalizer, idna, pip, typing_extensions |
| **总计** | **34/34** | **0** | 所有已安装包均正常工作 |

## 详细测试结果

### 核心 Python（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| pickle | 内置 | dumps/loads 正常 |
| datetime | 内置 | now() 正常 |
| ctypes | 内置 | CDLL("libc.so") 正常 |
| json | 内置 | dumps/loads 正常 |
| hashlib | 内置 | sha256 正常 |

### 数据处理（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| numpy | 2.4.4 | array, random, linalg, sin 均正常 |
| pyyaml | 6.0.3 | safe_load 正常 |
| beautifulsoup4 | 4.14.3 | HTML 解析正常 |

### 数据库/ORM（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| sqlalchemy | 2.0.49 | create_engine, Session, declarative_base 正常 |
| greenlet | 3.5.0 | greenlet 切换正常（sqlalchemy 依赖） |

### Web/HTTP（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| requests | 2.34.0 | 导入正常 |
| urllib3 | 2.7.0 | 导入正常 |
| flask | 3.1.3 | Flask() 应用、app_context、url_for 正常 |
| werkzeug | 3.1.8 | 导入正常 |

### 模板引擎（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| jinja2 | 3.1.6 | Template.render 正常 |
| markupsafe | 3.0.3 | escape 正常 |

### CLI/工具（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| click | 8.3.3 | 导入正常 |
| six | 1.17.0 | 导入正常 |
| colorama | 0.4.6 | Fore.GREEN 彩色输出正常 |
| tqdm | 4.67.3 | 导入正常 |

### 安全（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| itsdangerous | 2.2.0 | URLSafeSerializer 正常 |
| blinker | 1.9.0 | 导入正常 |
| bcrypt | 5.0.0 | hashpw, gensalt, checkpw 正常（使用 CC/CXX 环境变量编译） |

### 构建工具（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| setuptools | 82.0.1 | 导入正常 |
| wheel | 0.47.0 | 导入正常 |
| cython | 3.2.4 | 导入正常 |
| packaging | 26.2 | 导入正常 |

### 其他（全部通过）

| 包名 | 版本 | 测试 |
|---------|---------|------|
| certifi | 2026.4.22 | 导入正常 |
| charset_normalizer | 3.4.7 | 导入正常 |
| idna | 3.14 | 导入正常 |
| pip | 24.3.1 | pip 命令正常 |
| typing_extensions | 4.15.0 | 导入正常 |
| soupsieve | 2.8.3 | 导入正常 |

## 构建失败的包（已找到解决方案）

| 包名 | 错误 | 解决方案 | 状态 |
|---------|-------|----------|--------|
| bcrypt | 链接器找不到 `cc` | 在 pip install 前设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` | ✅ 已解决 |
| greenlet | `c++` 失败 | 设置 `CC/CXX` 环境变量，构建后签名 .so 文件 | ✅ 已解决 |
| pillow | `cc` 失败，缺少 jpeg 头文件 | 从源码编译 libjpeg-turbo 3.0.4 + libpng 1.6.48 | ✅ 已解决 |
| lxml | 缺少 libxml2/libxslt | 从源码编译 libxml2 2.14.0 + libxslt 1.1.42 | ✅ 已解决 |

## 仍然失败的包（需要系统库）

| 包名 | 错误 | 原因 | 替代方案 |
|---------|-------|--------|-------------|
| curses | autoconf 无法识别 'ohos' | config.sub 需要为 HarmonyOS 三元组打补丁 | 跳过依赖 curses 的应用 |
| cryptography | Rust 构建 | 需要 Rust 工具链 + CC 环境变量 | 设置 CC 环境变量 + Rust 工具链 |

## 已编译的原生库

| 库名 | 版本 | 位置 | 使用者 |
|---------|---------|----------|---------|
| libjpeg-turbo | 3.0.4 | `~/.local/lib/libjpeg.a` | pillow |
| libpng | 1.6.48 | `~/.local/lib/libpng16.a` | pillow |
| libxml2 | 2.14.0 | `~/.local/lib/libxml2.so` | lxml |
| libxslt | 1.1.42 | `~/.local/lib/libxslt.so` | lxml |
| libexslt | 1.1.42 | `~/.local/lib/libexslt.so` | lxml |

## 包兼容性分类

| 类别 | 兼容性 | 示例 | 备注 |
|----------|-------|---------|-------|
| 纯 Python | 100% | requests, flask, jinja2 | 直接 pip install |
| 基于 NumPy | 100% | numpy，签名后 | 需要 wheel 重命名 + .so 签名 |
| 图像处理 | 100% | pillow | 从源码编译 libjpeg/libpng |
| XML 解析 | 100% | lxml | 从源码编译 libxml2/libxslt |
| C/C++ 扩展 | 可变 | bcrypt, greenlet | 设置 CC/CXX 环境变量 |
| 基于 Rust | 可变 | bcrypt, cryptography | 需要 CC 环境变量 + Rust 工具链 |

## lxml 运行时要求

lxml 需要 `LD_LIBRARY_PATH` 来查找共享库：

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```

可以将其添加到 `~/.zshenv` 以实现持久化。

## 建议

1. **纯 Python 包**：直接使用 pip 安装，100% 兼容
2. **numpy/scipy**：使用 HarmonyOS wheel + 签名扩展模块
3. **C/C++ 扩展包**：在 pip install 前设置 `CC=/data/service/hnp/bin/clang` 和 `CXX=/data/service/hnp/bin/clang++` 环境变量
4. **基于 Rust 的包**：设置 CC/CXX 环境变量 + 确保 Rust 工具链可用
5. **图像处理 (pillow)**：✅ 现已可用 - 从源码编译了 libjpeg-turbo 和 libpng
6. **XML 解析 (lxml)**：✅ 现已可用 - 从源码编译了 libxml2、libxslt 和 libexslt
7. **终端 UI (curses)**：不可用 - autoconf 问题，跳过依赖 curses 的应用程序

## 测试脚本

位置：`/storage/Users/currentUser/Claude/test_pip_packages.py`

运行：`python3 test_pip_packages.py`