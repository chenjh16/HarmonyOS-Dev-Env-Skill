# starship HarmonyOS Adaptation Notes

> **中文版本见 build.cn.md**

## Basic Info

- **Project**: starship — cross-shell modern command-line prompt
- **Version**: v1.25.1
- **Source**: `https://github.com/starship-community/starship` (cloned via gh-proxy.com)
- **Build directory**: `/storage/Users/currentUser/Claude/starship-build/starship/`
- **Binary path**: `/storage/Users/currentUser/Claude/starship-build/starship/target/release/starship`
- **Config path**: `/data/storage/el2/base/haps/entry/files/starship/starship.toml`
- **Build time**: ~6 minutes (release profile)

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

**Problem**: HarmonyOS uses musl libc, which does not support the `strerror_r` function (only `strerror`).
However, the errno crate calls `strerror_r` under the `target_os = "linux"` condition (ohos inherits this identifier),
resulting in a link-time error: `undefined symbol: __xpg_strerror_r`.

**Patch**: Modify the errno crate's unix.rs in the cargo registry, replacing `strerror_r` with `strerror`.

Three versions of the errno crate are affected:
- `errno-0.2.8/src/unix.rs`
- `errno-0.3.10/src/unix.rs`
- `errno-0.3.14/src/unix.rs`

Key modifications:
1. `with_description()` function: replace `strerror_r` buffer-write pattern with `CStr::from_ptr(strerror(err.0))`
2. `STRERROR_NAME` constant: `"strerror_r"` -> `"strerror"`
3. extern block: replace `strerror_r` extern declaration with `fn strerror(errnum: c_int) -> *mut c_char`
4. import: remove `strerror_r`/`size_t`, add `c_char`

**Note**: After patching the cargo registry cache, you must manually remove errno-related .rlib/.rmeta files in target/deps,
otherwise cargo will not recompile the cached crate.

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

### 5. PATH and Environment Variable Configuration

Add to `.zshenv`:
```bash
export STARSHIP_HOME="$HOME/Claude/starship-build/starship/target/release"
export PATH="$STARSHIP_HOME:$PATH"
export STARSHIP_CONFIG="/data/storage/el2/base/haps/entry/files/starship/starship.toml"
```

### 6. zsh Prompt Configuration

In `.zshrc`, replace the original `PROMPT='%m:%~%# '` with:
```bash
eval "$(starship init zsh)"
```

### 7. starship Configuration File

`/data/storage/el2/base/haps/entry/files/starship/starship.toml`:
- `command_timeout = 5000` (git commands may be slower on HarmonyOS)
- Streamlined format: directory + git_branch + git_status + git_state + rust + cmd_duration + character
- Disable right_format (simplify terminal display)

## End-to-End Test Results

| Test Item | Result |
|-----------|--------|
| `starship --version` | starship 1.25.1 |
| `starship --help` | Full help output |
| `starship init zsh` | Outputs zsh initialization script |
| `starship prompt` | Outputs colored prompt (directory + git + rust + character) |
| `starship module directory` | Directory module |
| `starship module git_branch` | Git branch module |
| `starship preset` | Preset configuration available |
| `starship timings` | Module timing feature |

## Problems Encountered and Solutions

| Problem | Cause | Solution |
|---------|-------|----------|
| `undefined symbol: __xpg_strerror_r` | musl libc does not provide strerror_r; ohos inherits linux target_os causing errno crate to use strerror_r | Patch errno crate source code, use strerror instead |
| cargo does not recompile patched crate | target/deps caches old .rlib | Manually rm errno-related .rlib/.rmeta files |
| `permission denied` running binary | File permissions lost after signing | `chmod +x` to restore execution permissions |
| git command timeout warning | git commands may be slower on HarmonyOS | Configure `command_timeout = 5000` |

## Integration with zsh

starship integrates into zsh via `eval "$(starship init zsh)"`, which defines:
- `starship_prompt_func` — the function that renders the prompt
- `precmd` / `preexec` — command timing hooks
- `STARSHIP_START_TIME` — command execution start time tracking

Works normally under HarmonyOS stripped zsh (no compinit), does not require completion system support.