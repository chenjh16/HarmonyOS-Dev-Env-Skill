# HarmonyOS Python 软件包兼容性报告

## 测试日期：2026-05-30（更新）

## 环境

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- 平台: HarmonyOS HongMeng Kernel 1.12.0, aarch64

## 结果摘要

| 类别 | 通过 | 失败 | 备注 |
|----------|------|------|-------|
| 核心 Python | 13/13 | 0 | json, datetime, hashlib, ctypes, sqlite3, csv, xml, multiprocessing, urllib, re, collections, asyncio, unittest |
| 数据处理 | 5/5 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy, networkx |
| 数学/符号计算 | 1/1 | 0 | sympy |
| 数据可视化 | 3/3 | 0 | matplotlib 3.10.3 (mesonpy 构建), contourpy 1.3.3, kiwisolver 1.5.0 |
| 图像处理 | 1/1 | 0 | pillow 12.2.0 (编译 libjpeg/libpng) |
| XML 处理 | 1/1 | 0 | lxml 6.1.0 (编译 libxml2/libxslt) |
| Web/HTTP | 11/11 | 0 | requests, urllib3, flask, werkzeug, django, aiohttp, tornado, httpx, uvicorn, websockets, python-multipart |
| 模板 | 2/2 | 0 | jinja2, markupsafe |
| CLI/工具 | 5/5 | 0 | click, six, colorama, tqdm, rich |
| 测试 | 1/1 | 0 | pytest |
| 安全 | 8/8 | 0 | itsdangerous, blinker, bcrypt, cryptography, cffi, hiredis, passlib, pycryptodome |
| 数据库 | 1/1 | 0 | sqlalchemy (with greenlet) |
| 序列化 | 7/7 | 0 | msgpack, lz4, zstd, cbor2, ruamel.yaml, ijson, toml |
| 构建工具 | 4/4 | 0 | setuptools, wheel, cython, packaging |
| 日志 | 1/1 | 0 | loguru |
| 文档 | 1/1 | 0 | docutils |
| 语法高亮 | 1/1 | 0 | pygments |
| 配置/工具 | 3/3 | 0 | python-dotenv, distro, wcwidth |
| 日期/时间 | 2/2 | 0 | python-dateutil, arrow |
| 任务调度 | 1/1 | 0 | schedule |
| 重试/容错 | 1/1 | 0 | tenacity |
| 数据结构 | 1/1 | 0 | pyrsistent |
| 装饰器 | 1/1 | 0 | wrapt |
| 编码检测 | 2/2 | 0 | charset_normalizer, cchardet |
| 杂项 | 10/10 | 0 | certifi, idna, pip, typing_extensions, pyparsing, cattrs, aiofiles, pytz, tabulate, autopage |
| 数据/验证 | 3/3 | 0 | pydantic v2、fastapi、pandas |
| 系统/进程 | 1/1 | 0 | psutil |
| 基础设施 | 1/1 | 0 | docker |
| MCP/AI SDK | 3/3 | 0 | mcp 1.27.1、rpds-py 2026.5.1、tiktoken 0.13.0 |
| **总计（可用）** | **97/97** | **0** | 所有已测试软件包均正常工作 |
| **总计（不可构建）** | — | **7** | scipy, uvloop, polars, pynacl, orjson, tokenizers, structlog |

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
| networkx | 3.6.1 | Graph 创建、add_edges_from、度计算全部正常 |

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
| msgpack | 1.1.2 | pack/unpack 正常 |
| lz4 | 4.4.5 | frame 压缩/解压缩正常（C 扩展，3 个 .so 文件需签名 + 后缀重命名） |
| zstd | 1.5.7 | 压缩/解压缩正常（C 扩展，1 个 .so 文件需签名 + 后缀重命名） |
| cbor2 | 6.1.1 | dumps/loads 正常（C 扩展，1 个 .so 文件需签名 + 后缀重命名） |
| ruamel.yaml | 0.19.1 | YAML 循环 dump/load 正常（纯 Python） |

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
| hiredis | 3.3.1 | Reader、pack_command 正常（C 扩展，1 个 .so 需签名 + 后缀重命名） |

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

