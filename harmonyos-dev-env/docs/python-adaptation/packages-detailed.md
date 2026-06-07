# Python Package Compatibility — Detailed Per-Package Test Results

## Core Python (All PASS)

| Package | Version | Test |
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

## Data Processing (All PASS)

| Package | Version | Test |
|---------|---------|------|
| numpy | 2.4.4 | array, random, linalg, sin all work |
| pyyaml | 6.0.3 | safe_load works |
| beautifulsoup4 | 4.14.3 | HTML parsing works |
| networkx | 3.6.1 | Graph creation, add_edges_from, degree calculation all work |

## Math/Symbolic (All PASS)

| Package | Version | Test |
|---------|---------|------|
| sympy | 1.14.0 | diff(x**2, x) = 2*x works |

## Database/ORM (All PASS)

| Package | Version | Test |
|---------|---------|------|
| sqlalchemy | 2.0.49 | create_engine, Session, declarative_base work |
| greenlet | 3.5.1 | greenlet switching works (sqlalchemy dependency) |

## Web/HTTP (All PASS)

| Package | Version | Test |
|---------|---------|------|
| requests | 2.34.0 | HTTP GET works |
| urllib3 | 2.7.0 | import works |
| flask | 3.1.3 | Flask() app, app_context, url_for work |
| werkzeug | 3.1.8 | import works |
| django | 6.0.5 | Django VERSION works |
| aiohttp | 3.13.5 | async HTTP client/server works (e2e confirmed) |
| tornado | 6.5.1 | IOLoop import works |
| httpx | 0.28.1 | HTTP GET works (pure Python) |
| uvicorn | 0.48.0 | import works (pure Python, ASGI server) |
| websockets | 16.0 | import works (pure Python) |
| starlette | 0.45.0 | ASGI app creation, route handling works (pure Python) |
| sse-starlette | 3.4.4 | SSE event source import works (pure Python) |
| httpx_sse | 0.4.3 | SSE transport import works (pure Python) |
| multidict | 6.4.0 | multimap import works (pure Python) |
| yarl | 1.18.3 | URL creation works (pure Python) |
| frozenlist | 1.5.0 | FrozenList creation works (pure Python) |

## Serialization (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| msgpack | 1.1.2 | pack/unpack works | C extension, needs sign + suffix rename |
| lz4 | 4.4.5 | frame compress/decompress works | C extension, 3 .so files need sign + suffix rename |
| zstd | 1.5.7 | compress/decompress works | C extension, 1 .so file needs sign + suffix rename |
| cbor2 | 6.1.1 | dumps/loads works | C extension, 1 .so file needs sign + suffix rename |
| ruamel.yaml | 0.19.1 | YAML roundtrip dump/load works | pure Python |
| ijson | 3.5.0 | iterative JSON parsing works | pure Python |
| toml | 0.10.2 | toml.loads/dumps works | pure Python |
| orjson | 3.11.x | dumps/loads, UTF-8, datetime, numpy, dataclass, pretty print, sort keys — 8/8 e2e | Rust/PyO3/maturin build with rustc auto-sign wrapper + pre-compiled yyjson.a; see [rustc-wrapper.md](rustc-wrapper.md) |
| python-rapidjson | 1.23 | dumps/loads, datetime serialization works | C extension (RapidJSON C++): sign .so + patchelf --add-needed libc++_shared.so + rename suffix |
| simplejson | 4.1.1 | dumps/loads works | pure Python (v4.1.1 is pure Python wheel) |
| ujson | 5.12.1 | dumps/loads, speed benchmark works | C extension: sign .so + patchelf --add-needed libc++_shared.so + rename suffix |

## Templates (All PASS)

| Package | Version | Test |
|---------|---------|------|
| jinja2 | 3.1.6 | Template.render works |
| markupsafe | 3.0.3 | escape works |

## CLI/Utilities (All PASS)

| Package | Version | Test |
|---------|---------|------|
| click | 8.3.3 | import works |
| six | 1.17.0 | import works |
| colorama | 0.4.6 | Fore.GREEN colored output works |
| tqdm | 4.67.3 | import works |
| rich | 15.0.0 | Console.print works (pure Python) |
| autopep8 | 2.3.2 | auto-format Python code works (pure Python) |
| isort | 8.0.1 | sort imports works (pure Python) |
| flake8 | 7.3.0 | code linting works (pure Python) |
| black | 25.1.0 | code formatting works (pure Python) |
| invoke | 2.2.0 | task execution framework import works (pure Python) |

