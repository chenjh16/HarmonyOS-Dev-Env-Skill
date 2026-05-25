# bat (Rust) HarmonyOS (aarch64) 编译与端到端测试

## 1. 项目信息

- **版本**: bat v0.26.1
- **语言**: Rust (edition 2021, rust-version 1.88)
- **用途**: `cat(1) clone with wings` — 语法高亮、Git 集成、不可见字符显示
- **源码**: https://github.com/sharkdp/bat

---

## 2. 克隆

GitHub 直连失败（443 端口超时），使用代理:

```bash
git clone --depth 1 https://gh-proxy.com/https://github.com/sharkdp/bat.git
```

全部 1000 个文件检出成功，无文件名兼容性问题。

---

## 3. Cargo 配置

bat 的依赖（如 libgit2）需要 C 编译器。系统没有 `cc` 命令，必须配置 clang:

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

与 eza 相同的配置模式 — `[env]` 中必须设置 `CC`。

---

## 4. 编译

```bash
source ~/.zshenv
export CC=/data/service/hnp/bin/clang

# Release 构建
cargo build --release
# 成功，7分03秒，5.6MB 输出
```

bat 的 `rust-toolchain.toml` 指定 `channel = "1.88"`，我们的 rustc 1.95 更高，cargo 在没有 rustup 时忽略 channel。

**注意**: 首次 `cargo build` 会下载大量依赖（syntect 语法高亮器、libgit2 等），耗时较长。依赖下载需要设置 `SSL_CERT_FILE`（参见 Rust 适配文档）。

---

## 5. 代码签名

```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/bat -outFile target/release/bat-signed -signAlg SHA256withECDSA
mv target/release/bat-signed target/release/bat
chmod +x target/release/bat
```

---

## 6. 端到端测试结果

测试了所有核心功能（release 版本 v0.26.1）:

| # | 功能 | 命令 | 结果 |
|---|------|------|------|
| 1 | 版本 | `bat --version` | bat 0.26.1 |
| 2 | 基本显示 | `bat <file>` | 行号和装饰正常 |
| 3 | 纯文本 | `bat -p <file>` | 无装饰输出正常 |
| 4 | 行号 | `bat -n <file>` | 行号正常 |
| 5 | 行范围 | `bat -r 1:10` | 范围选择正常 |
| 6 | 语法高亮 | `bat -l sh/c/rust` | 多语言高亮正常 |
| 7 | 不可见字符 | `bat -A` | 空字符/控制字符显示正常 |
| 8 | Tab 转换 | `bat --tabs=4` | Tab 转空格正常 |
| 9 | 自动换行 | `bat --wrap=auto` | 自动换行正常 |
| 10 | 样式控制 | `bat --style=header/grid` | 样式组合正常 |
| 11 | 分页器控制 | `bat --pager=never` | 禁用分页器正常 |
| 12 | 多文件 | `bat file1 file2` | 多文件显示正常 |
| 13 | 行高亮 | `bat -H 3:7` | 指定行高亮正常 |
| 14 | 主题列表 | `bat --list-themes` | 20+ 内置主题 |
| 15 | 语言列表 | `bat --list-languages` | 支持多种语言 |
| 16 | 二进制检测 | `bat <.so file>` | 自动检测二进制 |
| 17 | UTF-8 | `echo "你好" | bat` | 中文和 emoji 正常 |
| 18 | 配置目录 | `bat --config-file` | 显示正常 |
| 19 | 缓存目录 | `bat --cache-dir` | 显示正常 |
| 20 | Diff 模式 | `bat -d file1 file2` | diff 对比正常 |

**HarmonyOS 特定验证**:
- UTF-8 中文和 emoji 显示正常
- ELF 二进制自动检测和警告
- 配置/缓存目录位于 `/data/storage/el2/base/haps/entry/files/bat/`
- `.zshenv` 文件语法高亮自动识别为 shell 脚本

---

## 7. 已知问题

### 7.1 GitHub 直连失败

`github.com:443` 连接超时，使用 `gh-proxy.com` 代理克隆。这是 HarmonyOS 网络环境限制，不是 bat 项目问题。

### 7.2 依赖下载时间

bat 依赖链较深（syntect → onig → libgit2 → libopenssl 等），首次编译下载依赖约 7 分钟。访问 crates.io 必须设置 `SSL_CERT_FILE`。

---

## 总结: HarmonyOS bat 编译检查清单

1. **克隆**: 使用 `gh-proxy.com` 代理，无文件名兼容性问题
2. **Cargo 配置**: `.cargo/config.toml` 设置 linker + CC + TMPDIR
3. **SSL 证书**: `SSL_CERT_FILE=~/.rust/cacert.pem`（cargo 下载依赖必需）
4. **编译**: `cargo build --release`，5.6MB 输出
5. **签名**: 构建产物必须 `binary-sign-tool -selfSign 1` 签名
6. **PATH**: 已添加到 `$HOME/.zshenv`，`bat` 命令直接可用
7. **功能**: 20+ 核心功能全部正常，包括语法高亮、UTF-8、二进制检测