### 系统/进程（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| psutil | 7.0.0 | cpu_count、virtual_memory、pids、Process 全部正常（见适配章节） |

### 数据/验证（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| pydantic v2 | 2.13.4 | BaseModel、model_dump_json、验证全部正常 |
| fastapi | 0.136.3 | FastAPI()、路由定义正常 |
| pandas | 3.0.3 | DataFrame、Series、groupby、date_range 全部正常 |

### 数据可视化（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| matplotlib | 3.10.3 | 折线图、直方图、散点图、柱状图、子图、等高线全部正常（mesonpy 构建，8 个 .so 需签名 + patchelf --add-needed libc++_shared.so + 后缀重命名） |
| contourpy | 1.3.3 | 等高线生成正常（C 扩展，需签名 + libc++_shared.so + 后缀重命名） |
| kiwisolver | 1.5.0 | 约束求解正常（C 扩展，需签名 + libc++_shared.so + 后缀重命名） |

### 序列化 — 扩展（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| msgpack | 1.1.1 | pack/unpack 正常 |

### Web/HTTP — 扩展（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| requests | 2.34.0 | HTTP GET 正常 |
| urllib3 | 2.7.0 | 导入正常 |
| flask | 3.1.3 | Flask() app、app_context、url_for 正常 |
| werkzeug | 3.1.8 | 导入正常 |
| django | 6.0.5 | Django VERSION 正常 |
| aiohttp | 3.12.14 | 异步 HTTP 客户端正常 |
| tornado | 6.5.1 | IOLoop 导入正常 |
| httpx | 0.28.1 | HTTP GET 正常（纯 Python） |
| uvicorn | 0.48.0 | 导入正常（纯 Python，ASGI 服务器） |
| websockets | 16.0 | 导入正常（纯 Python） |

### CLI/工具 — 扩展（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| click | 8.3.3 | 导入正常 |
| six | 1.17.0 | 导入正常 |
| colorama | 0.4.6 | Fore.GREEN 彩色输出正常 |
| tqdm | 4.67.3 | 导入正常 |
| rich | 15.0.0 | Console.print 正常（纯 Python） |

### 测试（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| pytest | 9.0.3 | 测试运行器正常（纯 Python） |

### MCP/AI SDK（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| mcp | 1.27.1 | FastMCP 服务器创建、工具注册、资源注册、提示注册、列出工具/资源/提示、jsonschema 验证 — 9/9 e2e 测试（纯 Python，依赖 rpds-py） |
| rpds-py | 2026.5.1 | HashTrieSet、HashTrieMap、List、Queue、Stack 全部正常（Rust/PyO3/maturin 构建，签名 .so + 重命名后缀） |
| tiktoken | 0.13.0 | cl100k_base 编码/解码正常（Rust/PyO3，1 个 .so 需签名 + 后缀重命名） |

### 杂项 — 扩展（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| certifi | 2026.4.22 | 导入正常 |
| charset_normalizer | 3.4.7 | 导入正常 |
| idna | 3.14 | 导入正常 |
| pip | 24.3.1 | pip 命令正常 |
| typing_extensions | 4.15.0 | 导入正常 |
| soupsieve | 2.8.3 | 导入正常 |
| pyparsing | 3.3.2 | 导入正常（纯 Python，matplotlib 依赖） |
| cattrs | 26.1.0 | dataclass unstructure 正常（纯 Python） |
| aiofiles | 24.1.0 | 异步文件 I/O 导入正常（纯 Python） |
| pytz | 2026.2 | 时区创建正常（纯 Python） |
| python-dateutil | 2.9.0 | 日期字符串解析正常（纯 Python） |
| tabulate | 0.9.0 | 表格格式化正常（纯 Python） |

### 基础设施（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| docker | 7.1.0 | 导入正常（纯 Python，Docker API 客户端） |

### 新增软件包 — 第二轮（全部通过）

