# HarmonyOS 代码签名指南

## 概述

HarmonyOS 要求所有 ELF 二进制文件（可执行文件和共享库）在执行前必须签名。这是 HarmonyOS 独有的安全机制，而非权限问题。

未签名的二进制文件将失败并显示：
```
zsh: permission denied: ./binary
```
退出码：126

## 签名工具

### ELF 二进制签名：`binary-sign-tool`

位置：`/data/service/hnp/bin/binary-sign-tool`

命令：
- `sign` — 对 ELF 二进制文件签名
- `display-sign` — 显示签名信息

支持的算法：
- `SHA256withECDSA`
- `SHA384withECDSA`

### HAP/应用签名：`hap-sign-tool`

位置：`/data/service/hnp/bin/hap-sign-tool`

命令：
- `generate-keypair` — 生成密钥对
- `generate-csr` — 生成证书签名请求
- `generate-cert` — 生成证书
- `generate-ca` — 生成 CA 证书
- `generate-app-cert` — 生成应用证书
- `generate-profile-cert` — 生成配置文件证书
- `sign-profile` — 签名配置文件
- `verify-profile` — 验证配置文件签名
- `sign-app` — 签名 HAP/app 包
- `verify-app` — 验证应用签名

密钥算法：ECC（NIST-P-256 / NIST-P-384）

## 签名方法

### 自签名（本地测试）

用于本地测试和开发，使用自签名：

```bash
/data/service/hnp/bin/binary-sign-tool sign \
  -selfSign 1 \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -signAlg SHA256withECDSA
```

### 生产环境签名（需要证书）

用于生产环境部署，使用正式证书：

```bash
/data/service/hnp/bin/binary-sign-tool sign \
  -keyAlias "your-key-alias" \
  -appCertFile cert.cer \
  -profileFile profile.p7b \
  -inFile <unsigned-binary> \
  -outFile <signed-binary> \
  -keystoreFile keystore.p12 \
  -signAlg SHA256withECDSA
```

必需参数：
- `-keyAlias`：密钥库中的密钥别名
- `-appCertFile`：应用证书文件
- `-profileFile`：配置文件（p7b 格式）
- `-inFile`：输入的未签名二进制文件
- `-outFile`：输出的已签名二进制文件
- `-keystoreFile`：密钥库文件（p12 格式）
- `-signAlg`：签名算法

## 需要签名的文件

### 可执行文件

所有编译后的可执行文件必须签名：
- Python 解释器（`python3`）
- Rust 编译器输出（`rustc` 编译的程序）
- Go 编译的程序
- llama.cpp 二进制文件（`llama-cli`、`llama-server`）
- mihomo 代理二进制文件
- Dropbear SSH 二进制文件
- 任何其他 ELF 可执行文件

### 共享库（.so 文件）

所有将被动态加载的共享库必须签名：
- Python 扩展模块（`.cpython-312-aarch64-linux-gnu.so`）
- Rust 动态库（`*.so`）
- 应用程序的本地库

### 不需要签名的文件

- Shell 脚本（`.sh`）
- Python 脚本（`.py`）
- 文本文件
- 配置文件
- 数据文件
- 静态库（`.a` 文件 — 仅链接，不加载）

## 批量签名脚本

使用 `scripts/sign-all.sh` 对目录中的所有二进制文件进行签名：

```bash
#!/bin/sh
# 批量签名目录中的所有 ELF 二进制文件

DIR="${1:-.}"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

for f in "$DIR"/*; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        echo "正在签名: $f"
        # 移除现有签名节
        /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned" 2>/dev/null || cp "$f" "${f}.unsigned"
        
        # 签名二进制文件
        "$SIGN_TOOL" sign -selfSign 1 \
            -inFile "${f}.unsigned" \
            -outFile "${f}.signed" \
            -signAlg SHA256withECDSA
        
        # 替换原文件
        mv "${f}.signed" "$f"
        rm -f "${f}.unsigned"
        chmod +x "$f"
    fi
done

echo "已完成 $DIR 中所有二进制文件的签名"
```

## 验证签名

检查二进制文件是否已签名：

```bash
/data/service/hnp/bin/binary-sign-tool display-sign -inFile <binary>
```

如果已签名，将显示签名详情。如果未签名，将报告错误。

## 常见问题

### 签名后仍显示"permission denied"

1. 检查签名是否成功（使用 display-sign）
2. 确保有执行权限：`chmod +x <binary>`
3. 验证文件所有权是否正确

### 签名已存在

重新签名前移除旧签名：

```bash
/data/service/hnp/bin/llvm-objcopy --remove-section=.codesign <binary> <binary>.unsigned
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile <binary>.unsigned -outFile <binary>.signed
mv <binary>.signed <binary>
```

### 签名失败并报错

1. 检查二进制是否为有效 ELF：`file <binary>`
2. 确保二进制文件未损坏
3. 验证签名工具权限正确

## 与构建流程集成

### Python 扩展构建

在安装 C 扩展的 pip install 之后：

```bash
cd ~/.local/lib/python3.12/site-packages/<package>
for f in *.cpython-312-aarch64-linux-gnu.so; do
    /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned"
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "${f}.unsigned" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
done
```

### Rust Cargo 构建

在 `cargo build` 之后：

```bash
for f in target/debug/* target/release/*.so; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.s"
        mv "${f}.s" "$f"
    fi
done
```

### C/C++ 构建

在 `make` 或 `cmake` 之后：

```bash
for f in <output-dir>/*; do
    if [ -f "$f" ] && file "$f" | grep -q "ELF"; then
        /data/service/hnp/bin/llvm-objcopy --remove-section=.codesign "$f" "${f}.unsigned"
        /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "${f}.unsigned" -outFile "$f"
        rm "${f}.unsigned"
    fi
done
```

## 安全考虑

自签名二进制文件（`-selfSign 1`）适用于：
- 本地开发和测试
- 个人项目
- 内部工具

对于生产环境或分布式应用：
- 使用来自授权 CA 的正式证书
- 遵循 HarmonyOS 应用签名指南
- 安全存储密钥库