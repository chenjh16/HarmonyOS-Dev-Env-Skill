# HarmonyOS-Dev-Env-Skill Project - Development Guide

## Project Overview

This project is a skill pack for HarmonyOS PC development environment. It provides complete build and installation guides for various tools (Python, Rust, Go, PyTorch, llama.cpp, etc.).

**Target Platform**: HarmonyOS (HongMeng Kernel 1.12.0, aarch64)

## Project Structure

```
HarmonyOS-Dev-Env-Skill/
├── CLAUDE.md              # This file - Agent development guide (English)
├── CLAUDE.cn.md           # Agent development guide (Chinese)
├── README.md              # Project README (bilingual)
├── skill.json             # Skill definition with tool metadata
├── rules/                 # Rules for target system (install to ~/.claude/)
│   ├── CLAUDE.md          # HarmonyOS rules (English)
│   └── CLAUDE.cn.md       # HarmonyOS rules (Chinese)
├── docs/                  # Adaptation guides (bilingual *.md + *.cn.md)
│   ├── python-harmonyos.md
│   ├── python-harmonyos.cn.md
│   └── ...
├── tools/                 # Tool-specific build guides (bilingual)
│   ├── python/
│   │   ├── build.md
│   │   ├── build.cn.md
│   │   └── install.sh
│   └── ...
├── config/                # Configuration templates
│   ├── .zshenv
│   ├── .claude/
│   │   ├── ssh-fetch-polyfill.js
│   │   └── start-claude.sh
│   └── ...
└── scripts/               # Utility scripts
    └── sign-all.sh
```

## Documentation Naming Convention

All documentation files follow bilingual naming:
- `*.md` - English version
- `*.cn.md` - Chinese version

**Exceptions**: README.md contains both English and Chinese in one file.

## Agent Development Rules

### 1. Bilingual Documentation
- When creating new documentation, always create both `*.md` and `*.cn.md`
- Keep code blocks and commands unchanged in both versions
- Translate headings, explanations, and comments

### 2. skill.json Updates
- When adding new tools, update skill.json with:
  - Tool metadata (name, version, category)
  - Documentation paths (path and path_cn)
- When adding new docs, update documentation array

### 3. File Organization
- `docs/` - General adaptation guides (platform-wide issues)
- `tools/` - Tool-specific build guides
- `rules/` - Target system rules (to be installed on user's system)
- `config/` - Configuration templates and scripts

### 4. Content Guidelines
- Include complete build steps, not just summaries
- Document all HarmonyOS-specific adaptations
- Provide troubleshooting sections for known issues
- Cross-reference related documents

### 5. Git Commits
- Maintain bilingual commit messages when significant
- Update both language versions together
- Reference the Co-Authored-By line

## Key HarmonyOS Adaptations

When documenting tool adaptations, always cover:

1. **Code Signing**: All ELF binaries must be signed
2. **/tmp Read-only**: Use $HOME/Claude/tmpdir
3. **LD_LIBRARY_PATH**: /usr/lib must come first
4. **Linker Wrapper**: SDK's lld broken, use ld.bfd wrapper
5. **No gcc**: Only clang available
6. **SSH V8 Crash**: Use --jitless + node-fetch polyfill
7. **SSH `-e` Flag**: Dropbear must be started with `-e` flag to pass env vars (LD_LIBRARY_PATH, PATH) to child sessions
8. **make -j fails**: mkfifo returns "Operation not permitted" — use Ninja for parallel builds
9. **No CMAKE_TOOLCHAIN_FILE**: Do NOT use CMAKE_TOOLCHAIN_FILE with CMAKE_SYSTEM_NAME=Linux — it triggers cross-compilation mode causing try_run() failures; use lightweight toolchain file (only compilers + linker wrapper, no CMAKE_SYSTEM_NAME) or pass compiler flags directly
10. **OpenBLAS/LAPACK**: Compile OpenBLAS v0.3.28 with NOFORTRAN=1 (f2c LAPACK); modify Makefile.prebuild for -B wrapper + code signing; create .so from .a; set LAPACK_LIBRARIES and LAPACK_FOUND explicitly in CMake
11. **Sleef NATIVE_BUILD_DIR fix**: Modify sleef CMakeLists.txt add_host_executable to use NATIVE_BUILD_DIR when provided, even without CMAKE_CROSSCOMPILING — avoids circular signing dependency
12. **NumPy post-build fix**: If NumPy not found during CMake, recompile tensor_numpy.cpp with -DUSE_NUMPY and relink libtorch_python.so — no full rebuild needed
13. **CMake 4.1.2 ldd in PATH**: CMake 4.1.2 runs ldd after linking executables; copy ldd wrapper to ~/.local/bin/ldd
14. **PyTorch visibility hidden + supplement.so**: PyTorch compiles with `-fvisibility=hidden`, hiding `RefcountedMapAllocator::decref/incref` and `at::internal::invoke_parallel` from libtorch_cpu.so's dynamic symbol table. Create `libtorch_supplement.so` with stub implementations, add as NEEDED dependency via `patchelf --add-needed`
15. **NEEDED path prefix fix**: Ninja-built libraries use "lib/" prefix in NEEDED entries (e.g. `lib/libtorch_cpu.so`). Use `patchelf --replace-needed` to strip prefix and `--set-rpath` to set `$ORIGIN:$HOME/.local/lib`
16. **OpenSSH passwd_compat LD_PRELOAD**: sshd requires passwd_compat LD_PRELOAD because uid 20020106 is not in /etc/passwd (read-only). Child env must preserve LD_PRELOAD/LD_LIBRARY_PATH (patch session.c do_setup_env). sshd_config must use SetEnv PATH to put openssh-prefix/bin first (system /usr/bin/scp crashes).
17. **OpenSSH abstract socket**: ssh-agent bind() returns EPERM for filesystem Unix sockets; falls back to abstract namespace (sun_path[0]='\0'). SSH_AUTH_SOCK uses "abstract:" prefix.
18. **OpenSSH privsep non-fatal**: HarmonyOS doesn't permit chroot/setgroups/setegid/seteuid for user-space processes. Patch sshd-session.c to make chroot non-fatal (skip subsequent privdrop). uidswap.c: change setgroups/setegid/seteuid from fatal to debug.
19. **OpenSSH authorized_keys UID**: Files owned by uid 20001006 (file_manager), sshd runs as uid 20020106. Add uid 20001006 to platform_sys_dir_uid() (like root). safe_path() skips mode check (022 bitmask) for system-dir-owned files. StrictModes=yes works.

## Related Documentation

- Target system rules: `rules/CLAUDE.md`
- Code signing guide: `docs/code-signing.md`
- LD_LIBRARY_PATH: `docs/ld-library-path.md`
- OpenSSH adaptation: `docs/openssh-harmonyos.md`