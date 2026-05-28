# HarmonyOS Python 软件包兼容性报告

## 测试日期：2026-05-28（更新）

## 环境

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- 平台: HarmonyOS HongMeng Kernel 1.12.0, aarch64

## 结果摘要

| 类别 | 通过 | 失败 | 备注 |
|----------|------|------|-------|
| 核心 Python | 13/13 | 0 | json, datetime, hashlib, ctypes, sqlite3, csv, xml, multiprocessing, urllib, re, collections, asyncio, unittest |
| 数据处理 | 4/4 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy |
| 数学/符号计算 | 1/1 | 0 | sympy |
| 图像处理 | 1/1 | 0 | pillow 12.2.0 (编译 libjpeg/libpng) |
| XML 处理 | 1/1 | 0 | lxml 6.1.0 (编译 libxml2/libxslt) |
| Web/HTTP | 7/7 | 0 | requests, urllib3, flask, werkzeug, django, aiohttp, tornado |
| 模板 | 2/2 | 0 | jinja2, markupsafe |
| CLI/工具 | 4/4 | 0 | click, six, colorama, tqdm |
| 安全 | 3/3 | 0 | itsdangerous, blinker, bcrypt |
| 数据库 | 1/1 | 0 | sqlalchemy (with greenlet) |
| 序列化 | 1/1 | 0 | msgpack |
| 构建工具 | 4/4 | 0 | setuptools, wheel, cython, packaging |
| 杂项 | 5/5 | 0 | certifi, charset_normalizer, idna, pip, typing_extensions |
| **总计** | **46/46** | **0** | 所有已安装的软件包均正常工作 |

## 详细测试结果

### 核心 Python（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| json | built-in | dumps/loads works |
| datetime | built-in | now() works |
| hashlib | built-in | sha256 works |
| ctypes | built-in | CDLL("libc.so") works |
| sqlite3 | built-in | in-memory DB works |
| csv | built-in | reader/writer works |
| xml.etree.ElementTree | built-in | parse/generate works |
| multiprocessing | built-in | Process/Queue works |
| urllib | built-in | request works |
| re | built-in | regex works |
| collections | built-in | defaultdict, Counter work |
| asyncio | built-in | async/await works |
| unittest | built-in | TestCase works |

### 数据处理（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| numpy | 2.4.4 | array, random, linalg, sin all work |
| pyyaml | 6.0.3 | safe_load works |
| beautifulsoup4 | 4.14.3 | HTML parsing works |

### 数学/符号计算（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| sympy | 1.14.0 | diff(x**2, x) = 2*x works |

### 数据库/ORM（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| sqlalchemy | 2.0.49 | create_engine, Session, declarative_base work |
| greenlet | 3.5.0 | greenlet switching works (sqlalchemy dependency) |

### Web/HTTP（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| requests | 2.34.0 | HTTP GET works |
| urllib3 | 2.7.0 | import works |
| flask | 3.1.3 | Flask() app, app_context, url_for work |
| werkzeug | 3.1.8 | import works |
| django | 6.0.5 | Django VERSION works |
| aiohttp | 3.12.14 | async HTTP client works |
| tornado | 6.5.1 | IOLoop import works |

### 序列化（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| msgpack | 1.1.1 | pack/unpack works |

### 模板（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| jinja2 | 3.1.6 | Template.render works |
| markupsafe | 3.0.3 | escape works |

### CLI/工具（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| click | 8.3.3 | import works |
| six | 1.17.0 | import works |
| colorama | 0.4.6 | Fore.GREEN colored output works |
| tqdm | 4.67.3 | import works |

### 安全（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| itsdangerous | 2.2.0 | URLSafeSerializer works |
| blinker | 1.9.0 | import works |
| bcrypt | 5.0.0 | hashpw, gensalt, checkpw work (compiled with CC/CXX env) |
| cryptography | 48.0.0 | AES, RSA, ECDSA, hashes all work (see cryptography-harmonyos.md) |
| cffi | 1.17.1 | import works (cryptography dependency) |

### 构建工具（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| setuptools | 82.0.1 | import works |
| wheel | 0.47.0 | import works |
| cython | 3.2.4 | import works |
| packaging | 26.2 | import works |

### 杂项（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| certifi | 2026.4.22 | import works |
| charset_normalizer | 3.4.7 | import works |
| idna | 3.14 | import works |
| pip | 24.3.1 | pip commands work |
| typing_extensions | 4.15.0 | import works |
| soupsieve | 2.8.3 | import works |

## 构建失败的软件包

