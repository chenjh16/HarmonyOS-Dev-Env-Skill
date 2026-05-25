# HarmonyOS-Dev-Env-Skill 项目 - 开发指南

## 项目概述

本项目是 HarmonyOS PC 开发环境的技能包，提供各种工具（Python、Rust、Go、PyTorch、llama.cpp 等）的完整构建和安装指南。

**目标平台**: HarmonyOS (鸿蒙内核 1.12.0, aarch64)

## 项目结构

Skill 内容存放在自包含的 `harmonyos-dev-env/` 子目录中，安装时直接整体复制到 `~/.claude/skills/`：

```
HarmonyOS-Dev-Env-Skill/
├── harmonyos-dev-env/        ← THE SKILL（cp -r 此目录到 ~/.claude/skills/）
│   ├── SKILL.md              ← Skill 定义（YAML frontmatter + 双语规则）
│   ├── scripts/
│   │   ├── env-setup.sh      ← 一键环境设置（tmpdir + linker wrapper + zshenv）
│   │   ├── sign-all.sh       ← 批量 ELF 签名
│   │   ├── verify-env.sh     ← 环境验证
│   │   ├── ssh-fetch-polyfill.js
│   │   └── start-claude.sh
│   ├── docs/                 ← 18 组双语适配文档（*.md + *.cn.md）
│   ├── tools/                ← 11 工具构建指南 + install.sh
│   ├── config/
│   │   ├── zshenv            ← Shell 环境配置模板
│   │   └── .claude/          ← SSH polyfill + 启动脚本模板
│   └── rules/
│       ├── CLAUDE.md         ← 完整平台规则（英文）
│       └── CLAUDE.cn.md      ← 完整平台规则（中文）
├── CLAUDE.md                 ← 本文件 - 项目开发指南（英文）
├── CLAUDE.cn.md              ← 项目开发指南（中文）
├── README.md                 ← 项目 README（双语合一）
├── skill.json                ← 元数据
├── scripts/
│   └── install-skill.sh      ← 简化版：直接 cp -r harmonyos-dev-env/
├── .gitignore
└── (顶层 config/, docs/, rules/, tools/ 是仓库源码原始文件)
```

**关键原则**: `harmonyos-dev-env/` 必须完全自包含。Shell 脚本使用 `SCRIPT_DIR` 模式查找同级文件。SKILL.md 使用相对路径引用 docs。所有用户可变路径使用 `$HOME`（绝不使用 `/storage/Users/currentUser`）。

## 文档命名规范

所有文档文件遵循双语命名：
- `*.md` - 英文版本
- `*.cn.md` - 中文版本

**例外**: README.md 在同一文件中包含英文和中文内容。

## Agent 开发规则

### 1. 双语文档
- 创建新文档时，必须同时创建 `*.md` 和 `*.cn.md`
- 两个版本中的代码块和命令保持不变
- 翻译标题、说明文字和注释

### 2. skill.json 更新
- 添加新工具时，更新 skill.json：
  - 工具元数据（名称、版本、类别）
  - 文档路径（path 和 path_cn）
- 添加新文档时，更新 documentation 数组

### 3. 路径可移植性
- **绝不使用 `/storage/Users/currentUser`** — 始终使用 `$HOME`
- JavaScript 中：使用 `process.env.HOME`
- C 代码中：使用 `getenv("HOME")`
- 系统路径如 `/data/service/hnp/bin/*`、`/system/lib64`、`/usr/lib` 是可以的（平台固定）
- Shell 脚本必须使用 `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` 查找同级文件

### 4. 文件组织
- `harmonyos-dev-env/docs/` - 通用适配指南（平台级别问题）
- `harmonyos-dev-env/tools/` - 工具特定构建指南
- `harmonyos-dev-env/rules/` - 目标系统规则（由 env-setup.sh 安装到 ~/.claude/）
- `harmonyos-dev-env/config/` - 配置模板和脚本
- `harmonyos-dev-env/scripts/` - 工具脚本（签名、验证、环境设置）

### 5. 内容指南
- 包含完整构建步骤，不只是摘要
- 记录所有 HarmonyOS 特定适配
- 提供已知问题的故障排除章节
- 交叉引用相关文档

### 5. Git 提交
- 重要更改时维护双语提交信息
- 同时更新两个语言版本
- 引用 Co-Authored-By 行

## HarmonyOS 关键适配点

记录工具适配时，必须覆盖：

