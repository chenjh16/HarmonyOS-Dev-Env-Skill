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

## Related Documentation

- Target system rules: `rules/CLAUDE.md`
- Code signing guide: `docs/code-signing.md`
- LD_LIBRARY_PATH: `docs/ld-library-path.md`