| 软件包 | 错误 | 解决方案 | 状态 |
|---------|-------|----------|--------|
| bcrypt | linker `cc` not found | 在 pip install 前设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` | ✅ WORKS |
| greenlet | `c++` failed | 设置 `CC/CXX` 环境变量，构建后签名 .so | ✅ WORKS |
| pillow | `cc` failed, missing jpeg headers | 从源码编译 libjpeg-turbo 3.0.4 + libpng 1.6.48 | ✅ WORKS |
| lxml | libxml2/libxslt missing | 从源码编译 libxml2 2.14.0 + libxslt 1.1.42 | ✅ WORKS |
| cryptography | Rust/maturin build | libffi → cffi → maturin → OpenSSL → cryptography 依赖链 | ✅ WORKS (see cryptography-harmonyos.md) |
| psutil | sockaddr_storage compile error | HarmonyOS 结构体差异 | ❌ FAILS |
| pandas | meson sanity check Permission denied | Meson 构建中间文件未代码签名 | ❌ FAILS |
| pydantic v2 | Rust/maturin required | maturin 需要 Rust 工具链 + CC 环境 | ❌ FAILS (use pydantic v1) |
| fastapi | depends on pydantic v2 | Requires pydantic >= 2.0 | ❌ FAILS |

## 仍然失败的软件包（需要系统库）

| 软件包 | 错误 | 原因 | 替代方案 |
|---------|-------|--------|-------------|
| curses | autoconf doesn't recognize 'ohos' | config.sub 需要为 HarmonyOS 三元组打补丁 | Skip curses-dependent apps |
| psutil | struct sockaddr_storage | HarmonyOS 内核头文件差异 | Use /proc and os module alternatives |
| pandas | meson binary not signed | Meson sanity_check.exe 未代码签名 | Need signing wrapper for meson |
| pydantic v2 | maturin + Rust | maturin 构建隔离问题 | Use pydantic v1.x (pure Python) |

## 已编译的原生库

| 库 | 版本 | 位置 | 使用者 |
|---------|---------|----------|---------|
| libjpeg-turbo | 3.0.4 | `~/.local/lib/libjpeg.a` | pillow |
| libpng | 1.6.48 | `~/.local/lib/libpng16.a` | pillow |
| libxml2 | 2.14.0 | `~/.local/lib/libxml2.so` | lxml |
| libxslt | 1.1.42 | `~/.local/lib/libxslt.so` | lxml |
| libexslt | 1.1.42 | `~/.local/lib/libexslt.so` | lxml |
| libffi | 8 | `~/.local/lib/libffi.so.8` | cffi/cryptography |
| libopenblas | 0.3.28 | `~/.local/lib/libopenblas.so` | PyTorch/numpy |

## 软件包兼容性分类

| 类别 | 可用性 | 示例 | 备注 |
|----------|-------|---------|-------|
| 纯 Python | 100% | requests, flask, jinja2, django | 直接使用 pip 安装 |
| 基于 NumPy | 100% | numpy, after signing | 需要重命名 wheel + 签名 .so |
| 图像处理 | 100% | pillow | 从源码编译 libjpeg/libpng |
| XML 解析 | 100% | lxml | 从源码编译 libxml2/libxslt |
| C/C++ 扩展 | 视情况 | bcrypt, greenlet | 设置 CC/CXX 环境变量 |
| 基于 Rust | 视情况 | cryptography | 需要 CC 环境 + Rust 工具链 + libffi |
| 基于 Meson | 失败 | pandas | 构建中间文件需要代码签名 |

## lxml 的运行时要求

lxml 需要设置 `LD_LIBRARY_PATH` 以找到共享库：

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```

可以将此行添加到 `~/.zshenv` 中以持久化配置。

## 建议

1. **纯 Python 软件包**：直接使用 pip 安装，100% 兼容
2. **numpy/scipy**：使用 HarmonyOS wheel + 签名扩展模块
3. **C/C++ 扩展软件包**：在 pip install 前设置 `CC=/data/service/hnp/bin/clang` 和 `CXX=/data/service/hnp/bin/clang++` 环境变量
4. **基于 Rust 的软件包**：设置 CC/CXX 环境变量 + 确保 Rust 工具链可用（参见 cryptography-harmonyos.md）
5. **图像处理 (pillow)**：✅ 可用 - 已从源码编译 libjpeg-turbo 和 libpng
6. **XML 解析 (lxml)**：✅ 可用 - 已从源码编译 libxml2、libxslt 和 libexslt
7. **终端 UI (curses)**：不可用 - autoconf 问题，跳过依赖 curses 的应用
8. **pandas**：❌ 失败 - meson 构建需要签名的中间文件；变通方案待定
9. **psutil**：❌ 失败 - struct sockaddr_storage 不兼容；使用 os/proc 替代方案
