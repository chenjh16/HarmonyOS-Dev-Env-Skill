# starship HarmonyOS Adaptation Record

## Basic Information

- **Project**: starship — Cross-shell modern command prompt
- **Version**: v1.25.1
- **Source**: `https://github.com/starship-community/starship` (via gh-proxy.com clone)
- **Build directory**: `/storage/Users/currentUser/Claude/starship-build/starship/`
- **Binary path**: `/storage/Users/currentUser/Claude/starship-build/starship/target/release/starship`
- **Config path**: `/data/storage/el2/base/haps/entry/files/starship/starship.toml`
- **Compile time**: ~6 minutes (release profile)

## Build Process

### 1. Clone Source

```bash
git clone https://gh-proxy.com/https://github.com/starship-community/starship.git starship-build/starship
```

### 2. Cargo Configuration

`.cargo/config.toml`:
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

### 3. errno Crate Patching (Critical!)

**Problem**: HarmonyOS uses musl libc, doesn't support `strerror_r` function (only `strerror`).
But errno crate calls `strerror_r` under `target_os = "linux"` (ohos inherits this identifier),
linking errors `undefined symbol: __xpg_strerror_r`.

**Patch**: Modify errno crate unix.rs in cargo registry, replace `strerror_r` with `strerror`.

Three errno crate versions affected:
- `errno-0.2.8/src/unix.rs`
- `errno-0.3.10/src/unix.rs`
- `errno-0.3.14/src/unix.rs`

Modification points:
1. `with_description()` function: Use `CStr::from_ptr(strerror(err.0))` instead of `strerror_r` buffer write mode
2. `STRERROR_NAME` constant: `"strerror_r"` → `"strerror"`
3. extern block: Replace `strerror_r` extern declaration with `fn strerror(errnum: c_int) -> *mut c_char`
4. import: Remove `strerror_r`/`size_t`, add `c_char`

**Note**: After patching cargo registry cache, must manually delete errno related .rlib/.rmeta in target/deps,
otherwise cargo won't recompile cached crate.

```bash
rm -f target/release/deps/*errno*
rm -f target/release/deps/*starship*
cargo build --release
```

### 4. Code Signing

```bash
binary-sign-tool sign -selfSign 1 \
  -inFile target/release/starship \
  -outFile target/release/starship-signed
mv target/release/starship-signed target/release/starship
chmod +x target/release/starship
```

### 5. PATH and Environment Configuration

Add to `.zshenv`:
```bash
export STARSHIP_HOME="$HOME/Claude/starship-build/starship/target/release"
export PATH="$STARSHIP_HOME:$PATH"
export STARSHIP_CONFIG="/data/storage/el2/base/haps/entry/files/starship/starship.toml"
```

### 6. zsh Prompt Configuration

In `.zshrc` replace original `PROMPT='%m:%~%# '` with:
```bash
eval "$(starship init zsh)"
```

### 7. starship Configuration File

`/data/storage/el2/base/haps/entry/files/starship/starship.toml`:
- `command_timeout = 5000` (git commands may be slow on HarmonyOS)
- Simplified format: directory + git_branch + git_status + git_state + rust + cmd_duration + character
- Disable right_format (simplify terminal display)

## End-to-End Test Results

| Test | Result |
|------|--------|
| `starship --version` | ✅ starship 1.25.1 |
| `starship --help` | ✅ Complete help output |
| `starship init zsh` | ✅ Outputs zsh init script |
| `starship prompt` | ✅ Color prompt (directory + git + rust + character) |
| `starship module directory` | ✅ Directory module |
| `starship module git_branch` | ✅ Git branch module |
| `starship preset` | ✅ Preset configs available |
| `starship timings` | ✅ Module timing function |

## Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| `undefined symbol: __xpg_strerror_r` | musl libc doesn't have strerror_r, ohos inherits linux target_os causing errno crate to use strerror_r | Patch errno crate source, use strerror instead |
| cargo won't recompile patched crate | target/deps cached old .rlib | Manually rm errno related .rlib/.rmeta files |
| `permission denied` running binary | Signature lost file permissions | `chmod +x` restore execute permission |
| git command timeout warning | git commands may be slow on HarmonyOS | Configure `command_timeout = 5000` |

## Integration with zsh

starship integrates via `eval "$(starship init zsh)"`, which defines:
- `starship_prompt_func` — Prompt drawing function
- `precmd` / `preexec` — Command timing hooks
- `STARSHIP_START_TIME` — Command execution start time tracking

Works normally with HarmonyOS stripped zsh (no compinit), doesn't need completion system support.