#### 纯 Python 软件包（全部通过）

| 软件包 | 版本 | 测试 |
|---------|---------|------|
| toml | 0.10.2 | toml.loads/dumps 正常 |
| python-dateutil | 2.9.0 | 日期字符串解析正常 |
| aiofiles | 24.1.0 | 异步文件 I/O 导入正常 |
| loguru | 0.7.2 | logger.info 正常 |
| docutils | 0.23 | publish_string 正常 |
| pygments | 2.20.0 | 代码高亮到 HTML 正常 |
| passlib | 1.7.4 | sha256_crypt hash/verify 正常 |
| python-dotenv | 1.2.2 | load_dotenv 正常 |
| distro | 1.9.0 | distro.id() 正常 |
| packaging | 26.2 | Version 解析正常 |
| arrow | 1.4.0 | arrow.now(), shift() 正常 |
| schedule | 1.2.2 | schedule.every() 正常 |
| tenacity | 9.1.4 | retry 装饰器正常 |
| python-multipart | 0.0.29 | MultipartParser 导入正常 |
| wcwidth | 0.7.0 | wcwidth('A')=1, wcswidth('你好')=4 正常 |
| pyrsistent | 0.20.0 | pvector 不可变集合正常 |
| ijson | 3.5.0 | 流式 JSON 解析正常 |
| autopage | 0.6.0 | 终端分页正常 |

#### C 扩展软件包（全部通过）

| 软件包 | 版本 | 测试 | 备注 |
|---------|---------|------|------|
| msgpack | 1.1.2 | packb/unpackb 正常 | C 扩展，需签名 + 后缀重命名 |
| cchardet | 2.1.7 | UTF-8/ASCII 检测正常 | C 扩展，C++ — 需在 setup.py 中设置 `libraries=['c++_shared']`，签名 .so + 后缀重命名 |
| greenlet | 3.5.1 | greenlet 切换正常 | C 扩展 |
| bcrypt | 5.0.0 | hashpw/checkpw 正常 | C 扩展（Rust），需 CC/CXX 环境变量 |
| pycryptodome | 3.23.0 | AES 加密/解密正常 | C 扩展，abi3 wheel — 签名 .so + 后缀重命名 |
| charset_normalizer | 3.4.7 | 编码检测正常 | C 扩展，需签名 |
| wrapt | 2.2.1 | 装饰器包装正常 | 现为纯 Python wheel |

## 已适配 — 之前失败的软件包

