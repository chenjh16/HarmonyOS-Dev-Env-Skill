# HarmonyOS-Dev-Env-Skill Project - Development Guide

## Project Overview

This project is a skill pack for HarmonyOS PC development environment. It provides complete build and installation guides for various tools (Python, Rust, Go, PyTorch, llama.cpp, etc.).

**Target Platform**: HarmonyOS (HongMeng Kernel 1.12.0, aarch64)

## Project Structure

The skill content lives in a self-contained `harmonyos-dev-env/` subdirectory that is copied wholesale to `~/.claude/skills/` during installation:

```
HarmonyOS-Dev-Env-Skill/
├── harmonyos-dev-env/        ← THE SKILL (cp -r this to ~/.claude/skills/)
│   ├── SKILL.md              ← Skill definition (YAML frontmatter + bilingual rules)
│   ├── scripts/
│   │   ├── env-setup.sh      ← One-time env setup (tmpdir + linker wrapper + zshenv)
│   │   ├── sign-all.sh       ← Batch ELF signing
│   │   ├── verify-env.sh     ← Environment verification
│   │   ├── ssh-fetch-polyfill.js
│   │   └── start-claude.sh
│   ├── docs/                 ← 19 bilingual adaptation guides (*.md + *.cn.md)
│   ├── tools/                ← 11 tool build guides + install scripts
│   └── assets/               ← Installation assets (not skill knowledge per se)
│       ├── zshenv            ← Shell env template
│       └── rules/
│           ├── CLAUDE.md     ← Global platform rules (English)
│           └── CLAUDE.cn.md  ← Global platform rules (Chinese)
├── CLAUDE.md                 ← This file - project dev guide (English)
├── CLAUDE.cn.md              ← Project dev guide (Chinese)
├── README.md                 ← Project README (bilingual)
├── skill.json                ← Metadata
├── scripts/
│   └── install-skill.sh      ← Simplified: just cp -r harmonyos-dev-env/
└── .gitignore
```

**Key principle**: `harmonyos-dev-env/` must be fully self-contained. Shell scripts use `SCRIPT_DIR` pattern to find sibling files. SKILL.md references docs with relative paths. All user-variable paths use `$HOME` (never `/storage/Users/currentUser`). `assets/` contains non-skill-knowledge files (shell config, global rules) needed by env-setup.sh.

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

### 3. Path Portability
- **Never use `/storage/Users/currentUser`** — always use `$HOME`
- In JavaScript: use `process.env.HOME`
- In C code: use `getenv("HOME")`
- System paths like `/data/service/hnp/bin/*`, `/system/lib64`, `/usr/lib` are fine (platform-fixed)
- Shell scripts must use `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` for sibling references

### 4. File Organization
- `harmonyos-dev-env/docs/` - General adaptation guides (platform-wide issues)
- `harmonyos-dev-env/tools/` - Tool-specific build guides
- `harmonyos-dev-env/assets/` - Installation assets (zshenv, rules — not skill knowledge)
- `harmonyos-dev-env/scripts/` - Utility scripts (sign-all, verify-env, env-setup)

### 5. Content Guidelines
- Include complete build steps, not just summaries
- Document all HarmonyOS-specific adaptations
- Provide troubleshooting sections for known issues
- Cross-reference related documents

### 6. Git Commits
- Maintain bilingual commit messages when significant
- Update both language versions together
- Reference the Co-Authored-By line

## Key HarmonyOS Adaptations

When documenting tool adaptations, always cover:

