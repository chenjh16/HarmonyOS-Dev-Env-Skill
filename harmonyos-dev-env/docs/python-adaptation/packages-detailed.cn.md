# Python 包兼容性 — 详细测试结果

## 核心 Python（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| json | built-in | dumps/loads 正常工作 |
| datetime | built-in | now() 正常工作 |
| hashlib | built-in | sha256 正常工作 |
| ctypes | built-in | CDLL("libc.so") 正常工作 |
| sqlite3 | built-in | 内存数据库正常工作 |
| csv | built-in | reader/writer 正常工作 |
| xml.etree.ElementTree | built-in | parse/generate 正常工作 |
| multiprocessing | built-in | Process/Queue 正常工作 |
| urllib | built-in | request 正常工作 |
| re | built-in | 正则表达式正常工作 |
| collections | built-in | defaultdict, Counter 正常工作 |
| asyncio | built-in | async/await 正常工作 |
| unittest | built-in | TestCase 正常工作 |

## 数据处理（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| numpy | 2.4.4 | array, random, linalg, sin 全部正常工作 |
| pyyaml | 6.0.3 | safe_load 正常工作 |
| beautifulsoup4 | 4.14.3 | HTML 解析正常工作 |
| networkx | 3.6.1 | Graph 创建, add_edges_from, 度计算全部正常工作 |

## 数学/符号计算（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| sympy | 1.14.0 | diff(x**2, x) = 2*x 正常工作 |

## 数据库/ORM（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| sqlalchemy | 2.0.49 | create_engine, Session, declarative_base 正常工作 |
| greenlet | 3.5.1 | greenlet 切换正常工作（sqlalchemy 依赖） |

## Web/HTTP（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| requests | 2.34.0 | HTTP GET 正常工作 |
| urllib3 | 2.7.0 | import 正常工作 |
| flask | 3.1.3 | Flask() app, app_context, url_for 正常工作 |
| werkzeug | 3.1.8 | import 正常工作 |
| django | 6.0.5 | Django VERSION 正常工作 |
| aiohttp | 3.13.5 | 异步 HTTP 客户端/服务端正常工作（e2e 已验证） |
| tornado | 6.5.1 | IOLoop import 正常工作 |
| httpx | 0.28.1 | HTTP GET 正常工作（纯 Python） |
| uvicorn | 0.48.0 | import 正常工作（纯 Python，ASGI 服务器） |
| websockets | 16.0 | import 正常工作（纯 Python） |
| starlette | 0.45.0 | ASGI 应用创建、路由处理正常工作（纯 Python） |
| sse-starlette | 3.4.4 | SSE 事件源 import 正常工作（纯 Python） |
| httpx_sse | 0.4.3 | SSE 传输 import 正常工作（纯 Python） |
| multidict | 6.4.0 | multimap import 正常工作（纯 Python） |
| yarl | 1.18.3 | URL 创建正常工作（纯 Python） |
| frozenlist | 1.5.0 | FrozenList 创建正常工作（纯 Python） |

## 序列化（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| msgpack | 1.1.2 | pack/unpack 正常工作 | C 扩展，需要签名 + 后缀重命名 |
| lz4 | 4.4.5 | frame 压缩/解压正常工作 | C 扩展，3 个 .so 文件需要签名 + 后缀重命名 |
| zstd | 1.5.7 | 压缩/解压正常工作 | C 扩展，1 个 .so 文件需要签名 + 后缀重命名 |
| cbor2 | 6.1.1 | dumps/loads 正常工作 | C 扩展，1 个 .so 文件需要签名 + 后缀重命名 |
| ruamel.yaml | 0.19.1 | YAML 往返 dump/load 正常工作 | 纯 Python |
| ijson | 3.5.0 | 迭代式 JSON 解析正常工作 | 纯 Python |
| toml | 0.10.2 | toml.loads/dumps 正常工作 | 纯 Python |
| orjson | 3.11.x | dumps/loads, UTF-8, datetime, numpy, dataclass, pretty print, sort keys — 8/8 e2e | Rust/PyO3/maturin 构建，使用 rustc 自动签名包装器 + 预编译 yyjson.a；参见 [rustc-wrapper.md](rustc-wrapper.md) |
| python-rapidjson | 1.23 | dumps/loads, datetime 序列化正常工作 | C 扩展（RapidJSON C++）：签名 .so + patchelf --add-needed libc++_shared.so + 后缀重命名 |
| simplejson | 4.1.1 | dumps/loads 正常工作 | 纯 Python（v4.1.1 是纯 Python wheel） |
| ujson | 5.12.1 | dumps/loads, 速度基准测试正常工作 | C 扩展：签名 .so + patchelf --add-needed libc++_shared.so + 后缀重命名 |

## 模板引擎（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| jinja2 | 3.1.6 | Template.render 正常工作 |
| markupsafe | 3.0.3 | escape 正常工作 |

