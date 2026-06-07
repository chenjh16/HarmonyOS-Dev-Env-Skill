# Meson 自动签名 Clang 包装器

Meson 构建需要在配置阶段执行健全性检查二进制文件。在 HarmonyOS 上，未签名的二进制文件无法执行。自动签名 clang 包装器在编译后立即签名所有 ELF 输出（包括 PIE 可执行文件）。

## 设置

```bash
# 在 $HOME/Claude/lib/meson_wrapper/clang 创建自动签名 clang 包装器
cat > $HOME/Claude/lib/meson_wrapper/clang << 'EOF'
#!/bin/sh
REAL_CC=/data/service/hnp/bin/clang
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool
READELF=/data/service/hnp/bin/llvm-readelf
TMPDIR="$HOME/Claude/tmpdir"

# 从命令行解析 -o 参数
OUTPUT_FILE=""
PREV=""
for arg in "$@"; do
    if [ "$PREV" = "-o" ]; then
        OUTPUT_FILE="$arg"
    fi
    PREV="$arg"
done

$REAL_CC "$@"
RESULT=$?

if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
    TYPE=$("$READELF" -h "$OUTPUT_FILE" 2>/dev/null | grep "Type:" | head -1)
    if echo "$TYPE" | grep -qE "EXEC|DYN"; then
        # 检查是否为 .o, .so 或 .a — 跳过这些
        case "$OUTPUT_FILE" in
            *.o|*.so|*.a) ;;
            *)
                HAS_SIGN=$("$READELF" -S "$OUTPUT_FILE" 2>/dev/null | grep ".codesign")
                if [ -z "$HAS_SIGN" ]; then
                    "$SIGN_TOOL" sign -selfSign 1 -inFile "$OUTPUT_FILE" -outFile "${OUTPUT_FILE}.signed" -signAlg SHA256withECDSA >/dev/null 2>&1
                    if [ -f "${OUTPUT_FILE}.signed" ]; then
                        mv "${OUTPUT_FILE}.signed" "$OUTPUT_FILE"
                    fi
                fi
                chmod +x "$OUTPUT_FILE"
                ;;
        esac
    fi
fi

exit $RESULT
EOF
chmod +x $HOME/Claude/lib/meson_wrapper/clang
```

## 创建 meson native.ini

```ini
[binaries]
c = '$HOME/Claude/lib/meson_wrapper/clang'
cpp = '$HOME/Claude/lib/meson_wrapper/clang++'

[built-in options]
c_args = ['-B$HOME/Claude/lib/linker_wrapper']
cpp_args = ['-B$HOME/Claude/lib/linker_wrapper']
```

注意：还需要为 C++ 构建创建类似的 `clang++` 包装器。

## 使用 mesonpy Python API 构建

```bash
# 构建 pandas
python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/pandas_src')"

# 构建 matplotlib（需要额外的 PKG_CONFIG_PATH）
export PKG_CONFIG_PATH=$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig:$PKG_CONFIG_PATH
python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/matplotlib_src')"
```

## 构建后步骤

```bash
# 签名 wheel 中所有 .so
find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +

# 对于 C++ 扩展 (matplotlib)：添加 libc++_shared.so
find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
  done
' sh {} +

# 重命名 .so 后缀
cd "$WHEEL_DIR"
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done

# 手动安装到 site-packages
cp -r <pkg_dir>/ $HOME/.local/lib/python3.12/site-packages/
cp -r <pkg_dir>-*.dist-info/ $HOME/.local/lib/python3.12/site-packages/
```

## 关键洞察

包装器必须签名所有 ELF 输出（包括 PIE/DYN 类型），而不仅仅是 EXEC 类型。Meson 的 sanity_check 是一个 PIE 可执行文件 —— 它在 ELF 头中具有 `Type: DYN`。如果包装器只检查 `EXEC`，健全性检查二进制文件将不会被签名，从而无法执行。

## 使用此技术的包

| 包名 | .so 数量 | 额外步骤 | e2e 测试 |
|------|----------|----------|----------|
| pandas | 45 | 签名 + 重命名所有 .so | DataFrame, Series, groupby, date_range |
| matplotlib | 8 | 签名 + patchelf libc++_shared.so + 重命名 | 折线图、直方图、散点图、柱状图、子图、等高线图 |