1. **Code Signing**: All ELF binaries must be signed
2. **PyTorch Version Note**: Labeled as v2.5.1 (git tag), internal version string is 2.5.0a0+gita8d6fb (pre-release marker) — same code
3. **/tmp Read-only**: Use $HOME/Claude/tmpdir
4. **LD_LIBRARY_PATH**: /usr/lib must come first
5. **Linker Wrapper**: SDK's lld broken, use ld.bfd wrapper
6. **No gcc**: Only clang available
7. **SSH V8 Crash**: Use --jitless + node-fetch polyfill
8. **SSH `-e` Flag**: Dropbear must be started with `-e` flag to pass env vars (LD_LIBRARY_PATH, PATH) to child sessions
9. **make -j fails**: mkfifo returns "Operation not permitted" — use Ninja for parallel builds
10. **No CMAKE_TOOLCHAIN_FILE**: Do NOT use CMAKE_TOOLCHAIN_FILE with CMAKE_SYSTEM_NAME=Linux — it triggers cross-compilation mode causing try_run() failures; use lightweight toolchain file (only compilers + linker wrapper, no CMAKE_SYSTEM_NAME) or pass compiler flags directly
11. **OpenBLAS/LAPACK**: Compile OpenBLAS v0.3.28 with NOFORTRAN=1 (f2c LAPACK); modify Makefile.prebuild for -B wrapper + code signing; create .so from .a; set LAPACK_LIBRARIES and LAPACK_FOUND explicitly in CMake
12. **Sleef NATIVE_BUILD_DIR fix**: Modify sleef CMakeLists.txt add_host_executable to use NATIVE_BUILD_DIR when provided, even without CMAKE_CROSSCOMPILING — avoids circular signing dependency
13. **NumPy post-build fix**: If NumPy not found during CMake, recompile tensor_numpy.cpp with -DUSE_NUMPY and relink libtorch_python.so — no full rebuild needed
14. **CMake 4.1.2 ldd in PATH**: CMake 4.1.2 runs ldd after linking executables; copy ldd wrapper to ~/.local/bin/ldd
15. **PyTorch visibility hidden + supplement.so**: PyTorch compiles with `-fvisibility=hidden`, hiding `RefcountedMapAllocator::decref/incref` and `at::internal::invoke_parallel` from libtorch_cpu.so's dynamic symbol table. Create `libtorch_supplement.so` with stub implementations, add as NEEDED dependency via `patchelf --add-needed`
16. **NEEDED path prefix fix**: Ninja-built libraries use "lib/" prefix in NEEDED entries (e.g. `lib/libtorch_cpu.so`). Use `patchelf --replace-needed` to strip prefix and `--set-rpath` to set `$ORIGIN:$HOME/.local/lib`
17. **OpenSSH passwd_compat LD_PRELOAD**: sshd requires passwd_compat LD_PRELOAD because uid 20020106 is not in /etc/passwd (read-only). Child env must preserve LD_PRELOAD/LD_LIBRARY_PATH (patch session.c do_setup_env). sshd_config must use SetEnv PATH to put openssh-prefix/bin first (system /usr/bin/scp crashes).
18. **OpenSSH abstract socket**: ssh-agent bind() returns EPERM for filesystem Unix sockets; falls back to abstract namespace (sun_path[0]='\0'). SSH_AUTH_SOCK uses "abstract:" prefix.
19. **OpenSSH privsep non-fatal**: HarmonyOS doesn't permit chroot/setgroups/setegid/seteuid for user-space processes. Patch sshd-session.c to make chroot non-fatal (skip subsequent privdrop). uidswap.c: change setgroups/setegid/seteuid from fatal to debug.
20. **OpenSSH authorized_keys UID**: Files owned by uid 20001006 (file_manager), sshd runs as uid 20020106. Add uid 20001006 to platform_sys_dir_uid() (like root). safe_path() skips mode check (022 bitmask) for system-dir-owned files. StrictModes=yes works.

## Related Documentation

- Skill definition: `harmonyos-dev-env/SKILL.md`
- One-time setup: `harmonyos-dev-env/scripts/env-setup.sh`
- Global rules template: `harmonyos-dev-env/assets/rules/CLAUDE.md`
- Shell env template: `harmonyos-dev-env/assets/zshenv`
- Code signing guide: `harmonyos-dev-env/docs/code-signing.md`
- LD_LIBRARY_PATH: `harmonyos-dev-env/docs/ld-library-path.md`
- OpenSSH adaptation: `harmonyos-dev-env/docs/openssh-harmonyos.md`