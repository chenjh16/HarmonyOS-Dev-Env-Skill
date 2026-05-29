---
name: harmonyos-dev-env
description: HarmonyOS PC 开发环境技能包。提供完整平台知识（代码签名、只读 /tmp、无 gcc、ld.bfd 封装、LD_LIBRARY_PATH 顺序）和工具链适配指南（Python、Rust、Go、PyTorch、llama.cpp、OpenSSH 等）。构建、编译或配置 HarmonyOS 上的任何软件时使用，或当用户提到"鸿蒙"、"HarmonyOS"、"HongMeng"或任何 HarmonyOS 特定问题时使用。需要详细构建指南时请查阅 docs/ 文件。
always-enable: true
---

# HarmonyOS PC 开发环境技能包

### 关键平台规则

1. **代码签名**: 所有 ELF 二进制（可执行文件 + .so）必须使用 `binary-sign-tool sign -selfSign 1 -inFile <unsigned> -outFile <signed> -signAlg SHA256withECDSA` 签名才能执行。未签名二进制立即崩溃。

2. **/tmp 只读**: 使用 `$HOME/Claude/tmpdir` 替代。所有构建系统中需覆盖 `TMPDIR`、`os.tmpname()`、`io.tmpfile()`。

3. **无 gcc**: 只有 `/data/service/hnp/bin/clang` (clang 15.0.4) 可用。所有构建需设置 `CC=/data/service/hnp/bin/clang CXX=/data/service/hnp/bin/clang++`。

4. **SDK lld 损坏**: 需要 `libxml2.so.16`（不存在）。必须创建 ld.bfd 封装：
   ```bash
   mkdir -p $HOME/Claude/lib/linker_wrapper
   cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
   #!/bin/sh
   exec /data/service/hnp/bin/ld.bfd "$@"
   EOF
   chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
   ```
   所有 clang 编译命令需添加 `-B$HOME/Claude/lib/linker_wrapper`。

5. **LD_LIBRARY_PATH 顺序**: `/usr/lib` 必须在 `$HOME/.rust/lib` 前面，避免 OpenSSL 符号版本冲突（OPENSSL_3.0.0 vs OPENSSLOH_3.0.0）。

6. **make -j 失败**: `mkfifo` 返回 "Operation not permitted"——使用 Ninja 进行并行构建。

7. **不要用 CMAKE_TOOLCHAIN_FILE + CMAKE_SYSTEM_NAME**: 会触发交叉编译模式导致 `try_run()` 失败。直接通过 `-DCMAKE_C_COMPILER` 和 `-DCMAKE_CXX_COMPILER` 传递编译器标志。

8. **SSH V8 崩溃**: 鸿蒙 PTY + V8 JIT 崩溃 (ENOMEM)。SSH 会话需使用 `node --jitless` + `node-fetch` polyfill。

9. **OpenSSH passwd_compat**: sshd 需要 `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so`，因为 uid 20020106 不在 /etc/passwd（只读）。子进程环境必须保留 LD_PRELOAD/LD_LIBRARY_PATH（patch session.c）。

10. **OpenSSH 抽象 socket**: ssh-agent bind() 对文件系统 Unix socket 返回 EPERM。使用抽象命名空间回退（`SSH_AUTH_SOCK=abstract:<name>`）。

11. **OpenSSH authorized_keys UID**: 文件所有者为 uid 20001006 (file_manager)，进程运行在 uid 20020106。`platform_sys_dir_uid()` 接受 20001006 为系统所有者。`safe_path()` 跳过系统拥有文件的 mode 检查。StrictModes=yes 正常工作。

12. **Dropbear -e 参数**: 必须使用 `-e` 参数启动 dropbear，传递父进程环境给子会话（LD_LIBRARY_PATH、PATH 等）。

13. **musl libc**: 无 `crypt()`（无密码认证）、无 `strerror_r`（errno crate 需补丁）、locale 支持有限、`__assert_fail` 使用 `int line` 无 `noexcept`。

14. **Python -rdynamic**: 我们的 Python 通过 `-rdynamic` 导出 948+ Py 符号，支持用户路径的签名 .so 扩展模块。无需仅限静态扩展。

15. **Node.js dlopen 签名**: HNP Node 二进制没有 .codesign 段 → 内核阻止 `process.dlopen()` 加载用户空间 .node/.so 文件。修复：创建签名副本（`binary-sign-tool sign -selfSign 1`）放在 `$HOME/.local/bin/node-harmonyos`，PATH 中 `$HOME/.local/bin` 优先。原生 addon 需要：`patchelf --add-needed libc++_shared.so` + 代码签名。使用 `sign-node-addon.sh` 脚本自动化。

16. **psutil HarmonyOS 补丁**: `sys.platform.startswith("harmonyos")` 应视为 Linux。修补 `_common.py`：添加 `or sys.platform.startswith("harmonyos")` 到 LINUX 检查。修补 `net.c`：在 `#include <linux/if.h>` 前 `#define sockaddr_storage __guard` 然后 `#undef`（防止重定义冲突）。

17. **maturin 直接构建**: pip 构建隔离破坏 HarmonyOS 上的 maturin。Rust/PyO3 包直接用 `maturin build --release --interpreter $HOME/.local/bin/python3` 构建，然后签名 .so、重命名后缀为 `.cpython-312-aarch64-linux-gnu.so`、手动安装到 site-packages。

