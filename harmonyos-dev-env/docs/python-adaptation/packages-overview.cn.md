# Python 包兼容性 — 分类概览

## 环境

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- 平台: HarmonyOS HongMeng Kernel 1.12.0, aarch64
- 测试日期: 2026-06-07 (更新)

## 结果摘要

| 类别 | 通过 | 失败 | 说明 |
|------|------|------|------|
| 核心 Python | 13/13 | 0 | json, datetime, hashlib, ctypes, sqlite3, csv, xml, multiprocessing, urllib, re, collections, asyncio, unittest |
| 数据处理 | 5/5 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy, networkx |
| 数学/符号计算 | 1/1 | 0 | sympy 1.14.0 (纯 Python) |
| 数据可视化 | 3/3 | 0 | matplotlib 3.10.3 (mesonpy 构建), contourpy 1.3.3, kiwisolver 1.5.0 |
| 图像处理 | 1/1 | 0 | pillow 12.2.0 (编译 libjpeg/libpng) |
| XML 处理 | 1/1 | 0 | lxml 6.1.0 (编译 libxml2/libxslt) |
| Web/HTTP | 17/17 | 0 | requests, urllib3, flask, werkzeug, django, aiohttp, tornado, httpx, uvicorn, websockets, python-multipart, starlette, sse-starlette, httpx_sse, multidict, yarl, frozenlist |
| 模板引擎 | 2/2 | 0 | jinja2, markupsafe |
| CLI/工具 | 10/10 | 0 | click, six, colorama, tqdm, rich, autopep8, isort, flake8, black, invoke |
| 测试 | 2/2 | 0 | pytest, tox |
| 安全 | 8/8 | 0 | itsdangerous, blinker, bcrypt, cryptography, cffi 2.0.0, hiredis, passlib, pycryptodome |
| 数据库 | 1/1 | 0 | sqlalchemy (含 greenlet) |
| 序列化 | 11/11 | 0 | msgpack, lz4, zstd, cbor2, ruamel.yaml, ijson, toml, orjson, python-rapidjson, simplejson, ujson |
| 序列化/作业 | 3/3 | 0 | joblib, cloudpickle, dill |
| 文件监控 | 1/1 | 0 | watchdog |
| 文档格式 | 6/6 | 0 | openpyxl, xlrd, xlwt, python-docx, odfpy, reportlab |
| 标记语言 | 1/1 | 0 | markdown |
| 测试/质量 | 4/4 | 0 | coverage, mock, mypy, pylint |
| 配置 | 2/2 | 0 | omegaconf, hydra-core |
| 网络/地址 | 1/1 | 0 | netaddr |
| 网络/数据库 | 3/3 | 0 | redis, pymongo, asyncpg |
| CLI/TUI | 2/2 | 0 | rich_click, textual |
| Web/CORS | 1/1 | 0 | aiohttp_cors |
| 任务队列 | 1/1 | 0 | celery |
| ML/优化 | 1/1 | 0 | optuna |
| ML/NLP扩展 | 2/2 | 0 | langchain (2/3 e2e), langchain-core (2/3 e2e) — 缺uuid_utils |
| 图像/IO | 1/1 | 0 | imageio |
| 音频 | 1/1 | 0 | pydub |
| 安全/XML | 1/1 | 0 | defusedxml |
| 进程/守护 | 2/2 | 0 | daemonize, supervisor |
| RPC/Thrift | 1/1 | 0 | thrift 0.21.0 (纯 Python) |
| 构建工具 | 4/4 | 0 | setuptools, wheel, cython, packaging |
| 日志 | 2/2 | 0 | loguru, structlog |
| 文档 | 1/1 | 0 | docutils |
| 语法高亮 | 1/1 | 0 | pygments |
| 配置/工具 | 4/4 | 0 | python-dotenv, distro, wcwidth, pydantic-settings |
| 日期/时间 | 2/2 | 0 | python-dateutil, arrow |
| 调度 | 1/1 | 0 | schedule |
| 重试/容错 | 1/1 | 0 | tenacity |
| 数据结构 | 2/2 | 0 | pyrsistent, cytoolz |
| 装饰器 | 1/1 | 0 | wrapt |
| 编码检测 | 2/2 | 0 | charset_normalizer, cchardet |
| 字符串/模糊匹配 | 3/3 | 0 | Levenshtein, rapidfuzz, regex |
| 哈希 | 1/1 | 0 | xxhash |
| 其他 | 10/10 | 0 | certifi, idna, pip, typing_extensions, pyparsing, cattrs, aiofiles, pytz, tabulate, autopage |
| 数据/验证 | 6/6 | 0 | pydantic v2, fastapi, pandas, jsonschema, jsonschema-specifications, referencing |
| 系统/进程 | 1/1 | 0 | psutil |
| 基础设施 | 1/1 | 0 | docker |
| MCP/AI SDK | 3/3 | 0 | mcp 1.27.1, rpds-py 2026.5.1, tiktoken 0.13.0 |
| ML/NLP | 3/3 | 0 | tokenizers 0.23.1, safetensors 0.7.0, transformers 5.10.2 |
| **总计 (可用)** | **164/164** | **0** | 所有测试包均可用 |
| **总计 (无法构建)** | — | **14** | grpcio, h5py, pyarrow, scikit-learn, xgboost, lightgbm, numcodecs, numexpr, psycopg, psycopg2, soundfile, zarr(部分), scipy, uvloop |

