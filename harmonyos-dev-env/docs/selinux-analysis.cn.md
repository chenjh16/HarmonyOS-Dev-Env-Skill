# HarmonyOS 编译 .so 加载问题 - 深度分析

> **英文版本**: selinux-analysis.md

## 问题摘要

**现象**: 编译的 Python 扩展模块 (.so 文件) 无法从用户路径加载，返回 "Permission denied" 错误。

**影响范围**: 原影响 numpy、pandas、pillow 及所有通过 pip 安装的包含编译扩展的包。



## 根因分析

### 1. SELinux 路径策略

**关键发现**: 问题**不是**代码签名，而是 **SELinux 路径安全策略**。

| 路径 | 文件系统 | SELinux 标签 | .so 加载 |
|------|----------|--------------|----------|
| `/data/service/hnp/` | hmfs | `u:object_r:hnp_file:s0` | ✓ 成功 |
| `/system/lib64/` | system | 系统标签 | ✓ 成功 |
| `$HOME`（示例：`/storage/Users/<user>/`） | hmdfs | `u:object_r:hmdfs:s0` | ✗ 拒绝 |
| `/data/storage/el2/base/haps/` | hmfs | `u:object_r:hishell_hap_data_file:s0` | ✗ 拒绝 |
| `/data/local/tmp/` | hmfs | `u:object_r:data_local_tmp:s0` | ✗ 拒绝 (无写权限) |

**证明**: 同一个系统 .so 文件 (`_bisect.cpython-312.so`) 从 `/data/service/hnp/` 加载成功，但复制到用户路径后加载失败。

### 2. 安全上下文

进程上下文: `u:r:hishell_hap:s0`

SELinux 状态:
- Enforce 模式: 0 (宽容模式? 不，仍然阻止)
- deny_unknown: 1 (拒绝未知权限)
- Seccomp: 2 (严格模式启用)

### 3. 能做什么 vs 不能做什么

**可以**:
- mmap PROT_EXEC ✓
- 读取 .so 文件 ✓
- 文件读/写/执行权限 ✓
- 系统 Python 扩展 ✓
- 纯 Python 包 ✓
- **从 `$HOME/.local/lib/` 加载的签名 .so 扩展模块** ✓（通过代码签名 + `-rdynamic` Python 解决）


**历史问题（已解决）**:
以下项目之前不工作，但已通过 `-rdynamic` Python + 代码签名**解决**:

| 历史问题 | 解决方案 | 日期 |
|---------|---------|------|
| 从用户路径 dlopen() | 配合签名 .so + `-rdynamic` Python 可正常工作 | 2026-05-22 |
| 即使文件权限正确也无法加载 .so | 代码签名后可正常工作 | 2026-05-22 |
| 代码签名无效（原始评估）| 代码签名是必需的；配合 `-rdynamic` 可解决此问题 | 2026-05-22 |

**仍不工作**:
- 修改 SELinux 标签 (setfattr 失败) ✗
- 从非用户安装路径加载 .so（如 `$HOME/` 下未正确安装的随机子目录） ✗

### 4. 技术细节

```
# 对比
系统 .so:
  路径: /data/service/hnp/python.org/python_3.12/lib/python3.12/lib-dynload/_ssl.cpython-312.so
  SELinux: u:object_r:hnp_file:s0
  代码签名: 未找到
  加载: 成功

用户 .so:
  路径: $HOME/Claude/venv/lib/python3.12/site-packages/numpy/_core/_multiarray_umath.cpython-312.so
  SELinux: u:object_r:hmdfs:s0
  代码签名: 自签名 (手动添加)
  加载: 权限拒绝
```

## 为什么我们的 Python 构建可以工作

我们本地编译的 Python (见 [python-harmonyos.cn.md](python-harmonyos.cn.md)) 使用 `-rdynamic` 导出 948+ Py 符号（1521 总导出），允许使用 `-DPy_BUILD_CORE_MODULE` 编译的扩展模块在不需要 `libpython.so` 的情况下解析符号。



## 可能的解决方案

### 方案 1: 安装到系统路径 (需要 Root)

如果能写入 `/data/service/hnp/python.org/python_3.12/lib/python3.12/site-packages/`，编译扩展就能工作。

**问题**: 无系统路径写权限。

### 方案 2: 修改 SELinux 策略 (需要 Root)

创建自定义 SELinux 策略模块，允许 `hishell_hap` 域从用户路径执行文件。

```c
// 示例策略 (需要编译和加载)
allow hishell_hap hishell_hap_data_file:file { execute execmod map };
allow hishell_hap hmdfs:file { execute execmod map };
```

**问题**: 需要 Root 权限和 SELinux 策略编译工具 (不可用)。

### 方案 3: HAP 打包

将 Python + 扩展打包为正式的 HarmonyOS HAP (HarmonyOS Ability Package)。正确签名的 HAP 会有合适的权限。

**优点**:
- HarmonyOS 应用分发官方方式
- 正确的代码签名和权限
- 可能启用编译扩展加载

**缺点**:
- 构建过程复杂
- 需要 DevEco Studio
- 需打包整个 Python + 包
- 不适合 CLI 开发

### 方案 4: 纯 Python 替代方案

> **更新**: 此方案已不再必要。以下列出的包现在均可通过 `-rdynamic` Python 构建配合代码签名正常使用。

以下包现在均支持从用户路径加载编译扩展:

| 包 | 状态 | 备注 |
|----|------|------|
| numpy | ✓ 正常 | 使用 clang 编译，.so 已签名 |
| pandas | ✓ 正常 | 纯 Python（基本功能无需 .so） |
| pillow | ✓ 正常 | 使用 clang 编译，.so 已签名 |
| lxml | ✓ 正常 | 使用 clang 编译，.so 已签名 |
| matplotlib | 未测试 | 大部分为纯 Python |
| scipy | 未测试 | 需编译 LAPACK 依赖 |

### 方案 5: 远程 Python 服务器

在有编译扩展的服务器上运行 Python，通过 HTTP/WebSocket 通信。

**优点**:
- 服务器上有完整 Python 功能
- 本地机器处理 UI/接口

**缺点**:
- 需要网络连接
- 不适合离线工作

## 结论



**原始分析 (2026-05-12)**: 从用户路径加载编译 .so 文件被 HarmonyOS SELinux 策略阻止，具体是:
1. 路径标签分配 (hmdfs vs hnp_file)
2. 域限制 (hishell_hap 不能从用户路径执行)
3. 这是平台级安全决策，不是 bug

**已解决方案**: `-rdynamic` Python 构建导出 948+ Py 符号（1521 总导出），使扩展模块无需 `libpython.so` 即可解析符号。配合对所有 .so 文件的代码签名，编译扩展现在可以从用户路径 (`$HOME/.local/lib/python3.12/site-packages/`) 正常加载。此方案有效绕过了 Python 用例的 SELinux 限制。



## 测试命令

```bash
# 检查 SELinux 上下文
cat /proc/self/attr/current

# 检查文件标签
getfattr -d <file> | grep selinux

# 检查已加载库
cat /proc/self/maps | grep ".so"

# 对比系统 vs 用户 .so 加载
python3 -c "import ctypes; ctypes.CDLL('/data/service/hnp/...')"  # 成功
python3 -c "import ctypes; ctypes.CDLL('/storage/Users/...')"     # 失败
```

---

*分析日期: 2026-05-12*
*平台: HarmonyOS HongMeng Kernel 1.12.0*