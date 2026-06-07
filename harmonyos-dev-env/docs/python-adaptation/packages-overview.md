# Python Package Compatibility — Category Overview

## Environment

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- Platform: HarmonyOS HongMeng Kernel 1.12.0, aarch64
- Test date: 2026-05-30 (Updated)

## Results Summary

| Category | PASS | FAIL | Notes |
|----------|------|------|-------|
| Core Python | 13/13 | 0 | json, datetime, hashlib, ctypes, sqlite3, csv, xml, multiprocessing, urllib, re, collections, asyncio, unittest |
| Data Processing | 5/5 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy, networkx |
| Math/Symbolic | 1/1 | 0 | sympy 1.14.0 (pure Python) |
| Data Visualization | 3/3 | 0 | matplotlib 3.10.3 (mesonpy build), contourpy 1.3.3, kiwisolver 1.5.0 |
| Image Processing | 1/1 | 0 | pillow 12.2.0 (compiled libjpeg/libpng) |
| XML Processing | 1/1 | 0 | lxml 6.1.0 (compiled libxml2/libxslt) |
| Web/HTTP | 17/17 | 0 | requests, urllib3, flask, werkzeug, django, aiohttp, tornado, httpx, uvicorn, websockets, python-multipart, starlette, sse-starlette, httpx_sse, multidict, yarl, frozenlist |
| Templates | 2/2 | 0 | jinja2, markupsafe |
| CLI/Utilities | 10/10 | 0 | click, six, colorama, tqdm, rich, autopep8, isort, flake8, black, invoke |
| Testing | 2/2 | 0 | pytest, tox |
| Security | 8/8 | 0 | itsdangerous, blinker, bcrypt, cryptography, cffi 2.0.0, hiredis, passlib, pycryptodome |
| Database | 1/1 | 0 | sqlalchemy (with greenlet) |
| Serialization | 11/11 | 0 | msgpack, lz4, zstd, cbor2, ruamel.yaml, ijson, toml, orjson, python-rapidjson, simplejson, ujson |
| RPC/Thrift | 1/1 | 0 | thrift 0.21.0 (pure Python) |
| Build Tools | 4/4 | 0 | setuptools, wheel, cython, packaging |
| Logging | 2/2 | 0 | loguru, structlog |
| Documentation | 1/1 | 0 | docutils |
| Syntax Highlighting | 1/1 | 0 | pygments |
| Config/Utils | 4/4 | 0 | python-dotenv, distro, wcwidth, pydantic-settings |
| Date/Time | 2/2 | 0 | python-dateutil, arrow |
| Scheduling | 1/1 | 0 | schedule |
| Retry/Resilience | 1/1 | 0 | tenacity |
| Data Structures | 2/2 | 0 | pyrsistent, cytoolz |
| Decorators | 1/1 | 0 | wrapt |
| Encoding Detection | 2/2 | 0 | charset_normalizer, cchardet |
| String/Fuzzy Matching | 3/3 | 0 | Levenshtein, rapidfuzz, regex |
| Hashing | 1/1 | 0 | xxhash |
| Misc | 10/10 | 0 | certifi, idna, pip, typing_extensions, pyparsing, cattrs, aiofiles, pytz, tabulate, autopage |
| Data/Validation | 6/6 | 0 | pydantic v2, fastapi, pandas, jsonschema, jsonschema-specifications, referencing |
| System/Process | 1/1 | 0 | psutil |
| Infrastructure | 1/1 | 0 | docker |
| MCP/AI SDK | 3/3 | 0 | mcp 1.27.1, rpds-py 2026.5.1, tiktoken 0.13.0 |
| ML/NLP | 3/3 | 0 | tokenizers 0.23.1, safetensors 0.7.0, transformers 5.10.2 |
| **Total (working)** | **130/130** | **0** | All tested packages work |
| **Total (cannot build)** | — | **4** | scipy, uvloop, polars, pynacl |

## Package Compatibility Categories