1. **代码签名**: 所有 ELF 二进制必须签名
2. **PyTorch 版本说明**: 标注为 v2.5.1（git tag），内部版本字符串为 2.5.0a0+gita8d6fb（pre-release 标记），两者指向同一代码
2. **/tmp 只读**: 使用 $HOME/Claude/tmpdir
3. **LD_LIBRARY_PATH**: /usr/lib 必须在最前面
4. **链接器封装**: SDK 的 lld 不工作，使用 ld.bfd 封装
5. **无 gcc**: 只有 clang 可用
6. **SSH V8 崩溃**: 使用 --jitless + node-fetch polyfill
7. **SSH `-e` 参数**: Dropbear 必须使用 `-e` 参数启动，以传递环境变量（LD_LIBRARY_PATH、PATH）给子会话
8. **make -j 失败**: mkfifo 返回"Operation not permitted"——使用 Ninja 进行并行构建
9. **不要使用 CMAKE_TOOLCHAIN_FILE**: 不要将 CMAKE_TOOLCHAIN_FILE 配合 CMAKE_SYSTEM_NAME=Linux 使用——它会触发交叉编译模式导致 try_run() 失败；使用轻量级工具链文件（仅编译器+链接器封装，无 CMAKE_SYSTEM_NAME）或直接传递编译器标志
10. **OpenBLAS/LAPACK**: 编译 OpenBLAS v0.3.28（NOFORTRAN=1，f2c LAPACK）；修改 Makefile.prebuild 添加 -B 封装+代码签名；从 .a 创建 .so；在 CMake 中显式设置 LAPACK_LIBRARIES 和 LAPACK_FOUND
11. **Sleef NATIVE_BUILD_DIR 修复**: 修改 sleef CMakeLists.txt 的 add_host_executable，在 NATIVE_BUILD_DIR 提供时使用，即使无 CMAKE_CROSSCOMPILING——避免循环签名依赖
12. **NumPy 增量补丁**: 如果 CMake 未找到 NumPy，重新编译 tensor_numpy.cpp（添加 -DUSE_NUMPY）并重新链接 libtorch_python.so——无需完整重构
13. **CMake 4.1.2 ldd**: CMake 4.1.2 链接后运行 ldd；将 ldd 封装复制到 ~/.local/bin/ldd
14. **PyTorch visibility hidden + supplement.so**: PyTorch 使用 `-fvisibility=hidden` 编译，导致 `RefcountedMapAllocator::decref/incref` 和 `at::internal::invoke_parallel` 从 libtorch_cpu.so 动态符号表中被隐藏。创建 `libtorch_supplement.so` 提供 stub 实现，通过 `patchelf --add-needed` 添加为 NEEDED 依赖
15. **NEEDED 路径前缀修复**: Ninja 构建的库在 NEEDED 条目中使用 "lib/" 前缀（如 `lib/libtorch_cpu.so`）。使用 `patchelf --replace-needed` 去除前缀，并 `--set-rpath` 设置 `$ORIGIN:$HOME/.local/lib`
16. **OpenSSH passwd_compat LD_PRELOAD**: sshd 需要 passwd_compat LD_PRELOAD，因为 uid 20020106 不在 /etc/passwd（只读）。子进程环境必须保留 LD_PRELOAD/LD_LIBRARY_PATH（patch session.c do_setup_env）。sshd_config 必须使用 SetEnv PATH 将 openssh-prefix/bin 放在首位（系统 /usr/bin/scp 会崩溃）。
17. **OpenSSH 抽象socket**: ssh-agent bind() 对文件系统 Unix socket 返回 EPERM；回退到抽象命名空间（sun_path[0]='\0'）。SSH_AUTH_SOCK 使用 "abstract:" 前缀。
18. **OpenSSH privsep 非致命**: HarmonyOS 不允许用户空间进程调用 chroot/setgroups/setegid/seteuid。Patch sshd-session.c 使 chroot 非致命（跳过后续权限降级）。uidswap.c：将 setgroups/setegid/seteuid 从 fatal 改为 debug。
19. **OpenSSH authorized_keys UID**: 文件所有者为 uid 20001006（file_manager），sshd 运行在 uid 20020106。将 uid 20001006 加入 platform_sys_dir_uid()（类似 root）。safe_path() 对系统目录拥有的文件跳过 mode 检查（022 位掩码）。StrictModes=yes 正常工作。

## 相关文档

- Skill 定义: `harmonyos-dev-env/SKILL.md`
- 一键环境设置: `harmonyos-dev-env/scripts/env-setup.sh`
- 目标系统规则: `harmonyos-dev-env/rules/CLAUDE.cn.md`
- 代码签名指南: `harmonyos-dev-env/docs/code-signing.cn.md`
- LD_LIBRARY_PATH: `harmonyos-dev-env/docs/ld-library-path.cn.md`
- OpenSSH 适配指南: `harmonyos-dev-env/docs/openssh-harmonyos.cn.md`