## 包兼容性分类

| 类别 | 可用 | 示例 | 说明 |
|------|------|------|------|
| 纯 Python | 100% | requests, flask, jinja2, django, httpx, rich, pytest, pyparsing, toml, python-dateutil, aiofiles, loguru, docutils, pygments, passlib, python-dotenv, distro, packaging, arrow, schedule, tenacity, python-multipart, wcwidth, pyrsistent, ijson, autopage, starlette, sse-starlette, httpx_sse, jsonschema, jsonschema-specifications, referencing, pydantic-settings, simplejson, autopep8, isort, structlog, joblib, cloudpickle, dill, watchdog, openpyxl, xlrd, xlwt, python-docx, odfpy, reportlab, markdown, coverage, mock, pylint, omegaconf, hydra-core, netaddr, redis, pymongo, rich_click, textual, aiohttp_cors, celery, optuna, langchain, langchain-core, imageio, pydub, defusedxml, daemonize, supervisor | 直接 pip install |
| 基于 NumPy | 100% | numpy, 签名后 | 需要 wheel 重命名 + .so 签名 |
| 图像处理 | 100% | pillow | 从源码编译 libjpeg/libpng |
| XML 解析 | 100% | lxml | 从源码编译 libxml2/libxslt |
| 数据可视化 | 100% | matplotlib, contourpy, kiwisolver | mesonpy 构建 + 签名 .so + libc++_shared.so patchelf + 后缀重命名 |
| C/C++ 扩展 | 100% | bcrypt, greenlet, psutil, contourpy, kiwisolver, hiredis, lz4, zstd, cbor2, msgpack, cchardet, pycryptodome, charset_normalizer, wrapt, python-rapidjson, ujson, Levenshtein, rapidfuzz, xxhash, cytoolz, asyncpg | 设置 CC/CXX 环境变量；C++ 扩展需要 libc++_shared.so patchelf + 后缀重命名；psutil 需要 sockaddr_storage 补丁；wrapt 现为纯 Python wheel；asyncpg：CC/CXX + 签名 .so + 后缀重命名 |
| 基于 Rust | 100% | cryptography, pydantic-core, rpds-py, tiktoken, orjson, tokenizers, safetensors | 需要 CC 环境变量 + Rust 工具链；maturin 直接构建（非 pip）；tiktoken 可直接 pip install；orjson 需要 rustc 自动签名包装器 + 预编译 yyjson.a；tokenizers 需要 fancy-regex 特性；safetensors 简单 maturin build |
| Pydantic v2 + fastapi | 100% | pydantic 2.13, fastapi 0.136 | 手动构建 pydantic-core + .so 重命名 + 签名 |
| 基于 Meson | 100% | pandas 3.0.3, matplotlib 3.10.3 | 自动签名 clang 包装器 + mesonpy API 构建 + .so 签名+重命名；matplotlib 还需要 libc++_shared.so |
| MCP/AI SDK | 100% | mcp 1.27.1, rpds-py 2026.5.1, tiktoken 0.13.0 | rpds-py/tiktoken: maturin build + 签名 + 重命名；mcp: 纯 Python (rpds-py 安装后 pip install --no-deps) |
| ML/NLP | 100% | tokenizers 0.23.1, safetensors 0.7.0, transformers 5.10.2 | tokenizers/safetensors: Rust/PyO3/maturin + 签名 + 重命名；transformers: 纯 Python + 版本约束补丁 + FP8 dtype 补丁 |
| 字符串/模糊匹配 | 100% | Levenshtein, rapidfuzz, regex | C/C++ 扩展：签名 .so + 后缀重命名；regex: 预构建 harmonyos wheel |
| 哈希 | 100% | xxhash | C 扩展：签名 .so + 后缀重命名 |
| Node.js WASM32 | 可用 | sharp (WASM32) | npm install --force @img/sharp-wasm32 |
| 依赖 Fortran | 0% | scipy | HarmonyOS 无 Fortran 编译器 |
| 依赖 libuv | 0% | uvloop | libuv autoconf 无法在 HarmonyOS 上配置 |
| maturin 构建脚本 (rustc 自动签名包装器) | 100% | orjson, tokenizers, safetensors | 均通过 rustc 自动签名包装器解决；tokenizers 还需要 fancy-regex 特性（替代 onig）；safetensors 简单 maturin build |
| 日志 (asyncio 补丁) | 100% | structlog | 通过 logging/__init__.py 补丁 (logAsyncioTasks = False) + sitecustomize.py (sys._logAsyncioTasks = False) 修复 |

## 已编译原生库

| 库名 | 版本 | 位置 | 被使用于 |
|------|------|------|----------|
| libjpeg-turbo | 3.0.4 | `~/.local/lib/libjpeg.a` | pillow |
| libpng | 1.6.48 | `~/.local/lib/libpng16.a` | pillow |
| libxml2 | 2.14.0 | `~/.local/lib/libxml2.so` | lxml |
| libxslt | 1.1.42 | `~/.local/lib/libxslt.so` | lxml |
| libexslt | 1.1.42 | `~/.local/lib/libexslt.so` | lxml |
| libffi | 8 | `~/.local/lib/libffi.so.8` | cffi/cryptography |
| libopenblas | 0.3.28 | `~/.local/lib/libopenblas.so` | PyTorch/numpy |

## lxml 运行时要求

lxml 需要 `LD_LIBRARY_PATH` 来查找共享库：

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```