| 软件包 | 错误 | 解决方案 | 状态 |
|---------|-------|----------|--------|
| bcrypt | linker `cc` not found | 在 pip install 前设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` | ✅ WORKS |
| greenlet | `c++` failed | 设置 `CC/CXX` 环境变量，构建后签名 .so | ✅ WORKS |
| pillow | `cc` failed, missing jpeg headers | 从源码编译 libjpeg-turbo 3.0.4 + libpng 1.6.48 | ✅ WORKS |
| lxml | libxml2/libxslt missing | 从源码编译 libxml2 2.14.0 + libxslt 1.1.42 | ✅ WORKS |
| cryptography | Rust/maturin build | libffi → cffi → maturin → OpenSSL → cryptography 依赖链 | ✅ WORKS |
| psutil | sockaddr_storage compile error | 修补 _common.py: LINUX 判断添加 `or sys.platform.startswith("harmonyos")`; 修补 net.c: 在 `#include <linux/if.h>` 前用 #define 防止 sockaddr_storage 重定义冲突 | ✅ WORKS |
| pydantic v2 | maturin 构建隔离 | 使用 `maturin build --release --interpreter $HOME/.local/bin/python3` 构建 pydantic-core，签名 .so，重命名后缀为 `.cpython-312-aarch64-linux-gnu.so`，手动安装 | ✅ WORKS |
| fastapi | 依赖 pydantic v2 | 先手动安装 pydantic-core，然后 `pip install fastapi --no-deps` | ✅ WORKS |
| matplotlib | mesonpy 构建，pybind11 pkg-config | 使用 mesonpy API 构建，签名 8 个 .so 文件，对每个 .so 执行 patchelf --add-needed libc++_shared.so，重命名后缀，手动安装；需要将 pybind11 的 pkgconfig 路径加入 PKG_CONFIG_PATH，依赖 setuptools_scm + vcs_versioning | ✅ WORKS |
| contourpy | C 扩展，缺少 libc++_shared.so | 签名 .so + patchelf --add-needed libc++_shared.so + 重命名后缀 | ✅ WORKS |
| kiwisolver | C 扩展，缺少 libc++_shared.so | 签名 .so + patchelf --add-needed libc++_shared.so + 重命名后缀 | ✅ WORKS |
| rpds-py | Rust/PyO3/maturin 构建 | 使用 `maturin build --release --interpreter $HOME/.local/bin/python3` 构建，签名 .so，重命名后缀为 `.cpython-312-aarch64-linux-gnu.so`，手动安装 | ✅ WORKS |
| mcp | 依赖 rpds-py | 先安装 rpds-py（maturin 构建），然后 `pip install mcp --no-deps` 并手动安装其余依赖（httpx_sse, pydantic-settings, python-dotenv, jsonschema, jsonschema-specifications, referencing, sse-starlette, starlette, anyio） | ✅ WORKS |
| tiktoken | Rust/PyO3，pip install 可用 | pip install 成功（Rust/PyO3 wheel 由 pip 构建），然后签名 .so + 重命名后缀 | ✅ WORKS |
| hiredis | C 扩展，pip install 可用 | 设置 CC/CXX 环境 pip install 成功，然后签名 .so + 重命名后缀 | ✅ WORKS |
| lz4 | C 扩展，pip install 可用 | 设置 CC/CXX 环境 pip install 成功，3 个 .so 文件需签名 + 后缀重命名 | ✅ WORKS |
| zstd | C 扩展，pip install 可用 | 设置 CC/CXX 环境 pip install 成功，1 个 .so 文件需签名 + 后缀重命名 | ✅ WORKS |
| cbor2 | C 扩展，pip install 可用 | pip install 成功，1 个 .so 文件需签名 + 后缀重命名 | ✅ WORKS |

## 无法构建的软件包

| 软件包 | 错误 | 原因 | 状态 |
|---------|-------|------|------|
| scipy | 需要 gfortran（Fortran 编译器） | HarmonyOS 没有 Fortran 编译器（gfortran）。scipy 的 C/Fortran 扩展模块无法编译。 | ❌ 无法构建 |
| uvloop | libuv 供应商无法在 HarmonyOS 上配置 | libuv 的 autoconf 无法猜测 HarmonyOS 平台；musl libc 缺少 cpu_set_t、CPU_SETSIZE 和 mmsghdr。需要对 libuv 源码进行大量修补。 | ❌ 无法构建 |
| polars | cargo metadata 失败 | Polars 是复杂的 Rust/PyO3 软件包；pip 构建时 cargo metadata 失败。需要下载源码手动构建。 | ❌ 无法构建（过于复杂） |
| pynacl | libsodium C 扩展 + cffi 版本冲突 | pip 构建隔离触发 cffi 2.0.0 重新构建失败（找不到 ffi.h）。已安装 cffi 1.17.1。需要手动编译 libsodium + 固定 cffi 版本。 | ❌ 无法构建（cffi 冲突） |
| paramiko (nacl 依赖) | 依赖 pynacl | pynacl 因 cffi 版本冲突无法构建。paramiko 本身是纯 Python，但没有 nacl.signing 无法运行。 | ❌ 导入失败（缺少 nacl） |
| orjson | maturin 构建脚本签名 | maturin 直接构建失败，因为 cargo 构建脚本是 ELF 可执行文件，在 HarmonyOS 上执行前需要签名 — 递归依赖（签名脚本 → cargo 重建 → 新的未签名脚本）。无法在 HarmonyOS 上通过 maturin 构建。 | ❌ 无法构建（maturin） |
| tokenizers | maturin 构建脚本签名 | 与 orjson 相同的 maturin 构建脚本签名问题。 | ❌ 无法构建（maturin） |
| structlog | 导入时段错误 | 导入时段错误（可能是日志状态冲突） | ❌ 导入失败（段错误） |

