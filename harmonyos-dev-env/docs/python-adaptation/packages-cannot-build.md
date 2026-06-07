# Packages That Cannot Build on HarmonyOS

## Permanently Blocked (Hardware/Platform Limitation)

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| scipy | needs gfortran (Fortran compiler) | HarmonyOS has no Fortran compiler (gfortran). scipy's C/Fortran extension modules cannot be compiled without it. | None — hardware limitation |
| uvloop | libuv vendor can't configure on HarmonyOS | libuv's autoconf can't guess the HarmonyOS platform; musl libc lacks cpu_set_t, CPU_SETSIZE, and mmsghdr. Requires significant libuv source patching. | None — platform limitation |

## Build Complexity Issues

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| polars | cargo metadata failed | Polars is a complex Rust/PyO3 package; cargo metadata fails during pip build. Requires downloading source and building manually. | Consider alternative (pandas works) |
| grpcio | C/C++ build too complex | grpcio requires building gRPC Core (C++) from source with complex CMake/Bazel setup. Multiple dependencies (protobuf, c-ares, abseil) create cascading build issues. | Consider alternative (pure Python grpcio-io; or use protobuf directly for message serialization) |
| h5py | HDF5 C library + Cython | h5py depends on libhdf5 (C) which requires complex CMake build. Cython extension module also needs CC/CXX configuration. | Consider alternative (imageio for simpler file I/O; zarr partial for array storage) |
| pyarrow | Apache Arrow C++ build | pyarrow requires building Apache Arrow C++ library (huge codebase, complex CMake). Build takes 30+ minutes and has many platform-specific issues. | Consider alternative (pandas CSV/Parquet via fastparquet; orjson for JSON) |
| scikit-learn | needs scipy + Cython | scikit-learn depends on scipy (blocked by Fortran). Even without scipy, Cython extensions have complex build requirements. | Consider alternative (manual implementation of specific algorithms; optuna for optimization) |
| xgboost | CMake + OpenMP | xgboost requires CMake build with OpenMP support. HarmonyOS musl libc lacks full OpenMP implementation. | Consider alternative (optuna for optimization; manual gradient boosting) |
| lightgbm | CMake + OpenMP | lightgbm requires OpenMP for parallel training. musl libc lacks libomp/libgomp. | Consider alternative (optuna for optimization) |
| numcodecs | needs Cython + numpy | numcodecs has Cython extensions requiring specific numpy version alignment. Build configuration issues on HarmonyOS. | Consider alternative (lz4/zstd for compression; imageio for array I/O) |
| numexpr | needs numpy + C extensions | numexpr's C extension has VFP (Virtual Function Pointer) tables requiring specific numpy ABI compatibility. Build fails on HarmonyOS. | Consider alternative (numpy vectorized operations; pandas query engine) |
| psycopg2 | libpq C extension | psycopg2 requires building libpq (PostgreSQL client library) from source. Complex build with many PostgreSQL dependencies. | Consider alternative (asyncpg works — 3/3 e2e; psycopg pure Python partial) |
| soundfile | libsndfile C extension | soundfile requires libsndfile (C library) which is not available on HarmonyOS. Needs manual compilation of libsndfile. | Consider alternative (pydub for audio processing; scipy.io.wavfile blocked by scipy) |
| zarr | partial (numcodecs dependency) | zarr itself is pure Python, but depends on numcodecs for compression codecs. Without numcodecs, zarr works but loses compression capabilities. | Consider alternative (imageio for array I/O; zarr works partially without numcodecs compression) |

## Dependency Conflict

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| pynacl | libsodium C extension + cffi version conflict | pip build isolation triggers cffi version mismatch: our cffi 2.0.0 vs HNP system cffi 1.17.1. `--no-build-isolation` also fails because subprocess loads `/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/_cffi_backend.cpython-312.so` (1.17.1). Would need manual libsodium compilation + cffi pin. | Consider alternatives (cryptography works) |
| psycopg (partial) | missing uuid_utils dependency | psycopg 3.x requires uuid_utils (Rust/PyO3 extension) which fails to build. psycopg's pure Python mode works for basic PostgreSQL connection (2/3 e2e), but full async support needs uuid_utils. | Consider alternative (asyncpg works — 3/3 e2e; psycopg pure Python for basic connections) |

## Cascading Failures

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| paramiko | depends on pynacl | pynacl cannot build due to cffi version conflict. paramiko itself is pure Python but cannot function without nacl.signing. | None without pynacl |

## Analysis

### cffi Version Conflict (pynacl)

This is the most nuanced failure. The root cause:

1. Our Python has cffi 2.0.0 with `_cffi_backend.cpython-312-aarch64-linux-gnu.so` (2.0.0)
2. HNP system Python at `/data/service/hnp/python.org/python_3.12/bin/python3.12` has cffi 1.17.1 with `_cffi_backend.cpython-312.so` (1.17.1)
3. pip build isolation uses the HNP system Python, which loads its own cffi backend
4. `--no-build-isolation` also fails because subprocess invocations still load the HNP cffi backend

**Potential fix** (not yet attempted): Compile libsodium from source, then manually create pynacl's C extension using our cffi 2.0.0, bypassing pip entirely.

### libuv Platform Detection (uvloop)

libuv's configure script can't detect HarmonyOS:
- `musl libc` lacks `cpu_set_t`, `CPU_SETSIZE`, and `mmsghdr` structures
- The autoconf `guess_platform` logic doesn't have a HarmonyOS case
- Requires upstream-level source patching to libuv

### Fortran Dependency (scipy)

scipy requires a Fortran compiler for its core linear algebra modules. HarmonyOS has no `gfortran` and no reasonable path to obtain one:
- Cross-compiling gfortran from source requires a bootstrapping GCC, which itself needs gcc
- The HarmonyOS SDK only provides clang (C/C++/ObjC)
- This is a fundamental hardware/platform limitation