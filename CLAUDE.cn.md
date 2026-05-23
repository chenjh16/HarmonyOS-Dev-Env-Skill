# HarmonyOS-Dev-Env-Skill 项目 - 开发指南

## 项目概述

本项目是 HarmonyOS PC 开发环境的技能包，提供各种工具（Python、Rust、Go、PyTorch、llama.cpp 等）的完整构建和安装指南。

**目标平台**: HarmonyOS (鸿蒙内核 1.12.0, aarch64)

## 项目结构

```
HarmonyOS-Dev-Env-Skill/
├── CLAUDE.md              # 本文件 - Agent 开发指南（英文）
├── CLAUDE.cn.md           # Agent 开发指南（中文）
├── README.md              # 项目 README（双语合一）
├── skill.json             # Skill 定义，包含工具元数据
├── rules/                 # 目标系统规则（安装到 ~/.claude/）
│   ├── CLAUDE.md          # HarmonyOS 规则（英文）
│   └── CLAUDE.cn.md       # HarmonyOS 规则（中文）
├── docs/                  # 适配指南（双语 *.md + *.cn.md）
│   ├── python-harmonyos.md
│   ├── python-harmonyos.cn.md
│   └── ...
├── tools/                 # 工具构建指南（双语）
│   ├── python/
│   │   ├── build.md
│   │   ├── build.cn.md
│   │   └── install.sh
│   └── ...
├── config/                # 配置模板
│   ├── .zshenv
│   ├── .claude/
│   │   ├── ssh-fetch-polyfill.js
│   │   └── start-claude.sh
│   └── ...
└── scripts/               # 工具脚本
    └── sign-all.sh
```

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

### 3. 文件组织
- `docs/` - 通用适配指南（平台级别问题）
- `tools/` - 工具特定构建指南
- `rules/` - 目标系统规则（安装到用户系统）
- `config/` - 配置模板和脚本

### 4. 内容指南
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

## 相关文档

- 目标系统规则: `rules/CLAUDE.md`
- 代码签名指南: `docs/code-signing.md`
- LD_LIBRARY_PATH: `docs/ld-library-path.md`