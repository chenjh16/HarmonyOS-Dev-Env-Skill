# Python Package Adaptation Guide for HarmonyOS

> **Progressive disclosure**: This index provides high-level summaries with links to detailed fragments. Start here, then drill down into specific topics as needed.

## Package Compatibility Overview

**164/164 Python packages working**, 14 cannot build (see [packages-cannot-build.md](packages-cannot-build.md) for details).

| Category | Pass Rate | Typical Packages | Adaptation Method |
|----------|-----------|------------------|-------------------|
| Pure Python | 100% | requests, flask, jinja2, httpx, pytest, structlog | pip install directly |
| C/C++ extensions | 100% | bcrypt, greenlet, hiredis, lz4, zstd, xxhash | CC/CXX + sign .so + suffix rename |
| C++ extensions (libc++_shared.so) | 100% | python-rapidjson, ujson, cytoolz, contourpy, kiwisolver, matplotlib | CC/CXX + sign + patchelf --add-needed libc++_shared.so + suffix rename |
| Mixed (C lib + Python binding) | 100% | pillow (libjpeg), lxml (libxml2) | Compile C deps first → pip install → sign .so |
| Rust/PyO3 (maturin) | 100% | cryptography, pydantic-core, rpds-py, tiktoken, orjson, tokenizers, safetensors | maturin build + sign + rename suffix |
| Meson-based | 100% | pandas, matplotlib | Auto-sign clang wrapper + mesonpy API |
| Platform detection patches | 100% | psutil | Patch _common.py + net.c |
| ML/NLP | 100% | tokenizers, safetensors, transformers | Rust build + pure Python patches |
| Fortran-dependent | 0% | scipy | No Fortran compiler on HarmonyOS |
| libuv-dependent | 0% | uvloop | libuv autoconf can't configure on HarmonyOS |

See [packages-overview.md](packages-overview.md) for full per-category breakdown and [packages-detailed.md](packages-detailed.md) for per-package test results.

## Adaptation Methodology

All extension package adaptations follow a 5-phase decision tree:

1. **Determine package type** — pure Python vs C/C++ vs Rust vs Meson
2. **Prepare build environment** — CC/CXX, TMPDIR, linker wrapper, RUSTFLAGS
3. **Compile & install** — pip vs wheel rename vs maturin vs mesonpy
4. **Sign & patchelf** — code signing + NEEDED fix + RPATH + libc++_shared.so + supplement.so
5. **Verify & run** — import test + LD_LIBRARY_PATH + error diagnosis

See [extension-guide.md](extension-guide.md) for the complete step-by-step methodology.

## Special Adaptation Techniques

These techniques apply to specific categories of packages:

| Technique | Applies To | Fragment |
|-----------|-----------|----------|
| C++ patchelf-sign workflow | All C++ extensions | [extension-guide.md](extension-guide.md) Step 4.5 |
| rustc auto-sign wrapper | orjson, tokenizers, safetensors, any Rust/PyO3 with build scripts | [rustc-wrapper.md](rustc-wrapper.md) |
| Meson auto-sign clang wrapper | pandas, matplotlib | [meson-wrapper.md](meson-wrapper.md) |
| asyncio.current_task segfault fix | structlog, any logging+asyncio package | [extension-guide.md](extension-guide.md) Step 4.7 |
| maturin direct build (not pip) | All Rust/PyO3 packages on HarmonyOS | [extension-guide.md](extension-guide.md) Phase 3 Strategy D |
| fancy-regex feature | tokenizers (replacing onig) | [packages-detailed.md](packages-detailed.md) tokenizers entry |
| transformers version + FP8 patches | transformers 5.10.2 | [packages-detailed.md](packages-detailed.md) transformers entry |
| psutil platform detection | psutil | [extension-guide.md](extension-guide.md) psutil example |
| cffi LDFLAGS rebuild | cffi 2.0.0 | [extension-guide.md](extension-guide.md) Step 4.6 |

## Cannot Build Packages

| Package | Reason | Workaround |
|---------|--------|------------|
| scipy | Needs gfortran (Fortran compiler) | None — hardware limitation |
| uvloop | libuv autoconf can't configure | None — platform limitation |
| polars | cargo metadata too complex | Consider alternative (pandas works) |
| pynacl | cffi version conflict | Consider alternatives (cryptography works) |

See [packages-cannot-build.md](packages-cannot-build.md) for detailed error analysis.

## Compiled Native Libraries

| Library | Version | Used By |
|---------|---------|---------|
| libjpeg-turbo | 3.0.4 | pillow |
| libpng | 1.6.48 | pillow |
| libxml2 | 2.14.0 | lxml |
| libxslt | 1.1.42 | lxml |
| libffi | 8 | cffi/cryptography |
| libopenblas | 0.3.28 | PyTorch/numpy |

See [packages-overview.md](packages-overview.md) Compiled Native Libraries section.

## Quick Reference

```bash
# Environment setup (required for ALL extension builds)
export CC=/data/service/hnp/bin/clang
export CXX=/data/service/hnp/bin/clang++
export TMPDIR=$HOME/Claude/tmpdir
export LDFLAGS="-B$HOME/Claude/lib/linker_wrapper"

# Batch sign all .so in a package
find ~/.local/lib/python3.12/site-packages/<pkg> -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "$f.tmp"
    mv "$f.tmp" "$f"
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +

# Rename .so suffix
cd ~/.local/lib/python3.12/site-packages/<pkg>
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done
```