## 正在构建的软件包

| 软件包 | 错误 | 解决方案 | 状态 |
|---------|-------|----------|--------|
| pandas | meson sanity check Permission denied | 创建自动签名 clang wrapper 在 `$HOME/Claude/lib/meson_wrapper/clang`，使用 mesonpy API 构建，签名 45 个 .so，重命名后缀，手动安装 | ✅ WORKS |
| sharp | 无 openharmony-arm64 预编译 | 安装 `@img/sharp-wasm32` (WASM32 模式，较慢但功能完整) | ✅ WORKS (WASM32) |

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
| 纯 Python | 100% | requests, flask, jinja2, django, httpx, rich, pytest, pyparsing, toml, python-dateutil, aiofiles, loguru, docutils, pygments, passlib, python-dotenv, distro, packaging, arrow, schedule, tenacity, python-multipart, wcwidth, pyrsistent, ijson, autopage | 直接使用 pip 安装 |
| 基于 NumPy | 100% | numpy, after signing | 需要重命名 wheel + 签名 .so |
| 图像处理 | 100% | pillow | 从源码编译 libjpeg/libpng |
| XML 解析 | 100% | lxml | 从源码编译 libxml2/libxslt |
| 数据可视化 | 100% | matplotlib, contourpy, kiwisolver | mesonpy 构建 + 签名 .so + libc++_shared.so patchelf + 后缀重命名 |
| C/C++ 扩展 | 100% | bcrypt, greenlet, psutil, contourpy, kiwisolver, hiredis, lz4, zstd, cbor2, msgpack, cchardet, pycryptodome, charset_normalizer, wrapt | 设置 CC/CXX 环境; 部分需要 libc++_shared.so + 后缀重命名; psutil 需要 sockaddr_storage 补丁; wrapt 现为纯 Python wheel |
| 基于 Rust | 100% | cryptography, pydantic-core, rpds-py, tiktoken | 需要 CC 环境 + Rust 工具链; maturin 直接构建(不走 pip); tiktoken 可直接 pip install |
| pydantic v2 + fastapi | 100% | pydantic 2.13, fastapi 0.136 | 手动构建 pydantic-core + .so 重命名 + 签名 |
| 基于 Meson | 100% | pandas 3.0.3, matplotlib 3.10.3 | 自动签名 clang wrapper + mesonpy API 构建 + .so 签名+重命名; matplotlib 还需要 libc++_shared.so |
| MCP/AI SDK | 100% | mcp 1.27.1, rpds-py 2026.5.1, tiktoken 0.13.0 | rpds-py/tiktoken: maturin 构建 + 签名 + 重命名; mcp: 纯 Python（安装 rpds-py 后 pip install --no-deps） |
| Node.js WASM32 | 可用 | sharp (WASM32) | npm install --force @img/sharp-wasm32 |
| 依赖 Fortran | 0% | scipy | HarmonyOS 没有 Fortran 编译器 |
| 依赖 libuv | 0% | uvloop | libuv autoconf 无法在 HarmonyOS 上配置 |
| maturin 构建脚本 | 0% | orjson, tokenizers | Cargo 构建脚本是 ELF 可执行文件，执行前需要签名 — HarmonyOS 上的递归依赖 |

## lxml 的运行时要求

