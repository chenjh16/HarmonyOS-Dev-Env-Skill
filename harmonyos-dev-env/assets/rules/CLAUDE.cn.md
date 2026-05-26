# HarmonyOS 开发环境 - 全局规则

> **注意**: 本文件 (`CLAUDE.cn.md`) 是中文版本。英文版本 (`CLAUDE.md`) 需同步维护。编辑本文件时，请同步更新英文版本。

## 平台: HarmonyOS (鸿蒙内核 1.12.0, aarch64)

### 文件系统与权限

- `/tmp` 在此系统上是 **只读** 的 — 不要用于临时文件、构建或 os.tmpname()
- 可写的临时目录是 `$HOME/Claude/tmpdir/` — 用此代替 /tmp
- 在 Lua 或其他脚本中覆盖 `os.tmpname` 时，将输出重定向到 `$HOME/Claude/tmpdir/`
- `io.tmpfile()` (C 标准库 tmpfile) 在 HarmonyOS 上返回 NULL — 使用替代方案: 在可写目录中 fopen 然后 unlink
- 用户主目录是 `$HOME/` (不是 /home/)

### 代码签名 (关键)

- **所有 ELF 二进制文件执行前必须签名** — 包括:
  - 编译的 C/C++ 程序 (clang 输出)
  - Go 编译的二进制
  - Rust 编译的二进制
  - Python 扩展模块 (.so 文件)
  - 从源码构建的任何可执行文件

**签名命令**:
```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile <未签名二进制> \
  -outFile <已签名二进制> \
  -signAlg SHA256withECDSA
```

开发/测试使用 `-selfSign 1`。生产环境需使用正式证书。

**快速验证**: 签名后检查:
```bash
/data/service/hnp/bin/binary-sign-tool display-sign -inFile <二进制>
```

完整文档见 code-signing.cn.md（位于 skill 的 `docs/` 目录）。

### 工具链 (无 gcc)

- **CC**: `/data/service/hnp/bin/clang` (clang 15.0.4, aarch64-unknown-linux-ohos 目标)
- **AR**: `/data/service/hnp/bin/ar`
- **RANLIB**: `/data/service/hnp/bin/ranlib`
- **MAKE**: `/data/service/hnp/bin/make`
- **CMAKE**: `/data/service/hnp/bin/cmake`
- **NINJA**: `/data/service/hnp/bin/ninja`
- **LD**: `/data/service/hnp/bin/ld.lld` — **已损坏** (需要 libxml2.so.16，该库不存在)
- **STRIP**: `/data/service/hnp/bin/llvm-strip`
- **NM**: `/data/service/hnp/bin/llvm-nm`
- **OBJCOPY**: `/data/service/hnp/bin/llvm-objcopy`
- **OBJDUMP**: `/data/service/hnp/bin/llvm-objdump`
- **READELF**: `/data/service/hnp/bin/llvm-readelf`
- **GDB**: `/data/service/hnp/bin/gdb`
- **LLDB**: `/data/service/hnp/bin/lldb`
- 没有 `gcc` — 始终使用 clang。不要编写默认使用 gcc 的 Makefile。
- Clang 三元组目标: `aarch64-unknown-linux-ohos-clang`, `armv7-unknown-linux-ohos-clang`
- **`make -j` 在 HarmonyOS 上失败**: mkfifo 返回"Operation not permitted"（jobserver 使用 mkfifo 进行并行构建）。请使用 Ninja。
- **不要使用 CMAKE_TOOLCHAIN_FILE 配合 CMAKE_SYSTEM_NAME**: 会触发 CMake 交叉编译模式导致 try_run() 失败。使用轻量级工具链文件（仅编译器+链接器封装，无 CMAKE_SYSTEM_NAME）或直接传递编译器标志。
- **OpenBLAS/LAPACK**: 编译 OpenBLAS v0.3.28（NOFORTRAN=1）；修改 Makefile.prebuild 添加 -B 封装+代码签名；从 .a 创建 .so；在 CMake 中显式设置 LAPACK_LIBRARIES 和 LAPACK_FOUND
- **Sleef NATIVE_BUILD_DIR**: 修改 sleef CMakeLists.txt 的 add_host_executable，在 NATIVE_BUILD_DIR 提供时使用，即使无 CMAKE_CROSSCOMPILING
- **CMake 4.1.2 ldd**: CMake 4.1.2 链接后运行 ldd；将 ldd 封装复制到 ~/.local/bin/ldd

**关键**: SDK 的 lld 需要不存在于 HarmonyOS 的 `libxml2.so.16`。必须用 ld.bfd 替代：

```bash
mkdir -p $HOME/Claude/lib/linker_wrapper
cat > $HOME/Claude/lib/linker_wrapper/ld.lld << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
chmod +x $HOME/Claude/lib/linker_wrapper/ld.lld
```