| Category | Works | Example | Notes |
|----------|-------|---------|-------|
| Pure Python | 100% | requests, flask, jinja2, django, httpx, rich, pytest, pyparsing, toml, python-dateutil, aiofiles, loguru, docutils, pygments, passlib, python-dotenv, distro, packaging, arrow, schedule, tenacity, python-multipart, wcwidth, pyrsistent, ijson, autopage, starlette, sse-starlette, httpx_sse, jsonschema, jsonschema-specifications, referencing, pydantic-settings, simplejson, autopep8, isort, structlog | pip install directly |
| NumPy-based | 100% | numpy, after signing | Need wheel rename + .so signing |
| Image processing | 100% | pillow | Compiled libjpeg/libpng from source |
| XML parsing | 100% | lxml | Compiled libxml2/libxslt from source |
| Data Visualization | 100% | matplotlib, contourpy, kiwisolver | mesonpy build + sign .so + libc++_shared.so patchelf + suffix rename |
| C/C++ extensions | 100% | bcrypt, greenlet, psutil, contourpy, kiwisolver, hiredis, lz4, zstd, cbor2, msgpack, cchardet, pycryptodome, charset_normalizer, wrapt, python-rapidjson, ujson, Levenshtein, rapidfuzz, xxhash, cytoolz | Set CC/CXX env; C++ extensions need libc++_shared.so patchelf + suffix rename; psutil needs sockaddr_storage patch; wrapt is now pure Python wheel |
| Rust-based | 100% | cryptography, pydantic-core, rpds-py, tiktoken, orjson, tokenizers, safetensors | Need CC env + Rust toolchain; maturin direct build (not pip); tiktoken pip install works directly; orjson needs rustc auto-sign wrapper + pre-compiled yyjson.a; tokenizers needs fancy-regex feature; safetensors simple maturin build |
| Pydantic v2 + fastapi | 100% | pydantic 2.13, fastapi 0.136 | Manual pydantic-core build + .so rename + signing |
| Meson-based | 100% | pandas 3.0.3, matplotlib 3.10.3 | Auto-sign clang wrapper + mesonpy API build + .so sign+rename; matplotlib also needs libc++_shared.so |
| MCP/AI SDK | 100% | mcp 1.27.1, rpds-py 2026.5.1, tiktoken 0.13.0 | rpds-py/tiktoken: maturin build + sign + rename; mcp: pure Python (pip install --no-deps after rpds-py) |
| ML/NLP | 100% | tokenizers 0.23.1, safetensors 0.7.0, transformers 5.10.2 | tokenizers/safetensors: Rust/PyO3/maturin + sign + rename; transformers: pure Python + version constraint patch + FP8 dtype patch |
| String/Fuzzy matching | 100% | Levenshtein, rapidfuzz, regex | C/C++ extension: sign .so + suffix rename; regex: prebuilt harmonyos wheel |
| Hashing | 100% | xxhash | C extension: sign .so + suffix rename |
| Node.js WASM32 | Works | sharp (WASM32) | npm install --force @img/sharp-wasm32 |
| Fortran-dependent | 0% | scipy | No Fortran compiler on HarmonyOS |
| libuv-dependent | 0% | uvloop | libuv autoconf can't configure on HarmonyOS |
| maturin build scripts (rustc auto-sign wrapper) | 100% | orjson, tokenizers, safetensors | All solved via rustc auto-sign wrapper; tokenizers also needs fancy-regex feature (replacing onig); safetensors simple maturin build |
| Logging (asyncio patch) | 100% | structlog | Fixed via logging/__init__.py patch (logAsyncioTasks = False) + sitecustomize.py (sys._logAsyncioTasks = False) |

## Compiled Native Libraries

| Library | Version | Location | Used By |
|---------|---------|----------|---------|
| libjpeg-turbo | 3.0.4 | `~/.local/lib/libjpeg.a` | pillow |
| libpng | 1.6.48 | `~/.local/lib/libpng16.a` | pillow |
| libxml2 | 2.14.0 | `~/.local/lib/libxml2.so` | lxml |
| libxslt | 1.1.42 | `~/.local/lib/libxslt.so` | lxml |
| libexslt | 1.1.42 | `~/.local/lib/libexslt.so` | lxml |
| libffi | 8 | `~/.local/lib/libffi.so.8` | cffi/cryptography |
| libopenblas | 0.3.28 | `~/.local/lib/libopenblas.so` | PyTorch/numpy |

## Runtime Requirements for lxml

lxml requires `LD_LIBRARY_PATH` to find shared libraries:

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```