lxml 需要设置 `LD_LIBRARY_PATH` 以找到共享库：

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```

可以将此行添加到 `~/.zshenv` 中以持久化配置。

## 建议

1. **纯 Python 软件包**：直接使用 pip 安装，100% 兼容（httpx、rich、pytest、pyparsing、toml、python-dateutil、aiofiles、loguru、docutils、pygments、passlib、python-dotenv、distro、packaging、arrow、schedule、tenacity、python-multipart、wcwidth、pyrsistent、ijson、autopage 均可直接安装）
2. **numpy**：使用 HarmonyOS wheel + 签名扩展模块
3. **C/C++ 扩展软件包**：在 pip install 前设置 `CC=/data/service/hnp/bin/clang` 和 `CXX=/data/service/hnp/bin/clang++` 环境变量；C++ 扩展可能需要签名后 `patchelf --add-needed libc++_shared.so` + 后缀重命名
4. **基于 Rust 的软件包 (maturin)**：使用 `maturin build --release --interpreter $HOME/.local/bin/python3` 直接构建（不走 pip），然后签名 + 重命名 .so 后缀 + 修复 WHEEL 标签（空格→下划线）+ 手动安装到 site-packages。pip 的构建隔离会破坏 HarmonyOS 上的 maturin。适用于 pydantic-core、cryptography、rpds-py、tiktoken。
5. **psutil**：修补 `_common.py`（LINUX 判断添加 `or sys.platform.startswith("harmonyos")`) 和 `arch/linux/net.c`（用 #define 防止 sockaddr_storage 重定义冲突）。使用 `python3 setup.py build_ext` 构建 + 手动安装 + 签名 .so。
6. **pydantic v2 + fastapi**：用 maturin 构建匹配版本的 pydantic-core，签名 .so，重命名为 `.cpython-312-aarch64-linux-gnu.so`，安装到 site-packages，然后 `pip install pydantic fastapi --no-deps`。
7. **图像处理 (pillow)**：✅ 可用 - 已从源码编译 libjpeg-turbo 和 libpng
8. **XML 解析 (lxml)**：✅ 可用 - 已从源码编译 libxml2、libxslt 和 libexslt
9. **pandas**：✅ 可用 - 使用 mesonpy + 自动签名 clang wrapper 构建，45 个 .so 签名+重命名+手动安装
10. **matplotlib**：使用 mesonpy API 构建，需将 pybind11 的 pkgconfig 路径加入 PKG_CONFIG_PATH，依赖 setuptools_scm + vcs_versioning。8 个 .so 文件需签名 + `patchelf --add-needed libc++_shared.so` + 后缀重命名。详见 python-extension-adaptation.cn.md。
11. **orjson/tokenizers**：❌ 不可用 - maturin 构建脚本是 ELF 可执行文件，在 HarmonyOS 上执行前需要签名，造成递归依赖。可使用 msgpack 或 ijson 作为替代。
12. **Node.js 图像处理 (sharp)**：✅ 可用 - 使用 WASM32 模式 `npm install --force @img/sharp-wasm32`
13. **终端 UI (curses)**：不可用 - autoconf 问题，跳过依赖 curses 的应用
14. **scipy**：不可用 - 需要 gfortran（Fortran 编译器），HarmonyOS 上不存在
15. **uvloop**：不可用 - libuv 供应商无法在 HarmonyOS 上配置；musl libc 缺少 cpu_set_t/CPU_SETSIZE/mmsghdr
16. **MCP（模型上下文协议）**：✅ 可用 — mcp 1.27.1 正常工作。需要 rpds-py（Rust/PyO3，通过 maturin 构建），然后单独安装 mcp 及其依赖（httpx_sse、pydantic-settings、python-dotenv、jsonschema 等）。FastMCP 服务器创建、工具/资源/提示注册、jsonschema 验证均已验证 — 9/9 e2e 测试通过。
17. **pycryptodome**：✅ 可用 — abi3 wheel，签名 .so + 重命名后缀。AES 加密/解密已验证。
18. **cchardet**：✅ 可用 — C++ 扩展，需在 setup.py 中设置 `libraries=['c++_shared']`，签名 .so + 后缀重命名。编码检测已验证。
19. **新增纯 Python 工具库**：✅ toml、python-dateutil、aiofiles、loguru、docutils、pygments、passlib、python-dotenv、distro、packaging、arrow、schedule、tenacity、python-multipart、wcwidth、pyrsistent、ijson、autopage — 均可直接 pip install，100% 兼容。
