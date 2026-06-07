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

## Dependency Conflict

| Package | Error | Reason | Workaround |
|---------|-------|--------|------------|
| pynacl | libsodium C extension + cffi version conflict | pip build isolation triggers cffi version mismatch: our cffi 2.0.0 vs HNP system cffi 1.17.1. `--no-build-isolation` also fails because subprocess loads `/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/_cffi_backend.cpython-312.so` (1.17.1). Would need manual libsodium compilation + cffi pin. | Consider alternatives (cryptography works) |

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