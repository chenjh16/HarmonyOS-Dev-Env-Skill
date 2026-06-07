# Rust/PyO3 构建脚本签名 — rustc 自动签名包装器

在 HarmonyOS 上，所有 ELF 可执行文件必须在执行前进行代码签名。Cargo 构建脚本是由 rustc 编译的 ELF 可执行文件。这会产生签名循环：当你签名一个构建脚本后，cargo 检测到文件已更改并重新构建它，生成新的未签名构建脚本 —— 无限循环。

## 失败的方案

- **后台监控轮询**：太慢 —— 0.2 秒的轮询间隔无法捕获 cargo 在毫秒级内执行的构建脚本
- **CC/clang 包装器**：构建脚本是 Rust 代码，由 rustc 编译，不是 C 代码 —— CC 包装器无法拦截
- **PATH-based rustc 包装器**：cargo 从自己的工具链路径调用 rustc，而非 PATH —— PATH 包装器被忽略

## 可行方案：rustc 自动签名包装器

将 `$HOME/.rust/bin/rustc` 处的真实 rustc 二进制文件替换为包装脚本，拦截每次 rustc 调用，调用真实 rustc（移动到 `rustc.real`），并在 cargo 尝试执行前自动签名所有 ELF 二进制输出。

### 设置

```bash
# 步骤 1：将真实 rustc 移动到 rustc.real
mv $HOME/.rust/bin/rustc $HOME/.rust/bin/rustc.real

# 步骤 2：在 $HOME/.rust/bin/rustc 创建包装脚本
cat > $HOME/.rust/bin/rustc << 'WRAPPER_EOF'
#!/bin/sh
REAL_RUSTC="$HOME/.rust/bin/rustc.real"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
READELF="/data/service/hnp/bin/llvm-readelf"

"$REAL_RUSTC" "$@"
RESULT=$?

OUT_DIR=""
CRATE_TYPE=""
PREV_ARG=""
for arg in "$@"; do
    case "$PREV_ARG" in
        --out-dir) OUT_DIR="$arg" ;;
        --crate-type) CRATE_TYPE="$arg" ;;
    esac
    PREV_ARG="$arg"
done

if [ -n "$OUT_DIR" ] && echo "$CRATE_TYPE" | grep -q "bin"; then
    for f in "${OUT_DIR}/build-script-build" "${OUT_DIR}/build_script_build-"*; do
        if [ -f "$f" ] && [ ! -d "$f" ]; then
            HAS_SIGN=$("$READELF" -S "$f" 2>/dev/null | grep ".codesign")
            if [ -z "$HAS_SIGN" ]; then
                "$SIGN_TOOL" sign -selfSign 1 -inFile "$f" -outFile "${f}.signed" -signAlg SHA256withECDSA >/dev/null 2>&1
                if [ -f "${f}.signed" ]; then
                    mv "${f}.signed" "$f"
                    chmod +x "$f"
                fi
            else
                chmod +x "$f"
            fi
        fi
    done
fi

# 同时处理 -o 指定的文件（用于 .so 输出）
OUTPUT_FILE=""
OPREV=""
for arg in "$@"; do
    if [ "$OPREV" = "-o" ]; then
        OUTPUT_FILE="$arg"
    fi
    OPREV="$arg"
done

if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
    TYPE=$("$READELF" -h "$OUTPUT_FILE" 2>/dev/null | grep "Type:" | head -1)
    if echo "$TYPE" | grep -qE "EXEC|DYN"; then
        HAS_SIGN=$("$READELF" -S "$OUTPUT_FILE" 2>/dev/null | grep ".codesign")
        if [ -z "$HAS_SIGN" ]; then
            "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT_FILE" -outFile "${OUTPUT_FILE}.signed" -signAlg SHA256withECDSA >/dev/null 2>&1
            if [ -f "${OUTPUT_FILE}.signed" ]; then
                mv "${OUTPUT_FILE}.signed" "$OUTPUT_FILE"
            fi
        fi
        chmod +x "$OUTPUT_FILE"
    fi
fi

exit $RESULT
WRAPPER_EOF
chmod +x $HOME/.rust/bin/rustc

# 步骤 3：构建你的 Rust/PyO3 包（构建脚本现在会自动签名）
# ... 正常的 maturin build ...

# 步骤 4：重要 —— 构建后恢复原始 rustc
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

### 关键点

- 包装器处理两种输出类型：`--out-dir` + `--crate-type bin`（构建脚本）和 `-o`（直接输出如 cdylib .so 文件）
- `chmod +x` 至关重要 —— cargo 创建构建脚本时不带执行权限；包装器必须添加它
- 包装器仅在不存在 `.codesign` 段时签名（避免重复签名已签名的文件）
- **构建后必须恢复原始 rustc** —— 永久保留包装器可能导致意外行为
- 此技术适用于所有带构建脚本的 Rust/PyO3 包

## 使用此技术的包

| 包名 | 额外步骤 | e2e 测试 |
|------|----------|----------|
| orjson | 预编译 yyjson.c → libyyjson.a；从 Cargo.toml build-dependencies 移除 `cc` | 8/8 |
| tokenizers | 启用 `fancy-regex` 特性：`maturin build --features fancy-regex`；abi3 wheel | 10/10 |
| safetensors | 简单 maturin build；abi3 wheel | 可用 |
| 任何带构建脚本的 Rust/PyO3 包 | 只需使用包装器 + maturin build | 视情况而定 |

## orjson 详细构建流程

orjson 使用 `cc` crate 通过构建脚本编译 yyjson.c，这会给签名循环增加另一个构建脚本。通过预编译来降低复杂度：

```bash
# 步骤 1：安装 rustc 自动签名包装器（见上方设置）

# 步骤 2：预编译 yyjson.c 为静态库
cd <orjson_source_dir>/src/yyjson/
/data/service/hnp/bin/clang -c yyjson.c -o yyjson.o -O3 -fPIC
/data/service/hnp/bin/ar rcs libyyjson.a yyjson.o

# 步骤 3：修改 Cargo.toml — 从 build-dependencies 移除 cc
# 在 src/yyjson/Cargo.toml 中创建一个无构建脚本的 crate 来链接 libyyjson.a

# 步骤 4：使用 maturin 构建
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# 步骤 5：解压 wheel、签名 .so、重命名后缀、手动安装

# 步骤 6：恢复原始 rustc
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

## tokenizers 详细构建流程

tokenizers 需要 `onig` 或 `fancy-regex` 特性之一。onig（C oniguruma 库）在 HarmonyOS 上无法编译。使用 `fancy-regex`（纯 Rust 正则表达式）：

```bash
# 步骤 1：安装 rustc 自动签名包装器

# 步骤 2：下载 tokenizers 源码
wget https://files.pythonhosted.org/packages/source/t/tokenizers/tokenizers-0.23.1.tar.gz
tar xf tokenizers-0.23.1.tar.gz
cd tokenizers-0.23.1

# 步骤 3：在 Cargo.toml 中启用 fancy-regex
# 修改: default = ["progressbar"]
# 为:   default = ["progressbar", "fancy-regex"]

# 步骤 4：使用 maturin 构建
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3 --features fancy-regex

# 步骤 5：解压 wheel、签名 .so、手动安装
# 注意：abi3 wheel — .abi3.so 后缀兼容，无需重命名

# 步骤 6：恢复原始 rustc
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

**e2e 测试 (10/10)**：encode、decode、batch_encode、batch_decode、from_pretrained、save、truncation、padding、special tokens、word_piece。