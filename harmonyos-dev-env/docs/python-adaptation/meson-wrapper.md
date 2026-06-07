# Meson Auto-Sign Clang Wrapper

Meson builds need to execute sanity check binaries during configuration. On HarmonyOS, unsigned binaries can't execute. The auto-sign clang wrapper signs all ELF outputs (including PIE executables) immediately after compilation.

## Setup

```bash
# Create auto-sign clang wrapper at $HOME/Claude/lib/meson_wrapper/clang
cat > $HOME/Claude/lib/meson_wrapper/clang << 'EOF'
#!/bin/sh
REAL_CC=/data/service/hnp/bin/clang
SIGN_TOOL=/data/service/hnp/bin/binary-sign-tool
READELF=/data/service/hnp/bin/llvm-readelf
TMPDIR="$HOME/Claude/tmpdir"

# Parse -o argument from command line
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
        # Check if it's a .o, .so, or .a — skip those
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

## Create meson native.ini

```ini
[binaries]
c = '$HOME/Claude/lib/meson_wrapper/clang'
cpp = '$HOME/Claude/lib/meson_wrapper/clang++'

[built-in options]
c_args = ['-B$HOME/Claude/lib/linker_wrapper']
cpp_args = ['-B$HOME/Claude/lib/linker_wrapper']
```

Note: Also create a similar `clang++` wrapper for C++ builds.

## Build with mesonpy Python API

```bash
# For pandas
python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/pandas_src')"

# For matplotlib (needs additional PKG_CONFIG_PATH)
export PKG_CONFIG_PATH=$HOME/.local/lib/python3.12/site-packages/pybind11/share/pkgconfig:$PKG_CONFIG_PATH
python3 -c "import mesonpy; mesonpy.build_wheel('$HOME/Claude/tmpdir/matplotlib_src')"
```

## Post-Build Steps

```bash
# Sign all .so in resulting wheel
find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "${f}.signed"
    mv "${f}.signed" "$f"
  done
' sh {} +

# For C++ extensions (matplotlib): add libc++_shared.so
find "$WHEEL_DIR" -name "*.so" -type f -exec sh -c '
  for f do
    /data/service/hnp/bin/patchelf --add-needed libc++_shared.so "$f"
  done
' sh {} +

# Rename .so suffix
cd "$WHEEL_DIR"
for f in *.cpython-312.so; do
  mv "$f" "${f%.cpython-312.so}.cpython-312-aarch64-linux-gnu.so"
done

# Install manually to site-packages
cp -r <pkg_dir>/ $HOME/.local/lib/python3.12/site-packages/
cp -r <pkg_dir>-*.dist-info/ $HOME/.local/lib/python3.12/site-packages/
```

## Key Insight

The wrapper must sign ALL ELF outputs (including PIE/DYN type), not just EXEC type. Meson's sanity_check is a PIE executable — it has `Type: DYN` in the ELF header. If the wrapper only checks for `EXEC`, the sanity check binary won't be signed and will fail to execute.

## Packages Using This Technique

| Package | .so Count | Additional Steps | e2e Tests |
|---------|-----------|-----------------|-----------|
| pandas | 45 | Sign + rename all .so | DataFrame, Series, groupby, date_range |
| matplotlib | 8 | Sign + patchelf libc++_shared.so + rename | line plot, histogram, scatter, bar, subplots, contour |