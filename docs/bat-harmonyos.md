# bat (Rust) HarmonyOS (aarch64) Compilation and End-to-End Testing

## 1. Project Information

- **Version**: bat v0.26.1
- **Language**: Rust (edition 2021, rust-version 1.88)
- **Usage**: `cat(1) clone with wings` — syntax highlighting, Git integration, non-printable char display
- **Source**: https://github.com/sharkdp/bat

---

## 2. Clone

GitHub direct doesn't work (port 443 timeout), use proxy:

```bash
git clone --depth 1 https://gh-proxy.com/https://github.com/sharkdp/bat.git
```

All 1000 files checkout success, no filename compatibility issues.

---

## 3. Cargo Configuration

bat's dependencies (like libgit2) need C compiler. System has no `cc` command, must configure clang:

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

Same config pattern as eza — `[env]` `CC` must be set.

---

## 4. Compile

```bash
source ~/.zshenv
export CC=/data/service/hnp/bin/clang

# Release build
cargo build --release
# Success, 7m 03s, 5.6MB output
```

bat's `rust-toolchain.toml` specifies `channel = "1.88"`, our rustc 1.95 is higher, cargo ignores channel without rustup.

**Note**: First `cargo build` downloads many dependencies (syntect syntax highlighter, libgit2, etc.), takes longer. Dependency download needs `SSL_CERT_FILE` set (see Rust adaptation).

---

## 5. Code Signing

```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/bat -outFile target/release/bat-signed -signAlg SHA256withECDSA
mv target/release/bat-signed target/release/bat
chmod +x target/release/bat
```

---

## 6. End-to-End Test Results

All core features tested (release version v0.26.1):

| # | Feature | Command | Result |
|---|---------|---------|--------|
| 1 | Version | `bat --version` | bat 0.26.1 |
| 2 | Basic display | `bat <file>` | Normal with line numbers and decorations |
| 3 | Plain text | `bat -p <file>` | No decoration output normal |
| 4 | Line numbers | `bat -n <file>` | Line numbers normal |
| 5 | Line range | `bat -r 1:10` | Range selection normal |
| 6 | Syntax highlight | `bat -l sh/c/rust` | Multi-language highlight normal |
| 7 | Non-printable | `bat -A` | Null/control chars display normal |
| 8 | Tab conversion | `bat --tabs=4` | Tab to spaces normal |
| 9 | Wrap | `bat --wrap=auto` | Auto wrap normal |
| 10 | Style control | `bat --style=header/grid` | Style combination normal |
| 11 | Pager control | `bat --pager=never` | Disable pager normal |
| 12 | Multi-file | `bat file1 file2` | Multi-file display normal |
| 13 | Line highlight | `bat -H 3:7` | Specific lines highlighted normal |
| 14 | Theme list | `bat --list-themes` | 20+ built-in themes |
| 15 | Language list | `bat --list-languages` | Many languages supported |
| 16 | Binary detect | `bat <.so file>` | Auto-detect binary |
| 17 | UTF-8 | `echo "你好" | bat` | Chinese and emoji normal |
| 18 | Config directory | `bat --config-file` | Normal display |
| 19 | Cache directory | `bat --cache-dir` | Normal display |
| 20 | Diff mode | `bat -d file1 file2` | diff comparison normal |

**HarmonyOS-specific verification**:
- UTF-8 Chinese and emoji display normal
- ELF binary auto-detection and warning
- Config/cache directory at `/data/storage/el2/base/haps/entry/files/bat/`
- Syntax highlight auto-detect for `.zshenv` (shell script)

---

## 7. Known Issues

### 7.1 GitHub direct connection fails

`github.com:443` connection timeout, use `gh-proxy.com` proxy clone. This is HarmonyOS network environment limitation, not bat project issue.

### 7.2 Dependency download time

bat has deep dependency chain (syntect → onig → libgit2 → libopenssl etc), first compile downloads dependencies ~7 minutes. `SSL_CERT_FILE` must be set for crates.io access.

---

## Summary: HarmonyOS bat Compilation Checklist

1. **Clone**: Use `gh-proxy.com` proxy, no filename compatibility issues
2. **Cargo config**: `.cargo/config.toml` set linker + CC + TMPDIR
3. **SSL certificate**: `SSL_CERT_FILE=~/.rust/cacert.pem` (cargo dependency download required)
4. **Compile**: `cargo build --release`, 5.6MB output
5. **Sign**: Build output must `binary-sign-tool -selfSign 1` sign
6. **PATH**: Added to `$HOME/.zshenv`, `bat` command directly available
7. **Features**: 20+ core features all normal, including syntax highlight, UTF-8, binary detection