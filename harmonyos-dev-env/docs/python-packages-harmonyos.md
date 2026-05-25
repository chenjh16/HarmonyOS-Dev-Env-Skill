# HarmonyOS Python Package Compatibility Report

## Test Date: 2026-05-20 (Updated)

## Environment

- Python: `$HOME/.local/bin/python3` (3.12.8)
- pip: 24.3.1
- Platform: HarmonyOS HongMeng Kernel 1.12.0, aarch64

## Results Summary

| Category | PASS | FAIL | Notes |
|----------|------|------|-------|
| Core Python | 5/5 | 0 | pickle, datetime, ctypes, json, hashlib |
| Data Processing | 4/4 | 0 | numpy, pyyaml, beautifulsoup4, sqlalchemy |
| Image Processing | 1/1 | 0 | pillow 12.2.0 (compiled libjpeg/libpng) |
| XML Processing | 1/1 | 0 | lxml 6.1.0 (compiled libxml2/libxslt) |
| Web/HTTP | 4/4 | 0 | requests, urllib3, flask, werkzeug |
| Templates | 2/2 | 0 | jinja2, markupsafe |
| CLI/Utilities | 4/4 | 0 | click, six, colorama, tqdm |
| Security | 3/3 | 0 | itsdangerous, blinker, bcrypt |
| Database | 1/1 | 0 | sqlalchemy (with greenlet) |
| Build Tools | 4/4 | 0 | setuptools, wheel, cython, packaging |
| Misc | 5/5 | 0 | certifi, charset_normalizer, idna, pip, typing_extensions |
| **Total** | **34/34** | **0** | All installed packages work |

## Detailed Test Results

### Core Python (All PASS)

| Package | Version | Test |
|---------|---------|------|
| pickle | built-in | dumps/loads works |
| datetime | built-in | now() works |
| ctypes | built-in | CDLL("libc.so") works |
| json | built-in | dumps/loads works |
| hashlib | built-in | sha256 works |

### Data Processing (All PASS)

| Package | Version | Test |
|---------|---------|------|
| numpy | 2.4.4 | array, random, linalg, sin all work |
| pyyaml | 6.0.3 | safe_load works |
| beautifulsoup4 | 4.14.3 | HTML parsing works |

### Database/ORM (All PASS)

| Package | Version | Test |
|---------|---------|------|
| sqlalchemy | 2.0.49 | create_engine, Session, declarative_base work |
| greenlet | 3.5.0 | greenlet switching works (sqlalchemy dependency) |

### Web/HTTP (All PASS)

| Package | Version | Test |
|---------|---------|------|
| requests | 2.34.0 | import works |
| urllib3 | 2.7.0 | import works |
| flask | 3.1.3 | Flask() app, app_context, url_for work |
| werkzeug | 3.1.8 | import works |

### Templates (All PASS)

| Package | Version | Test |
|---------|---------|------|
| jinja2 | 3.1.6 | Template.render works |
| markupsafe | 3.0.3 | escape works |

### CLI/Utilities (All PASS)

| Package | Version | Test |
|---------|---------|------|
| click | 8.3.3 | import works |
| six | 1.17.0 | import works |
| colorama | 0.4.6 | Fore.GREEN colored output works |
| tqdm | 4.67.3 | import works |

### Security (All PASS)

| Package | Version | Test |
|---------|---------|------|
| itsdangerous | 2.2.0 | URLSafeSerializer works |
| blinker | 1.9.0 | import works |
| bcrypt | 5.0.0 | hashpw, gensalt, checkpw work (compiled with CC/CXX env) |

### Build Tools (All PASS)

| Package | Version | Test |
|---------|---------|------|
| setuptools | 82.0.1 | import works |
| wheel | 0.47.0 | import works |
| cython | 3.2.4 | import works |
| packaging | 26.2 | import works |

### Misc (All PASS)

| Package | Version | Test |
|---------|---------|------|
| certifi | 2026.4.22 | import works |
| charset_normalizer | 3.4.7 | import works |
| idna | 3.14 | import works |
| pip | 24.3.1 | pip commands work |
| typing_extensions | 4.15.0 | import works |
| soupsieve | 2.8.3 | import works |

## Packages That Failed to Build (Solutions Found)

| Package | Error | Solution | Status |
|---------|-------|----------|--------|
| bcrypt | linker `cc` not found | Set `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++` before pip install | ✅ WORKS |
| greenlet | `c++` failed | Set `CC/CXX` environment variables, sign .so after build | ✅ WORKS |
| pillow | `cc` failed, missing jpeg headers | Compiled libjpeg-turbo 3.0.4 + libpng 1.6.48 from source | ✅ WORKS |
| lxml | libxml2/libxslt missing | Compiled libxml2 2.14.0 + libxslt 1.1.42 from source | ✅ WORKS |

## Packages That Still Fail (Requires System Libraries)

| Package | Error | Reason | Alternative |
|---------|-------|--------|-------------|
| curses | autoconf doesn't recognize 'ohos' | config.sub needs patching for HarmonyOS triplet | Skip curses-dependent apps |
| cryptography | Rust build | Need Rust toolchain + CC env | Set CC environment + Rust toolchain |

## Compiled Native Libraries

| Library | Version | Location | Used By |
|---------|---------|----------|---------|
| libjpeg-turbo | 3.0.4 | `~/.local/lib/libjpeg.a` | pillow |
| libpng | 1.6.48 | `~/.local/lib/libpng16.a` | pillow |
| libxml2 | 2.14.0 | `~/.local/lib/libxml2.so` | lxml |
| libxslt | 1.1.42 | `~/.local/lib/libxslt.so` | lxml |
| libexslt | 1.1.42 | `~/.local/lib/libexslt.so` | lxml |

## Package Compatibility Categories

| Category | Works | Example | Notes |
|----------|-------|---------|-------|
| Pure Python | 100% | requests, flask, jinja2 | pip install directly |
| NumPy-based | 100% | numpy, after signing | Need wheel rename + .so signing |
| Image processing | 100% | pillow | Compiled libjpeg/libpng from source |
| XML parsing | 100% | lxml | Compiled libxml2/libxslt from source |
| C/C++ extensions | Variable | bcrypt, greenlet | Set CC/CXX environment variables |
| Rust-based | Variable | bcrypt, cryptography | Need CC environment + Rust toolchain |

## Runtime Requirements for lxml

lxml requires `LD_LIBRARY_PATH` to find shared libraries:

```bash
export LD_LIBRARY_PATH=$HOME/.local/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/system/lib64
```

This can be added to `~/.zshenv` for persistence.

## Recommendations

1. **Pure Python packages**: Install directly with pip, 100% compatible
2. **numpy/scipy**: Use HarmonyOS wheel + sign extension modules
3. **C/C++ extension packages**: Set `CC=/data/service/hnp/bin/clang` and `CXX=/data/service/hnp/bin/clang++` environment variables before pip install
4. **Rust-based packages**: Set CC/CXX environment variables + ensure Rust toolchain is available
5. **Image processing (pillow)**: ✅ Now available - compiled libjpeg-turbo and libpng from source
6. **XML parsing (lxml)**: ✅ Now available - compiled libxml2, libxslt, and libexslt from source
7. **Terminal UI (curses)**: Not available - autoconf issues, skip curses-dependent applications

## Test Script

Location: `$HOME/Claude/test_pip_packages.py`

Run: `python3 test_pip_packages.py`