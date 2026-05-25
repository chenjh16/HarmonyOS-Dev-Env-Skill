# eza (Rust) HarmonyOS (aarch64) 编译与端到端测试

## 1. 项目信息

- **版本**: eza v0.23.4
- **语言**: Rust (edition 2024, rust-version 1.90)
- **用途**: 现代化的 `ls` 命令替代品，支持颜色、图标、树形视图、Git 状态等
- **源码**: https://github.com/eza-community/eza

---

## 2. 克隆

```bash
git clone --depth 1 https://github.com/eza-community/eza.git
```

GitHub 直连正常，716 个文件全部 checkout 成功（没有 HarmonyOS 文件名兼容问题）。

---

## 3. Cargo 配置

eza 的某些依赖（如 libgit2）需要 C 编译器。系统无 `cc` 命令，必须配置 clang：

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

**关键**：`[env]` 中的 `CC` 变量必须设置，否则 `cc-rs` crate 找不到 C 编译器导致构建失败。

---

## 4. SSL 证书问题

musl 版 cargo 没有内置 CA 证书，访问 crates.io 时报 SSL 错误：
```
[60] SSL peer certificate or SSH remote key was not OK
```

**解决**：从 Python certifi 包复制 CA 证书，设置 `SSL_CERT_FILE` 环境变量：
```bash
cp /data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/certifi/cacert.pem \
   ~/.rust/cacert.pem
export SSL_CERT_FILE=~/.rust/cacert.pem
```

此配置已写入 `$HOME/.zshenv`，每次 shell 启动自动生效。

---

## 5. 编译

```bash
source ~/.zshenv

# Debug build
cargo build
# 成功，1m 30s，产物 49MB

# Release build
cargo build --release
# 成功，3m 05s，产物 2.0MB
```

`rust-toolchain.toml` 指定 `channel = "1.90"`，但我们使用 rustc 1.95（高于要求版本），无 rustup 的情况下 cargo 直接忽略此文件中的 channel 指定。

---

## 6. 代码签名

编译产物必须签名才能在 HarmonyOS 上运行：
```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/eza -outFile target/release/eza-signed -signAlg SHA256withECDSA
mv target/release/eza-signed target/release/eza
chmod +x target/release/eza
```

---

## 7. 端到端测试结果

所有核心功能测试通过（使用 release 版 v0.23.4）：

| # | 功能 | 命令 | 结果 |
|---|------|------|------|
| 1 | 版本 | `eza --version` | v0.23.4 [+git] |
| 2 | 基本列表 | `eza <dir>` | 正常显示目录内容 |
| 3 | 长格式 | `eza -l <dir>` | 权限、大小、日期正常 |
| 4 | 树形视图 | `eza --tree <dir>` | 正常递归显示 |
| 5 | 层级限制 | `eza --tree --level=2` | 正常限制深度 |
| 6 | 图标 | `eza --icons=always` | Nerd Font 图标正常 |
| 7 | 人可读大小 | `eza -lh` | 显示 KB/MB/GB |
| 8 | 八进制权限 | `eza -lo` | 显示 2771 等 |
| 9 | 排序 | `eza --sort=modified` | 按时间排序正常 |
| 10 | 隐藏文件 | `eza -la` | 显示 .开头的文件 |
| 11 | Git 状态 | `eza --git` | 在 git repo 中正常 |
| 12 | inode | `eza -li` | 显示 inode 号 |
| 13 | 颜色缩放 | `eza -l --color-scale=size` | 文件大小色标正常 |
| 14 | 符号链接 | `eza -l <symlinks>` | 正常显示链接目标 |
| 15 | 扩展属性 | `eza -l --extended` | 显示 SELinux、hmdfs 属性 |
| 16 | 仅目录 | `eza --only-dirs` | 过滤正常 |
| 17 | 文件分类 | `eza --classify=always` | 可执行文件标 * |
| 18 | 挂载信息 | `eza --mounts` | 正常显示 |
| 19 | 网格视图 | `eza --grid` | 正常显示 |
| 20 | Header | `eza --header` | 正常显示 |

**HarmonyOS 特殊功能验证**：
- SELinux context 显示正常（`u:object_r:hmdfs:s0`）
- hmdfs 扩展属性正常（`user.hmdfs.perm`）
- 符号链接解析正常（包括跨文件系统的 `/system/lib64/` 链接）

---

## 8. 已知问题

### 8.1 部分参数语法变更

eza v0.23.4 中某些参数不再是直接传路径值：
- `--icons` → `--icons=always`（不接受路径参数）
- `--classify` / `-F` → `--classify=always`
- `--time` → `--sort=modified`（时间排序）

这些是 eza 版本升级的 CLI 变更，不是 HarmonyOS 适配问题。

### 8.2 依赖 libgit2 的 C 编译

eza 的 `git2` crate 依赖 libgit2 C 库，需要 `CC` 环境变量指向 clang。cargo config.toml 的 `[env]` 段可解决此问题。

---

## 总结：HarmonyOS 编译 eza 的关键 Checklist

1. **克隆**：GitHub 直连正常，无文件名兼容问题
2. **Cargo 配置**：`.cargo/config.toml` 设置 linker + CC + TMPDIR
3. **SSL 证书**：`SSL_CERT_FILE=~/.rust/cacert.pem`（从 Python certifi 包获取）
4. **编译**：`cargo build --release`，产物 2.0MB
5. **签名**：所有编译产物必须 `binary-sign-tool -selfSign 1` 签名
6. **PATH**：已加入 `$HOME/.zshenv`，`eza` 命令直接可用
7. **功能**：20+ 核心功能全部正常，含 HarmonyOS 特有的 SELinux 和 hmdfs 属性