然后在所有 clang 编译命令中添加 `-B$HOME/Claude/lib/linker_wrapper`，或在 CMake 中设置：
```cmake
set(CMAKE_C_FLAGS "-B$HOME/Claude/lib/linker_wrapper")
set(CMAKE_CXX_FLAGS "-B$HOME/Claude/lib/linker_wrapper")
```
- **Rust**: `rustc 1.95.0` (aarch64-unknown-linux-ohos) 位于 `$HOME/.rust/bin/`; `cargo 1.95.0` (musl) 同路径; 必须使用 `-C linker=/data/service/hnp/bin/clang`; 所有 ELF 二进制执行前必须代码签名
- **llama.cpp**: 构建于 `$HOME/Claude/llama.cpp/build/bin/`; `llama-cli`, `llama-server`, `llama-quantize` 等可用
- **eza**: v0.23.4 位于 `$HOME/Claude/eza-build/eza/target/release/`; 现代 `ls` 替代品，带颜色、图标、树视图
- **bat**: v0.26.1 位于 `$HOME/Claude/bat-build/bat/target/release/`; `cat` 替代品，带语法高亮
- **starship**: v1.25.1 位于 `$HOME/Claude/starship-build/starship/target/release/`; 跨 shell 提示符
- **Go**: v1.22.5 位于 `$HOME/Claude/go-build/go/`; 使用 `GOPROXY=https://goproxy.cn,direct`; 设置 `TMPDIR=$HOME/Claude/tmpdir`
- **mihomo**: Clash Meta 代理位于 `$HOME/Claude/mihomo-build/bin/mihomo-linux-arm64`; 配置位于 `$HOME/Claude/mihomo-config/`; 代理端口 7890, API 端口 9090; 支持 GEOIP/GEOSITE 智能分流
- **PyTorch**: v2.5.1 位于 `$HOME/.local/lib/python3.12/site-packages/torch/`; **15/15 端到端测试全部通过**（NumPy 通过增量补丁修复，LAPACK 通过 OpenBLAS + supplement.so 启用）; 需要 `LD_LIBRARY_PATH=$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH`; 构建必须使用 Ninja；不要使用 CMAKE_TOOLCHAIN_FILE 配合 CMAKE_SYSTEM_NAME；使用轻量级工具链文件；OpenBLAS v0.3.28 位于 `$HOME/.local/lib/libopenblas.so`; `libtorch_supplement.so` 提供 3 个隐藏符号；patchelf 修复 NEEDED 路径前缀
- **Dropbear**: v2024.86 SSH 服务器/客户端位于 `$HOME/.local/bin/`; `dropbear` (服务器), `dbclient` (客户端), `dropbearkey` (密钥生成); 仅支持公钥认证（无密码认证，因缺少 crypt() 函数）；接受任何非系统用户名（chenh, user, currentUser, UID 均可——单用户设备）；**必须使用 `-e` 参数**（将环境变量传递给子会话）；PTY 交互式会话受限（TIOCSCTTY 在 HarmonyOS 上失败）
- **OpenSSH**: 9.9p1 位于 `$HOME/Claude/openssh-build/openssh-prefix/bin`; `ssh`, `sshd`, `scp`, `sftp`, `ssh-add`, `ssh-agent`, `ssh-keygen`, `ssh-keyscan`; 需要 `LD_PRELOAD=$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so`; ssh-agent 使用抽象命名空间socket (`SSH_AUTH_SOCK=abstract:<name>`); scp/sftp 通过 sshd_config 的 `SetEnv PATH` 正常工作; 已应用全部16个 HarmonyOS 补丁

### PATH 中的第三方工具

所有第三方工具链在 `$HOME/.zshenv` 中配置，shell 启动时自动加载:
- Rust: `$HOME/.rust/bin` → `rustc`, `cargo`
- llama.cpp: `$HOME/Claude/llama.cpp/build/bin` → `llama-cli`, `llama-server` 等
- eza: `$HOME/Claude/eza-build/eza/target/release` → `eza`
- bat: `$HOME/Claude/bat-build/bat/target/release` → `bat`
- starship: `$HOME/Claude/starship-build/starship/target/release` → `starship`
- Dropbear: `$HOME/.local/bin` → `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`
- OpenSSH: `$HOME/Claude/openssh-build/openssh-prefix/bin` → `ssh`, `sshd`, `scp`, `sftp`, `ssh-add`, `ssh-agent`, `ssh-keygen`, `ssh-keyscan`; 需要LD_PRELOAD; ssh-agent 使用抽象命名空间socket (`SSH_AUTH_SOCK=abstract:<name>`)
- `LD_LIBRARY_PATH` 包含 `$HOME/.rust/lib`, `/system/lib64` 和 llama.cpp bin 目录
- `LD_PRELOAD` 设置为 `$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so`（用于 OpenSSH sshd）
- `SSL_CERT_FILE` 设置为 `$HOME/.rust/cacert.pem` (用于 cargo crates.io 访问)
- `TMPDIR` 设置为 `$HOME/Claude/tmpdir` (因为 HarmonyOS 上 `/tmp` 只读)

**关键**: LD_LIBRARY_PATH 中 `/usr/lib` 必须在 `$HOME/.rust/lib` 前面，否则会导致 OpenSSL 符号版本冲突！详见 ld-library-path.cn.md（位于 skill 的 `docs/` 目录）