## Security (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| itsdangerous | 2.2.0 | URLSafeSerializer works | pure Python |
| blinker | 1.9.0 | import works | pure Python |
| bcrypt | 5.0.0 | hashpw, gensalt, checkpw work | C extension via Rust, needs CC/CXX env + sign .so |
| cryptography | 48.0.0 | AES, RSA, ECDSA, hashes all work | see cryptography-harmonyos.md |
| cffi | 2.0.0 | import works, FFI works | rebuilt with LDFLAGS="-L$HOME/.local/lib" for libffi path; sign _cffi_backend.so + rename suffix |
| hiredis | 3.3.1 | Reader, pack_command work | C extension, 1 .so needs sign + suffix rename |
| passlib | 1.7.4 | sha256_crypt hash/verify works | pure Python |
| pycryptodome | 3.23.0 | AES encrypt/decrypt works | C extension, abi3 wheel — sign .so + suffix rename |

## Build Tools (All PASS)

| Package | Version | Test |
|---------|---------|------|
| setuptools | 82.0.1 | import works |
| wheel | 0.47.0 | import works |
| cython | 3.2.4 | import works |
| packaging | 26.2 | import works |

## Data/Validation (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| pydantic v2 | 2.13.4 | BaseModel creation, Field validation (gt=0), Optional fields, model_dump_json, model_validate — 5/5 e2e | Rust/PyO3/maturin build (pydantic-core), sign .so + rename suffix |
| fastapi | 0.136.3 | FastAPI(), route definition works | Depends on pydantic v2 |
| pandas | 3.0.3 | DataFrame, Series, groupby, date_range all work | Meson build with auto-sign wrapper, 45 .so files need sign + rename |
| jsonschema | 4.26.0 | JSON Schema validation works | pure Python |
| jsonschema-specifications | 2025.9.1 | JSON Schema specs import works | pure Python |
| referencing | 0.37.0 | JSON referencing works | pure Python |

## Data Visualization (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| matplotlib | 3.10.3 | line plot, histogram, scatter, bar chart, subplots, contour all work — 6/6 e2e | mesonpy build, 8 .so files need sign + patchelf --add-needed libc++_shared.so + suffix rename |
| contourpy | 1.3.3 | contour generation works | C extension, needs sign + libc++_shared.so + suffix rename |
| kiwisolver | 1.5.0 | constraint solving works | C extension, needs sign + libc++_shared.so + suffix rename |

## Logging (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| loguru | 0.7.2 | logger.info works | pure Python |
| structlog | 25.5.0 | structured logging, get_logger, bind, process chain, JSON renderer, context vars, exception logging, lazy evaluation — 8/8 e2e | pure Python; previously segfault, fixed via logging/__init__.py patch (logAsyncioTasks = False) |

## Testing (All PASS)

| Package | Version | Test |
|---------|---------|------|
| pytest | 9.0.3 | test runner works (pure Python) |
| tox | 4.25.1 | test config import works (pure Python) |

## MCP/AI SDK (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| mcp | 1.27.1 | FastMCP server creation, tool/resource/prompt registration, list tools/resources/prompts, jsonschema validation — 9/9 e2e | pure Python, depends on rpds-py |
| rpds-py | 2026.5.1 | HashTrieSet, HashTrieMap, List, Queue, Stack all work | Rust/PyO3/maturin build, sign .so + rename suffix |
| tiktoken | 0.13.0 | cl100k_base encode/decode works | Rust/PyO3, 1 .so needs sign + suffix rename |

## ML/NLP (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| tokenizers | 0.23.1 | encode, decode, batch_encode, batch_decode, from_pretrained, save, truncation, padding, special tokens, word piece — 10/10 e2e | Rust/PyO3/maturin build with rustc auto-sign wrapper + **fancy-regex** feature (replacing onig); abi3 wheel; sign .so + rename suffix |
| safetensors | 0.7.0 | save/load tensors works, compatible with PyTorch/transformers | Rust/PyO3/maturin build with rustc auto-sign wrapper; abi3 wheel; sign .so + rename suffix |
| transformers | 5.10.2 | GPT-2/BERT model creation, forward pass, generation, tokenizer, safetensors save/load, AutoConfig — 8/8 e2e | pure Python; two patches: (1) dependency_versions_table.py tokenizers constraint `<=0.23.0` → `>=0.22.0`; (2) finegrained_fp8.py `torch.float8_e8m0fnu` → `getattr(torch, "float8_e8m0fnu", torch.float8_e4m3fn)` |