## 命令行工具/实用程序（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| click | 8.3.3 | import 正常工作 |
| six | 1.17.0 | import 正常工作 |
| colorama | 0.4.6 | Fore.GREEN 彩色输出正常工作 |
| tqdm | 4.67.3 | import 正常工作 |
| rich | 15.0.0 | Console.print 正常工作（纯 Python） |
| autopep8 | 2.3.2 | 自动格式化 Python 代码正常工作（纯 Python） |
| isort | 8.0.1 | 排序 imports 正常工作（纯 Python） |
| flake8 | 7.3.0 | 代码检查正常工作（纯 Python） |
| black | 25.1.0 | 代码格式化正常工作（纯 Python） |
| invoke | 2.2.0 | 任务执行框架 import 正常工作（纯 Python） |

## 安全（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| itsdangerous | 2.2.0 | URLSafeSerializer 正常工作 | 纯 Python |
| blinker | 1.9.0 | import 正常工作 | 纯 Python |
| bcrypt | 5.0.0 | hashpw, gensalt, checkpw 正常工作 | Rust C 扩展，需要 CC/CXX 环境变量 + 签名 .so |
| cryptography | 48.0.0 | AES, RSA, ECDSA, hashes 全部正常工作 | 参见 cryptography-harmonyos.md |
| cffi | 2.0.0 | import 正常工作，FFI 正常工作 | 使用 LDFLAGS="-L$HOME/.local/lib" 重新构建以链接 libffi；签名 _cffi_backend.so + 后缀重命名 |
| hiredis | 3.3.1 | Reader, pack_command 正常工作 | C 扩展，1 个 .so 需要签名 + 后缀重命名 |
| passlib | 1.7.4 | sha256_crypt hash/verify 正常工作 | 纯 Python |
| pycryptodome | 3.23.0 | AES 加密/解密正常工作 | C 扩展，abi3 wheel — 签名 .so + 后缀重命名 |

## 构建工具（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| setuptools | 82.0.1 | import 正常工作 |
| wheel | 0.47.0 | import 正常工作 |
| cython | 3.2.4 | import 正常工作 |
| packaging | 26.2 | import 正常工作 |

## 数据/验证（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| pydantic v2 | 2.13.4 | BaseModel 创建, Field 验证 (gt=0), Optional 字段, model_dump_json, model_validate — 5/5 e2e | Rust/PyO3/maturin 构建（pydantic-core），签名 .so + 后缀重命名 |
| fastapi | 0.136.3 | FastAPI(), 路由定义正常工作 | 依赖 pydantic v2 |
| pandas | 3.0.3 | DataFrame, Series, groupby, date_range 全部正常工作 | Meson 构建使用自动签名包装器，45 个 .so 文件需要签名 + 重命名 |
| jsonschema | 4.26.0 | JSON Schema 验证正常工作 | 纯 Python |
| jsonschema-specifications | 2025.9.1 | JSON Schema 规范 import 正常工作 | 纯 Python |
| referencing | 0.37.0 | JSON 引用正常工作 | 纯 Python |

## 数据可视化（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| matplotlib | 3.10.3 | 折线图、直方图、散点图、柱状图、子图、等高线图全部正常工作 — 6/6 e2e | mesonpy 构建，8 个 .so 文件需要签名 + patchelf --add-needed libc++_shared.so + 后缀重命名 |
| contourpy | 1.3.3 | 等高线生成正常工作 | C 扩展，需要签名 + libc++_shared.so + 后缀重命名 |
| kiwisolver | 1.5.0 | 约束求解正常工作 | C 扩展，需要签名 + libc++_shared.so + 后缀重命名 |

## 日志（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| loguru | 0.7.2 | logger.info 正常工作 | 纯 Python |
| structlog | 25.5.0 | 结构化日志, get_logger, bind, 处理链, JSON 渲染器, 上下文变量, 异常日志, 延迟求值 — 8/8 e2e | 纯 Python；之前会段错误，通过 logging/__init__.py 补丁修复（logAsyncioTasks = False） |

## 测试（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| pytest | 9.0.3 | 测试运行器正常工作（纯 Python） |
| tox | 4.25.1 | 测试配置 import 正常工作（纯 Python） |

## MCP/AI SDK（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| mcp | 1.27.1 | FastMCP 服务器创建, tool/resource/prompt 注册, list tools/resources/prompts, jsonschema 验证 — 9/9 e2e | 纯 Python，依赖 rpds-py |
| rpds-py | 2026.5.1 | HashTrieSet, HashTrieMap, List, Queue, Stack 全部正常工作 | Rust/PyO3/maturin 构建，签名 .so + 后缀重命名 |
| tiktoken | 0.13.0 | cl100k_base encode/decode 正常工作 | Rust/PyO3，1 个 .so 需要签名 + 后缀重命名 |