18. **Meson 自动签名包装器**: 在 `$HOME/Claude/lib/meson_wrapper/clang` 创建包装器，自动签名所有 ELF 输出（包括 PIE/DYN 类型）。用作 meson native.ini 的 CC。使用 mesonpy Python API 构建。

19. **sharp WASM32 回退**: `npm install --force @img/sharp-wasm32`。所有操作正常工作，比原生慢约 5-10 倍。

### 工具链快速参考

| 工具 | 版本 | 安装路径 | 关键特性 |
|------|------|----------|----------|
| Python | 3.12.8 | `$HOME/.local` | pip, -rdynamic, numpy, pillow, lxml, psutil, pydantic v2, pandas |
| Node.js | 24.13.0 | `$HOME/.local/bin` | 签名二进制, 原生 addon, sharp WASM32, MCP SDK + Anthropic SDK, 31/31 测试 |
| Rust | 1.95.0 | `$HOME/.rust` | aarch64-unknown-linux-ohos 目标 |
| Go | 1.22.5 | `$HOME/Claude/go-build/go` | GOPROXY=goproxy.cn |
| PyTorch | 2.5.1 | `$HOME/.local/lib/.../torch` | LAPACK, NumPy, 15/15 测试 |
| llama.cpp | b9073 | `$HOME/Claude/llama.cpp/build/bin` | NEON/SVE, ~4x prompt eval 加速 |
| mihomo | Meta | `$HOME/Claude/mihomo-build/bin` | HTTP/SOCKS5, GEOIP/GEOSITE |
| Dropbear | 2024.86 | `$HOME/.local/bin` | 仅公钥认证, -e 参数, 5 补丁 |
| OpenSSH | 9.9p1 | `$HOME/Claude/openssh-build/openssh-prefix/bin` | 16 补丁, scp/sftp/ssh-agent |
| eza | 0.23.4 | `$HOME/Claude/eza-build/.../release` | 现代 ls |
| bat | 0.26.1 | `$HOME/Claude/bat-build/.../release` | 语法高亮 cat |
| starship | 1.25.1 | `$HOME/Claude/starship-build/.../release` | 跨 shell 提示符 |
| Claude Code | 2.1.88-ohos.1 | npm global | 鸿蒙原生, ripgrep 自动签名 |

### 适配指南位置

完整构建指南在本 skill 的 `docs/` 目录中。当用户询问特定工具时，使用 Read 工具从本 SKILL.cn.md 目录的相对路径读取对应指南：

- `docs/python-harmonyos.cn.md` — Python 3.12.8 独立构建
- `docs/python-packages-harmonyos.cn.md` — 59 个包测试（orjson、matplotlib、httpx、pytest、mcp、rpds-py 均可用；scipy/uvloop 无法构建），C/Rust/Meson 扩展解决方案
- `docs/python-extension-adaptation.cn.md` — **适配 C/Rust/C++/Meson Python 包的通用指南**
- `docs/rust-harmonyos.cn.md` — Rust ohos 目标安装
- `docs/pytorch-harmonyos.cn.md` — PyTorch v2.5.1, 15/15 测试
- `docs/openssh-harmonyos.cn.md` — OpenSSH 9.9p1, 16 补丁
- `docs/dropbear-harmonyos.cn.md` — Dropbear, 5 补丁, V8 崩溃
- `docs/llama-cpp-harmonyos.cn.md` — NEON/SVE 优化, Qwen3.5
- `docs/claude-code-harmonyos.cn.md` — Claude Code ohos 适配
- `docs/nodejs-harmonyos.cn.md` — **Node.js dlopen 修复, 原生 addon 签名, sharp WASM32, MCP SDK + Anthropic SDK, 31/31 测试**
- `docs/mihomo-harmonyos.cn.md` — HTTP/SOCKS5, GEOIP/GEOSITE
- `docs/eza-harmonyos.cn.md` — 现代 ls
- `docs/bat-harmonyos.cn.md` — 语法高亮 cat
- `docs/starship-harmonyos.cn.md` — 跨 shell 提示符
- `docs/code-signing.cn.md` — ELF/HAP 签名指南
- `docs/ld-library-path.cn.md` — LD_LIBRARY_PATH 顺序
- `docs/selinux-analysis.cn.md` — .so 加载根因
- `docs/ipc-feasibility.cn.md` — Native 子进程 API
- `docs/troubleshooting.cn.md` — 综合故障排除

带 install.sh 的工具构建指南在 `tools/` 目录中：
- `tools/python/`, `tools/rust/`, `tools/go/`, `tools/llama-cpp/`, `tools/mihomo/`, `tools/dropbear/`, `tools/openssh/`, `tools/pytorch/`, `tools/bat/`, `tools/eza/`, `tools/starship/`

### 快捷命令

```bash
# 一次性环境设置（创建 $HOME/Claude 基础目录、tmpdir、linker wrapper、复制 zshenv）
# $HOME/Claude 是所有工具链安装的约定目录——env-setup.sh 会自动创建
sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh

# 批量代码签名
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-all.sh <目录>

# 签名 Node.js 原生 addon (.node 文件)
sh ~/.claude/skills/harmonyos-dev-env/scripts/sign-node-addon.sh <.node-文件路径>

# 环境验证
sh ~/.claude/skills/harmonyos-dev-env/scripts/verify-env.sh
```