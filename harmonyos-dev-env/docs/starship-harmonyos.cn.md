# starship HarmonyOS 适配记录

## 基本信息

- **项目**: starship — 跨 shell 现代命令行提示符
- **版本**: v1.25.1
- **源码**: `https://github.com/starship-community/starship`（通过 gh-proxy.com 克隆）
- **构建目录**: `$HOME/Claude/starship-build/starship/`
- **二进制路径**: `$HOME/Claude/starship-build/starship/target/release/starship`
- **配置路径**: `/data/storage/el2/base/haps/entry/files/starship/starship.toml`
- **编译时间**: 约 6 分钟（release profile）

## 构建过程

### 1. 克隆源码

```bash
git clone https://gh-proxy.com/https://github.com/starship-community/starship.git starship-build/starship
```

### 2. Cargo 配置

`.cargo/config.toml`:
```toml
[target.aarch64-unknown-linux-ohos]
linker = "/data/service/hnp/bin/clang"

[env]
TMPDIR = "$HOME/Claude/tmpdir"
CC = "/data/service/hnp/bin/clang"
```

### 3. errno Crate 补丁（关键！）

**问题**: HarmonyOS 使用 musl libc，不支持 `strerror_r` 函数（只有 `strerror`）。
但 errno crate 在 `target_os = "linux"` 下调用 `strerror_r`（ohos 继承了这个标识符），
导致链接错误 `undefined symbol: __xpg_strerror_r`。

**补丁**: 修改 cargo registry 中的 errno crate unix.rs，用 `strerror` 替代 `strerror_r`。

受影响的三个 errno crate 版本:
- `errno-0.2.8/src/unix.rs`
- `errno-0.3.10/src/unix.rs`
- `errno-0.3.14/src/unix.rs`

修改要点:
1. `with_description()` 函数: 使用 `CStr::from_ptr(strerror(err.0))` 替代 `strerror_r` 缓冲区写入模式
2. `STRERROR_NAME` 常量: `"strerror_r"` → `"strerror"`
3. extern 块: 用 `fn strerror(errnum: c_int) -> *mut c_char` 替换 `strerror_r` extern 声明
4. import: 移除 `strerror_r`/`size_t`，添加 `c_char`

**注意**: 打补丁后必须手动删除 target/deps 中的 errno 相关 .rlib/.rmeta，
否则 cargo 不会重新编译已缓存的 crate。

```bash
rm -f target/release/deps/*errno*
rm -f target/release/deps/*starship*
cargo build --release
```

### 4. 代码签名

```bash
binary-sign-tool sign -selfSign 1 \
  -inFile target/release/starship \
  -outFile target/release/starship-signed
mv target/release/starship-signed target/release/starship
chmod +x target/release/starship
```

### 5. PATH 和环境配置

添加到 `.zshenv`:
```bash
export STARSHIP_HOME="$HOME/Claude/starship-build/starship/target/release"
export PATH="$STARSHIP_HOME:$PATH"
export STARSHIP_CONFIG="/data/storage/el2/base/haps/entry/files/starship/starship.toml"
```

### 6. zsh 提示符配置

在 `.zshrc` 中将原来的 `PROMPT='%m:%~%# '` 替换为:
```bash
eval "$(starship init zsh)"
```

### 7. starship 配置文件

`/data/storage/el2/base/haps/entry/files/starship/starship.toml`:
- `command_timeout = 5000`（HarmonyOS 上 git 命令可能较慢）
- 简化 format: directory + git_branch + git_status + git_state + rust + cmd_duration + character
- 禁用 right_format（简化终端显示）

## 端到端测试结果

| 测试 | 结果 |
|------|------|
| `starship --version` | ✅ starship 1.25.1 |
| `starship --help` | ✅ 完整帮助输出 |
| `starship init zsh` | ✅ 输出 zsh 初始化脚本 |
| `starship prompt` | ✅ 彩色提示符（目录 + git + rust + character） |
| `starship module directory` | ✅ 目录模块 |
| `starship module git_branch` | ✅ Git 分支模块 |
| `starship preset` | ✅ 预设配置可用 |
| `starship timings` | ✅ 模块计时功能 |

## 问题与解决方案

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `undefined symbol: __xpg_strerror_r` | musl libc 没有 strerror_r，ohos 继承 linux target_os 导致 errno crate 使用 strerror_r | 补丁 errno crate 源码，使用 strerror 替代 |
| cargo 不重新编译打补丁的 crate | target/deps 缓存了旧的 .rlib | 手动 rm errno 相关的 .rlib/.rmeta 文件 |
| 运行二进制时 `permission denied` | 签名后丢失文件权限 | `chmod +x` 恢复执行权限 |
| git 命令超时警告 | HarmonyOS 上 git 命令可能较慢 | 配置 `command_timeout = 5000` |

## 与 zsh 的集成

starship 通过 `eval "$(starship init zsh)"` 集成，它会定义:
- `starship_prompt_func` — 提示符绘制函数
- `precmd` / `preexec` — 命令计时钩子
- `STARSHIP_START_TIME` — 命令执行开始时间追踪

与 HarmonyOS 剪裁版 zsh（无 compinit）正常配合，不需要补全系统支持。