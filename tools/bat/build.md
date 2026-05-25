# bat (Rust) HarmonyOS (aarch64) Build and End-to-End Testing

> **中文版本见 build.cn.md**

## 1. Project Info

- **Version**: bat v0.26.1
- **Language**: Rust (edition 2021, rust-version 1.88)
- **Purpose**: `cat(1) clone with wings` — supports syntax highlighting, Git integration, non-printable character display, etc.
- **Source**: https://github.com/sharkdp/bat

---

## 2. Clone

Direct GitHub connection does not work (port 443 connection timeout), use proxy:

```bash
git clone --depth 1 https://gh-proxy.com/https://github.com/sharkdp/bat.git
```

All 1000 files checked out successfully, no filename compatibility issues.

---

## 3. Cargo Configuration

Some of bat's dependencies (such as libgit2) require a C compiler. The system has no `cc` command, so clang must be configured:

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

Same configuration pattern as eza — the `CC` variable in `[env]` must be set.

---

## 4. Build

```bash
source ~/.zshenv
export CC=/data/service/hnp/bin/clang

# Release build
cargo build --release
# Success, 7m 03s, output 5.6MB
```

bat's `rust-toolchain.toml` specifies `channel = "1.88"`; our rustc 1.95 is higher than this requirement, and without rustup, cargo simply ignores the channel specification.

**Note**: The first `cargo build` will download many dependencies (including syntect syntax highlighting engine, libgit2, etc.), which takes a long time. Dependency download requires the `SSL_CERT_FILE` environment variable to be set (see Rust adaptation notes).

---

## 5. Code Signing

```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/bat -outFile target/release/bat-signed -signAlg SHA256withECDSA
mv target/release/bat-signed target/release/bat
chmod +x target/release/bat
```

---

## 6. End-to-End Test Results

All core functionality tests passed (using release version v0.26.1):

| # | Feature | Command | Result |
|---|---------|---------|--------|
| 1 | Version | `bat --version` | bat 0.26.1 |
| 2 | Basic display | `bat <file>` | Normal, with line numbers and decorations |
| 3 | Plain text mode | `bat -p <file>` | No-decoration output works |
| 4 | Line numbers | `bat -n <file>` | Line numbers display correctly |
| 5 | Line range | `bat -r 1:10` | Range selection works |
| 6 | Syntax highlighting | `bat -l sh/c/rust` | Multi-language highlighting works |
| 7 | Non-printable chars | `bat -A` | Null/control character display works |
| 8 | Tab conversion | `bat --tabs=4` | Tab-to-space conversion works |
| 9 | Wrap | `bat --wrap=auto` | Auto line wrapping works |
| 10 | Style control | `bat --style=header/grid` | Style combination works |
| 11 | Pager control | `bat --pager=never` | Disable pager works |
| 12 | Multiple files | `bat file1 file2` | Multi-file display works |
| 13 | Line highlight | `bat -H 3:7` | Highlight specified lines works |
| 14 | Theme list | `bat --list-themes` | 20+ built-in themes |
| 15 | Language list | `bat --list-languages` | Extensive language support |
| 16 | Binary detection | `bat <.so file>` | Auto-detect binary files |
| 17 | UTF-8 | `echo "你好" | bat` | Chinese and emoji display correctly |
| 18 | Config directory | `bat --config-file` | Displayed correctly |
| 19 | Cache directory | `bat --cache-dir` | Displayed correctly |
| 20 | Diff mode | `bat -d file1 file2` | Diff comparison works |

**HarmonyOS-specific verification**:
- UTF-8 Chinese and emoji display correctly
- ELF binary file auto-detection and warning
- Config/cache directory points to `/data/storage/el2/base/haps/entry/files/bat/`
- Syntax highlighting correctly auto-detects `.zshenv` as shell script

---

## 7. Known Issues

### 7.1 Direct GitHub Connection Does Not Work

`github.com:443` connection timeout, need to use `gh-proxy.com` proxy for cloning. This is a HarmonyOS network environment limitation, not a bat project issue.

### 7.2 Dependency Download Takes Time

bat has a deep dependency chain (including syntect -> onig -> libgit2 -> libopenssl, etc.), and the first build downloading dependencies takes about 7 minutes. `SSL_CERT_FILE` must be set to access crates.io.

---

## Summary: Key Checklist for Building bat on HarmonyOS

1. **Clone**: Use `gh-proxy.com` proxy, no filename compatibility issues
2. **Cargo config**: `.cargo/config.toml` set linker + CC + TMPDIR
3. **SSL certificate**: `SSL_CERT_FILE=~/.rust/cacert.pem` (required for cargo dependency download)
4. **Build**: `cargo build --release`, output 5.6MB
5. **Signing**: Build output must be signed with `binary-sign-tool -selfSign 1`
6. **PATH**: Already added to `$HOME/.zshenv`, `bat` command available directly
7. **Functionality**: 20+ core features all working, including syntax highlighting, UTF-8, binary detection