## String/Fuzzy Matching (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| Levenshtein | 0.27.3 | edit distance, ratio calculation works | C extension via rapidfuzz: sign .so + rename suffix |
| rapidfuzz | 3.14.5 | fuzzy matching, process.extract works | C++ extension: sign .so + rename suffix |
| regex | 2026.5.9 | pattern matching, fuzzy search works | C extension: prebuilt harmonyos wheel, rename suffix only |

## Hashing (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| xxhash | 3.7.0 | xxh32/xxh64/xxh3_64 hash works | C extension: sign .so + rename suffix |

## Data Structures (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| pyrsistent | 0.20.0 | pvector immutable collections works | pure Python |
| cytoolz | 1.1.0 | dicttoolz.merge, itertoolz.groupby, functoolz.curry works | C extension (Cython): sign .so + patchelf --add-needed libc++_shared.so + rename suffix (all 5 .so files) |

## Encoding Detection (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| charset_normalizer | 3.4.7 | detect encoding works | C extension, needs sign |
| cchardet | 2.1.7 | detect UTF-8/ASCII works | C extension (C++): needs `libraries=['c++_shared']` in setup.py, sign .so + suffix rename |

## System/Process (All PASS)

| Package | Version | Test | Notes |
|---------|---------|------|-------|
| psutil | 7.0.0 | cpu_count, virtual_memory, pids, Process all work | Patch _common.py + net.c (see extension-guide.md) |

## Misc (All PASS)

| Package | Version | Test |
|---------|---------|------|
| certifi | 2026.4.22 | import works |
| idna | 3.14 | import works |
| pip | 24.3.1 | pip commands work |
| typing_extensions | 4.15.0 | import works |
| pyparsing | 3.3.2 | import works (pure Python, matplotlib dependency) |
| cattrs | 26.1.0 | unstructure dataclass works (pure Python) |
| aiofiles | 24.1.0 | async file I/O import works (pure Python) |
| pytz | 2026.2 | timezone creation works (pure Python) |
| python-dateutil | 2.9.0 | date string parsing works (pure Python) |
| tabulate | 0.9.0 | table formatting works (pure Python) |
| autopage | 0.6.0 | terminal paging works (pure Python) |
| soupsieve | 2.8.3 | import works (pure Python) |
| python-multipart | 0.0.29 | MultipartParser import works (pure Python) |
| wcwidth | 0.7.0 | wcwidth('A')=1, wcswidth('你好')=4 works (pure Python) |
| schedule | 1.2.2 | schedule.every() works (pure Python) |
| tenacity | 9.1.4 | retry decorator works (pure Python) |
| arrow | 1.4.0 | arrow.now(), shift() works (pure Python) |
| distro | 1.9.0 | distro.id() works (pure Python) |
| python-dotenv | 1.2.2 | load_dotenv works (pure Python) |
| docutils | 0.23 | publish_string works (pure Python) |
| pygments | 2.20.0 | highlight code to HTML works (pure Python) |

## Infrastructure (All PASS)

| Package | Version | Test |
|---------|---------|------|
| docker | 7.1.0 | import works (pure Python, Docker API client) |

## Decorators (All PASS)

| Package | Version | Test |
|---------|---------|------|
| wrapt | 2.2.1 | decorator wrapping works | now pure Python wheel |

## Config/Utils (All PASS)

| Package | Version | Test |
|---------|---------|------|-------|
| python-dotenv | 1.2.2 | load_dotenv works (pure Python) |
| distro | 1.9.0 | distro.id() works (pure Python) |
| wcwidth | 0.7.0 | wcwidth('A')=1, wcswidth('你好')=4 works (pure Python) |
| pydantic-settings | 2.14.1 | BaseSettings creation, env variable loading works (pure Python) |

## RPC/Thrift (All PASS)

| Package | Version | Test |
|---------|---------|------|-------|
| thrift | 0.21.0 | TProtocol import works (pure Python) |