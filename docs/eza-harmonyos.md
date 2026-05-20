# eza (Rust) HarmonyOS (aarch64) Compilation and End-to-End Testing

## 1. Project Information

- **Version**: eza v0.23.4
- **Language**: Rust (edition 2024, rust-version 1.90)
- **Usage**: Modern `ls` replacement with colors, icons, tree view, Git status
- **Source**: https://github.com/eza-community/eza

---

## 2. Clone

```bash
git clone --depth 1 https://github.com/eza-community/eza.git
```

GitHub direct connection works normally, all 716 files checkout success (no HarmonyOS filename compatibility issues).

---

## 3. Cargo Configuration

eza's dependencies (like libgit2) need C compiler. System has no `cc` command, must configure clang:

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

**Critical**: `[env]` `CC` variable must be set, otherwise `cc-rs` crate won't find C compiler causing build failure.

---

## 4. SSL Certificate Issue

musl version cargo doesn't have built-in CA certificates, SSL error accessing crates.io:
```
[60] SSL peer certificate or SSH remote key was not OK
```

**Solution**: Copy CA certificates from Python certifi package, set `SSL_CERT_FILE`:
```bash
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/certifi/cacert.pem \
   ~/.rust/cacert.pem
export SSL_CERT_FILE=~/.rust/cacert.pem
```

This config is in `$HOME/.zshenv`, auto-applies on shell startup.

---

## 5. Compile

```bash
source ~/.zshenv

# Debug build
cargo build
# Success, 1m 30s, 49MB output

# Release build
cargo build --release
# Success, 3m 05s, 2.0MB output
```

`rust-toolchain.toml` specifies `channel = "1.90"`, but we use rustc 1.95 (higher than required), cargo ignores channel specification without rustup.

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

All core features tested (release version v0.23.4):

| # | Feature | Command | Result |
|---|---------|---------|--------|
| 1 | Version | `eza --version` | v0.23.4 [+git] |
| 2 | Basic list | `eza <dir>` | Normal directory display |
| 3 | Long format | `eza -l <dir>` | Permissions, size, date normal |
| 4 | Tree view | `eza --tree <dir>` | Recursive display normal |
| 5 | Level limit | `eza --tree --level=2` | Depth limit normal |
| 6 | Icons | `eza --icons=always` | Nerd Font icons normal |
| 7 | Human-readable size | `eza -lh` | Shows KB/MB/GB |
| 8 | Octal permissions | `eza -lo` | Shows 2771 etc |
| 9 | Sorting | `eza --sort=modified` | Time sorting normal |
| 10 | Hidden files | `eza -la` | Shows .* files |
| 11 | Git status | `eza --git` | Works in git repo |
| 12 | inode | `eza -li` | Shows inode number |
| 13 | Color scale | `eza -l --color-scale=size` | Size color scale normal |
| 14 | Symlinks | `eza -l <symlinks>` | Shows link target |
| 15 | Extended attrs | `eza -l --extended` | Shows SELinux, hmdfs attrs |
| 16 | Only dirs | `eza --only-dirs` | Filter normal |
| 17 | File classify | `eza --classify=always` | Executable files marked * |
| 18 | Mount info | `eza --mounts` | Normal display |
| 19 | Grid view | `eza --grid` | Normal display |
| 20 | Header | `eza --header` | Normal display |

**HarmonyOS-specific verification**:
- SELinux context display normal (`u:object_r:hmdfs:s0`)
- hmdfs extended attributes normal (`user.hmdfs.perm`)
- Symlink resolution normal (including cross-filesystem `/system/lib64/` links)

---

## 8. Known Issues

### 8.1 Some parameter syntax changes

eza v0.23.4 some parameters no longer accept path values directly:
- `--icons` → `--icons=always` (doesn't accept path parameter)
- `--classify` / `-F` → `--classify=always`
- `--time` → `--sort=modified` (time sorting)

These are eza version CLI changes, not HarmonyOS adaptation issues.

### 8.2 libgit2 C compilation dependency

eza's `git2` crate depends on libgit2 C library, needs `CC` env var pointing to clang. cargo config.toml `[env]` section solves this.

---

## Summary: HarmonyOS eza Compilation Checklist

1. **Clone**: GitHub direct works, no filename compatibility issues
2. **Cargo config**: `.cargo/config.toml` set linker + CC + TMPDIR
3. **SSL certificate**: `SSL_CERT_FILE=~/.rust/cacert.pem` (from Python certifi)
4. **Compile**: `cargo build --release`, 2.0MB output
5. **Sign**: All build outputs must `binary-sign-tool -selfSign 1` sign
6. **PATH**: Added to `$HOME/.zshenv`, `eza` command directly available
7. **Features**: 20+ core features all normal, including HarmonyOS-specific SELinux and hmdfs attributes