## ML/NLP（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| tokenizers | 0.23.1 | encode, decode, batch_encode, batch_decode, from_pretrained, save, truncation, padding, special tokens, word piece — 10/10 e2e | Rust/PyO3/maturin 构建，使用 rustc 自动签名包装器 + **fancy-regex** 特性（替代 onig）；abi3 wheel；签名 .so + 后缀重命名 |
| safetensors | 0.7.0 | save/load tensors 正常工作，与 PyTorch/transformers 兼容 | Rust/PyO3/maturin 构建，使用 rustc 自动签名包装器；abi3 wheel；签名 .so + 后缀重命名 |
| transformers | 5.10.2 | GPT-2/BERT 模型创建, forward pass, generation, tokenizer, safetensors save/load, AutoConfig — 8/8 e2e | 纯 Python；两个补丁：(1) dependency_versions_table.py tokenizers 约束 `<=0.23.0` → `>=0.22.0`；(2) finegrained_fp8.py `torch.float8_e8m0fnu` → `getattr(torch, "float8_e8m0fnu", torch.float8_e4m3fn)` |

## 字符串/模糊匹配（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| Levenshtein | 0.27.3 | 编辑距离, 相似度计算正常工作 | rapidfuzz C 扩展：签名 .so + 后缀重命名 |
| rapidfuzz | 3.14.5 | 模糊匹配, process.extract 正常工作 | C++ 扩展：签名 .so + 后缀重命名 |
| regex | 2026.5.9 | 模式匹配, 模糊搜索正常工作 | C 扩展：预构建 harmonyos wheel，仅需后缀重命名 |

## 哈希（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| xxhash | 3.7.0 | xxh32/xxh64/xxh3_64 哈希正常工作 | C 扩展：签名 .so + 后缀重命名 |

## 数据结构（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| pyrsistent | 0.20.0 | pvector 不可变集合正常工作 | 纯 Python |
| cytoolz | 1.1.0 | dicttoolz.merge, itertoolz.groupby, functoolz.curry 正常工作 | C 扩展（Cython）：签名 .so + patchelf --add-needed libc++_shared.so + 后缀重命名（共 5 个 .so 文件） |

## 编码检测（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| charset_normalizer | 3.4.7 | 检测编码正常工作 | C 扩展，需要签名 |
| cchardet | 2.1.7 | 检测 UTF-8/ASCII 正常工作 | C 扩展（C++）：需要在 setup.py 中设置 `libraries=['c++_shared']`，签名 .so + 后缀重命名 |

## 系统/进程（全部通过）

| 包 | 版本 | 测试 | 说明 |
|---------|---------|------|-------|
| psutil | 7.0.0 | cpu_count, virtual_memory, pids, Process 全部正常工作 | 补丁 _common.py + net.c（参见 extension-guide.md） |

## 杂项（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| certifi | 2026.4.22 | import 正常工作 |
| idna | 3.14 | import 正常工作 |
| pip | 24.3.1 | pip 命令正常工作 |
| typing_extensions | 4.15.0 | import 正常工作 |
| pyparsing | 3.3.2 | import 正常工作（纯 Python，matplotlib 依赖） |
| cattrs | 26.1.0 | unstructure dataclass 正常工作（纯 Python） |
| aiofiles | 24.1.0 | 异步文件 I/O import 正常工作（纯 Python） |
| pytz | 2026.2 | 时区创建正常工作（纯 Python） |
| python-dateutil | 2.9.0 | 日期字符串解析正常工作（纯 Python） |
| tabulate | 0.9.0 | 表格格式化正常工作（纯 Python） |
| autopage | 0.6.0 | 终端分页正常工作（纯 Python） |
| soupsieve | 2.8.3 | import 正常工作（纯 Python） |
| python-multipart | 0.0.29 | MultipartParser import 正常工作（纯 Python） |
| wcwidth | 0.7.0 | wcwidth('A')=1, wcswidth('你好')=4 正常工作（纯 Python） |
| schedule | 1.2.2 | schedule.every() 正常工作（纯 Python） |
| tenacity | 9.1.4 | retry 装饰器正常工作（纯 Python） |
| arrow | 1.4.0 | arrow.now(), shift() 正常工作（纯 Python） |
| distro | 1.9.0 | distro.id() 正常工作（纯 Python） |
| python-dotenv | 1.2.2 | load_dotenv 正常工作（纯 Python） |
| docutils | 0.23 | publish_string 正常工作（纯 Python） |
| pygments | 2.20.0 | 代码高亮到 HTML 正常工作（纯 Python） |

## 基础设施（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| docker | 7.1.0 | import 正常工作（纯 Python，Docker API 客户端） |

## 装饰器（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| wrapt | 2.2.1 | 装饰器包装正常工作 | 现为纯 Python wheel |

## 配置/工具（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|-------|
| python-dotenv | 1.2.2 | load_dotenv 正常工作（纯 Python） |
| distro | 1.9.0 | distro.id() 正常工作（纯 Python） |
| wcwidth | 0.7.0 | wcwidth('A')=1, wcswidth('你好')=4 正常工作（纯 Python） |
| pydantic-settings | 2.14.1 | BaseSettings 创建, 环境变量加载正常工作（纯 Python） |

## RPC/Thrift（全部通过）

| 包 | 版本 | 测试 |
|---------|---------|------|
| thrift | 0.21.0 | TProtocol import 正常工作（纯 Python） |