### 代码签名

- **ELF 签名**: `/data/service/hnp/bin/binary-sign-tool`
  - 命令: `sign`, `display-sign`
  - 签名算法: SHA256withECDSA 或 SHA384withECDSA
  - 必需参数: `-keyAlias`, `-appCertFile`, `-profileFile`, `-inFile`, `-outFile`, `-keystoreFile`, `-signAlg`
  - 自签名选项: `-selfSign 1` 用于本地测试
  - 示例: `binary-sign-tool sign -keyAlias "key" -appCertFile cert.cer -profileFile profile.p7b -inFile unsigned.elf -outFile signed.elf -keystoreFile keystore.p12 -signAlg SHA256withECDSA`

- **HAP/App 签名**: `/data/service/hnp/bin/hap-sign-tool`
  - 命令: `generate-keypair`, `generate-csr`, `generate-cert`, `generate-ca`, `generate-app-cert`, `generate-profile-cert`, `sign-profile`, `verify-profile`, `sign-app`, `verify-app`
  - 密钥算法: ECC (NIST-P-256 / NIST-P-384)

### 设备部署

- **hdc** (HarmonyOS 设备连接器): `/data/service/hnp/bin/hdc` (v3.1.0e)
  - 类似 Android 的 adb — 用于应用安装、文件推送、shell 访问、调试

### 内核与运行时差异

- `io.stdin:seek("set", ...)` 在 HarmonyOS 上成功 (返回 0) 而非失败 — 期望 stdin seek 失败的测试需要 `_port = true`
- C 标准库函数 `tmpfile()`, `mkstemp()` 可能不工作 — 优先在可写目录显式创建文件
- `os.tmpname()` 返回 `/tmp` 下路径，该目录只读 — 必须覆盖或重定向
- 动态库加载 (Lua `require` .so) 可能不工作 — 跳过相关测试
- 本地化支持有限 (无 pt_BR, collate, ctype locale) — 跳过依赖 locale 的测试
- musl libc 差异: `__assert_fail` 签名使用 `int line` 无 `noexcept` (glibc 使用 `unsigned int` + `noexcept`)

### Python 环境

- **Python**: `$HOME/.local/bin/python3` (3.12.8) — 唯一源，支持 pip 和扩展模块加载
- **pip 镜像**: `pypi.tuna.tsinghua.edu.cn`
- **扩展模块 (.so) 必须签名** 才能加载
- **C/C++ 扩展包**: 安装前设置 `CC=/data/service/hnp/bin/clang` 和 `CXX=/data/service/hnp/bin/clang++`

详见 python-harmonyos.cn.md（位于 skill 的 `docs/` 目录）。

### 适配经验

详细适配指南位于 skill 的 `docs/` 目录。skill 安装目录取决于安装范围：
- **全局安装**: `~/.claude/skills/harmonyos-dev-env/docs/`
- **项目级安装**: `<项目>/.claude/skills/harmonyos-dev-env/docs/`

使用 Read 工具按对应路径读取。可用指南：

| 文件 | 说明 |
|------|------|
| claude-code-harmonyos.cn.md | AI 编程助手、npm 包安装、SSH V8 崩溃解决方案 |
| nodejs-harmonyos.cn.md | Node.js 安装、TLS/V8 问题、npm 配置 |
| python-harmonyos.cn.md | 安装位置、配置、numpy/pillow/lxml 安装 |
| python-packages-harmonyos.cn.md | 34 个包测试结果，C/Rust 扩展解决方案 |
| python-extension-adaptation.cn.md | **适配 C/Rust/C++ Python 包的通用指南**（签名、patchelf、supplement.so、.so 后缀） |
| llama-cpp-harmonyos.cn.md | 构建、NEON/SVE 优化、ModelScope 模型下载 |
| rust-harmonyos.cn.md | 工具链安装、签名、cargo 配置、FFI 互操作 |
| eza-harmonyos.cn.md | Rust 项目编译、SELinux/hmdfs 属性显示 |
| bat-harmonyos.cn.md | Rust 项目编译、语法高亮 |
| starship-harmonyos.cn.md | Rust 项目编译、errno 补丁、prompt 配置 |
| mihomo-harmonyos.cn.md | Go 工具链、代理配置、GEOIP/GEOSITE 分流规则 |
| pytorch-harmonyos.cn.md | PyTorch v2.5.1 编译、15个关键适配、15/15 测试全部通过、MNIST 训练 |
| dropbear-harmonyos.cn.md | SSH 服务器/客户端、5个源码补丁、V8 JIT 崩溃解决方案 |
| openssh-harmonyos.cn.md | OpenSSH 9.9p1 完整构建、16个源码补丁、scp/sftp/ssh-agent 全功能可用 |
| code-signing.cn.md | 详细代码签名说明 |
| ld-library-path.cn.md | 动态库路径配置 |
| selinux-analysis.cn.md | .so 加载限制的根本原因 |
| ipc-feasibility.cn.md | Native Child Process API 分析 |
| troubleshooting.cn.md | 综合问题解决参考 |