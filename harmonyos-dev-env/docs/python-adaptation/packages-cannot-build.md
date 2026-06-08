# Packages That Cannot Build on HarmonyOS

> **169 Python packages working**, 9 cannot build (see below for details).

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
| pyarrow | Apache Arrow C++ build | pyarrow requires building Apache Arrow C++ library (huge codebase, complex CMake). Build takes 30+ minutes and has many platform-specific issues. | Consider alternative (pandas CSV/Parquet via fastparquet; orjson for JSON) |
| scikit-learn | needs scipy + Cython | scikit-learn depends on scipy (blocked by Fortran). Even without scipy, Cython extensions have complex build requirements. | Consider alternative (manual implementation of specific algorithms; optuna for optimization) |
| xgboost | CMake + git submodules + OpenMP | xgboost requires CMake build with recursive git submodules (dmlc-core, rabit) which can't be fetched on HarmonyOS. Also needs OpenMP support. | Consider alternative (optuna for optimization; manual gradient boosting) |
| lightgbm | CMake build succeeds but import fails (needs scipy) | lightgbm builds successfully with CC/CXX + --no-build-isolation, but import fails because lightgbm.basic imports scipy.sparse at module level. Since scipy can't be built, lightgbm is unusable. | Consider alternative (optuna for optimization; numpy vectorized operations) |

## Dependency Conflict

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| pynacl | libsodium autotools configure fails on HarmonyOS | libsodium's bundled configure script fails because: (1) /tmp is read-only (can't create temp files for sanity checks), (2) compiled test executables need code signing before execution. Meson auto-sign wrapper doesn't help because libsodium uses autotools, not meson. Would need manual libsodium compilation bypassing configure. | Consider alternatives (cryptography works — provides NaCl: Ed25519, X25519, ChaCha20Poly1305) |

## Cascading Failures

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| paramiko | depends on pynacl | pynacl cannot build due to libsodium configure failure. paramiko itself is pure Python but cannot function without nacl.signing. | None without pynacl; use cryptography's NaCl primitives where possible |

## Previously Blocked — Now Working

These packages were previously in the "cannot build" list but have been successfully adapted:

| Package | Version | Adaptation Method | E2E Tests |
|---------|---------|-------------------|-----------|
| soundfile | 0.14.0 | Compiled libsndfile 1.2.2 from source (cmake+ninja), patched soundfile.py for HarmonyOS platform detection + musl find_library fallback | 3/3 |
| h5py | 3.16.0 | Compiled HDF5 1.14.6 from source (cmake+ninja, no zlib/szip), built h5py with --no-build-isolation, signed .so, fixed NEEDED path prefix (bin/→), set RPATH | 3/3 |
| psycopg2 | 2.9.12 | Compiled libpq from PostgreSQL 17.5 (meson+ninja), created pg_config wrapper, built psycopg2 with --no-build-isolation, signed .so | 3/3 |
| numexpr | 2.14.1 | Already installed and working (C extension, signed .so, suffix renamed) | 3/3 |
| numcodecs | 0.16.5 | Built with --no-build-isolation (Cython extensions), signed .so, suffix renamed, set RPATH | 3/3 |
| numcodecs enables zarr | zarr | numcodecs working → zarr's compression codecs now functional | see zarr e2e |

## Analysis

### libsodium configure Failure (pynacl)

libsodium's autotools configure script fails on HarmonyOS because:
1. `/tmp` is read-only — configure uses `mktemp` to create temporary files for sanity checks
2. Compiled test executables need code signing before execution on HarmonyOS
3. The meson auto-sign clang wrapper only works for meson-based projects; libsodium uses autotools

**Potential fix** (not yet attempted): Create a minimal config.h manually, compile all libsodium .c files directly into .so using clang, bypassing configure entirely.

### scipy Dependency Cascade

Several packages depend on scipy at import time (not just for optional features):
- **lightgbm**: `import scipy.sparse` at module level → import fails
- **scikit-learn**: scipy is a hard dependency
- This creates a "dependency cascade" where building the C library doesn't help because scipy is needed at import time

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