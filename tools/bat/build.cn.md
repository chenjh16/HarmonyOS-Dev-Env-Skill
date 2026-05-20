# bat (Rust) HarmonyOS (aarch64) 编译与端到端测试

## 1. 项目信息

- **版本**: bat v0.26.1
- **语言**: Rust (edition 2021, rust-version 1.88)
- **用途**: `cat(1) clone with wings` — 支持语法高亮、Git 集成、不可打印字符显示等
- **源码**: https://github.com/sharkdp/bat

---

## 2. 克隆

GitHub 直连不通（端口 443 连接超时），需用代理：

```bash
git clone --depth 1 https://gh-proxy.com/https://github.com/sharkdp/bat.git
```

1000 个文件全部 checkout 成功，无文件名兼容问题。

---

## 3. Cargo 配置

bat 的某些依赖（如 libgit2）需要 C 编译器。系统无 `cc` 命令，必须配置 clang：

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "/storage/Users/currentUser/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

与 eza 相同的配置模式——`[env]` 中 `CC` 变量必须设置。

---

## 4. 编译

```bash
source ~/.zshenv
export CC=/data/service/hnp/bin/clang

# Release build
cargo build --release
# 成功，7m 03s，产物 5.6MB
```

bat 的 `rust-toolchain.toml` 指定 `channel = "1.88"`，我们的 rustc 1.95 高于此要求，无 rustup 时 cargo 直接忽略 channel 指定。

**注意**：首次 `cargo build` 会下载大量依赖（含 syntect 语法高亮引擎、libgit2 等），耗时较长。依赖下载需 `SSL_CERT_FILE` 环境变量设置（见 Rust 适配记录）。

---

## 5. 代码签名

```bash
binary-sign-tool sign -selfSign 1 -inFile target/release/bat -outFile target/release/bat-signed -signAlg SHA256withECDSA
mv target/release/bat-signed target/release/bat
chmod +x target/release/bat
```

---

## 6. 端到端测试结果

所有核心功能测试通过（使用 release 版 v0.26.1）：

| # | 功能 | 命令 | 结果 |
|---|------|------|------|
| 1 | 版本 | `bat --version` | bat 0.26.1 |
| 2 | 基本显示 | `bat <file>` | 正常，带行号和装饰 |
| 3 | 纯文本模式 | `bat -p <file>` | 无装饰输出正常 |
| 4 | 行号 | `bat -n <file>` | 行号显示正常 |
| 5 | 行范围 | `bat -r 1:10` | 范围选择正常 |
| 6 | 语法高亮 | `bat -l sh/c/rust` | 多语言高亮正常 |
| 7 | 不可打印字符 | `bat -A` | Null/控制字符显示正常 |
| 8 | Tab 转换 | `bat --tabs=4` | Tab 空格转换正常 |
| 9 | Wrap | `bat --wrap=auto` | 自动换行正常 |
| 10 | 样式控制 | `bat --style=header/grid` | 样式组合正常 |
| 11 | Pager 控制 | `bat --pager=never` | 禁用 pager 正常 |
| 12 | 多文件 | `bat file1 file2` | 多文件显示正常 |
| 13 | 行高亮 | `bat -H 3:7` | 指定行高亮正常 |
| 14 | 主题列表 | `bat --list-themes` | 20+ 内置主题 |
| 15 | 语言列表 | `bat --list-languages` | 大量语言支持 |
| 16 | 二进制检测 | `bat <.so file>` | 自动检测二进制 |
| 17 | UTF-8 | `echo "你好" | bat` | 中文和 emoji 正常 |
| 18 | 配置目录 | `bat --config-file` | 正常显示 |
| 19 | 缓存目录 | `bat --cache-dir` | 正常显示 |
| 20 | Diff 模式 | `bat -d file1 file2` | diff 比较正常 |

**HarmonyOS 特殊验证**：
- UTF-8 中文和 emoji 显示正常
- ELF 二进制文件自动检测和警告
- 配置/缓存目录指向 `/data/storage/el2/base/haps/entry/files/bat/`
- 语法高亮对 `.zshenv`（shell script）自动检测正确

---

## 7. 已知问题

### 7.1 GitHub 直连不通

`github.com:443` 连接超时，需用 `gh-proxy.com` 代理克隆。这是 HarmonyOS 网络环境限制，不是 bat 项目问题。

### 7.2 依赖下载耗时

bat 依赖链较深（含 syntect → onig → libgit2 → libopenssl 等），首次编译下载依赖约 7 分钟。`SSL_CERT_FILE` 必须设置才能访问 crates.io。

---

## 总结：HarmonyOS 编译 bat 的关键 Checklist

1. **克隆**：用 `gh-proxy.com` 代理，无文件名兼容问题
2. **Cargo 配置**：`.cargo/config.toml` 设置 linker + CC + TMPDIR
3. **SSL 证书**：`SSL_CERT_FILE=~/.rust/cacert.pem`（cargo 下载依赖必需）
4. **编译**：`cargo build --release`，产物 5.6MB
5. **签名**：编译产物必须 `binary-sign-tool -selfSign 1` 签名
6. **PATH**：已加入 `$HOME/.zshenv`，`bat` 命令直接可用
7. **功能**：20+ 核心功能全部正常，含语法高亮、UTF-8、二进制检测