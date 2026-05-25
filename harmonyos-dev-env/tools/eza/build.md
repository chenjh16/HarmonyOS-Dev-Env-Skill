# eza (Rust) HarmonyOS (aarch64) Build and End-to-End Testing

> **中文版本见 build.cn.md**

## 1. Project Info

- **Version**: eza v0.23.4
- **Language**: Rust (edition 2024, rust-version 1.90)
- **Purpose**: Modern `ls` command replacement, supports colors, icons, tree view, Git status, etc.
- **Source**: https://github.com/eza-community/eza

---

## 2. Clone

```bash
git clone --depth 1 https://github.com/eza-community/eza.git
```

Direct GitHub connection works, all 716 files checked out successfully (no HarmonyOS filename compatibility issues).

---

## 3. Cargo Configuration

Some of eza's dependencies (such as libgit2) require a C compiler. The system has no `cc` command, so clang must be configured:

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

**Key**: The `CC` variable in `[env]` must be set, otherwise the `cc-rs` crate cannot find the C compiler and the build will fail.

---

## 4. SSL Certificate Issue

The musl version of cargo does not include built-in CA certificates, causing SSL errors when accessing crates.io:
```
[60] SSL peer certificate or SSH remote key was not OK
```

**Solution**: Copy CA certificates from the Python certifi package and set the `SSL_CERT_FILE` environment variable:
```bash
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/certifi/cacert.pem \
   ~/.rust/cacert.pem
export SSL_CERT_FILE=~/.rust/cacert.pem
```

This configuration has been written to `$HOME/.zshenv` and takes effect automatically on each shell startup.

---

## 5. Build

```bash
source ~/.zshenv

# Debug build
cargo build
# Success, 1m 30s, output 49MB

# Release build
cargo build --release
# Success, 3m 05s, output 2.0MB
```

`rust-toolchain.toml` specifies `channel = "1.90"`, but we use rustc 1.95 (higher than the required version), and without rustup, cargo simply ignores the channel specification in this file.

---

## 6. Code Signing

Build output must be signed to run on HarmonyOS:
```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/eza -outFile target/release/eza-signed -signAlg SHA256withECDSA
mv target/release/eza-signed target/release/eza
chmod +x target/release/eza
```

---

## 7. End-to-End Test Results

All core functionality tests passed (using release version v0.23.4):

| # | Feature | Command | Result |
|---|---------|---------|--------|
| 1 | Version | `eza --version` | v0.23.4 [+git] |
| 2 | Basic listing | `eza <dir>` | Directory content displayed normally |
| 3 | Long format | `eza -l <dir>` | Permissions, size, date normal |
| 4 | Tree view | `eza --tree <dir>` | Recursive display works |
| 5 | Level limit | `eza --tree --level=2` | Depth limit works |
| 6 | Icons | `eza --icons=always` | Nerd Font icons work |
| 7 | Human-readable size | `eza -lh` | Shows KB/MB/GB |
| 8 | Octal permissions | `eza -lo` | Shows 2771 etc. |
| 9 | Sort | `eza --sort=modified` | Sort by time works |
| 10 | Hidden files | `eza -la` | Shows dot-prefixed files |
| 11 | Git status | `eza --git` | Works in git repo |
| 12 | inode | `eza -li` | Shows inode numbers |
| 13 | Color scale | `eza -l --color-scale=size` | File size color scale works |
| 14 | Symlinks | `eza -l <symlinks>` | Shows link targets correctly |
| 15 | Extended attributes | `eza -l --extended` | Shows SELinux, hmdfs attributes |
| 16 | Only dirs | `eza --only-dirs` | Filtering works |
| 17 | File classification | `eza --classify=always` | Executable files marked with * |
| 18 | Mount info | `eza --mounts` | Displayed correctly |
| 19 | Grid view | `eza --grid` | Displayed correctly |
| 20 | Header | `eza --header` | Displayed correctly |

**HarmonyOS-specific feature verification**:
- SELinux context display works (`u:object_r:hmdfs:s0`)
- hmdfs extended attributes work (`user.hmdfs.perm`)
- Symlink resolution works (including cross-filesystem `/system/lib64/` links)

---

## 8. Known Issues

### 8.1 Some Parameter Syntax Changes

In eza v0.23.4, some parameters no longer accept path values directly:
- `--icons` -> `--icons=always` (does not accept path parameter)
- `--classify` / `-F` -> `--classify=always`
- `--time` -> `--sort=modified` (time-based sort)

These are CLI changes from eza version upgrades, not HarmonyOS adaptation issues.

### 8.2 C Compilation Dependency on libgit2

eza's `git2` crate depends on the libgit2 C library, which requires the `CC` environment variable pointing to clang. The `[env]` section of cargo config.toml can resolve this issue.

---

## Summary: Key Checklist for Building eza on HarmonyOS

1. **Clone**: Direct GitHub connection works, no filename compatibility issues
2. **Cargo config**: `.cargo/config.toml` set linker + CC + TMPDIR
3. **SSL certificate**: `SSL_CERT_FILE=~/.rust/cacert.pem` (from Python certifi package)
4. **Build**: `cargo build --release`, output 2.0MB
5. **Signing**: All build output must be signed with `binary-sign-tool -selfSign 1`
6. **PATH**: Already added to `$HOME/.zshenv`, `eza` command available directly
7. **Functionality**: 20+ core features all working, including HarmonyOS-specific SELinux and hmdfs attributes