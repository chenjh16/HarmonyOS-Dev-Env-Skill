# Rust/PyO3 Build Script Signing — rustc Auto-Sign Wrapper

On HarmonyOS, all ELF executables must be code-signed before execution. Cargo build scripts are ELF executables compiled by rustc. This creates a signing loop: when you sign a build script, cargo detects the file changed and rebuilds it, producing a new unsigned build script — infinite loop.

## Failed Approaches

- **Background monitor polling**: too slow — a 0.2s polling interval can't catch build scripts that cargo executes within milliseconds
- **CC/clang wrapper**: build scripts are Rust code compiled by rustc, not C code — a CC wrapper doesn't intercept them
- **PATH-based rustc wrapper**: cargo calls rustc from its own toolchain path, not PATH — PATH wrapper is ignored

## Working Solution: rustc Auto-Sign Wrapper

Replace the real rustc binary at `$HOME/.rust/bin/rustc` with a wrapper script that intercepts every rustc invocation, calls the real rustc (moved to `rustc.real`), and auto-signs any ELF binary outputs before cargo tries to execute them.

### Setup

```bash
# Step 1: Move real rustc to rustc.real
mv $HOME/.rust/bin/rustc $HOME/.rust/bin/rustc.real

# Step 2: Create wrapper script at $HOME/.rust/bin/rustc
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

# Also handle -o specified files (for .so output)
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

# Step 3: Build your Rust/PyO3 package (build scripts are now auto-signed)
# ... normal maturin build ...

# Step 4: IMPORTANT — Restore original rustc after build
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

### Key Points

- The wrapper handles two output types: `--out-dir` + `--crate-type bin` (build scripts) and `-o` (direct output like cdylib .so files)
- `chmod +x` is critical — cargo creates build scripts without execute permission; the wrapper must add it
- The wrapper only signs if no `.codesign` section exists (avoids re-signing already-signed files)
- **Must restore original rustc after build** — leaving the wrapper permanently could cause unexpected behavior
- This technique works for ALL Rust/PyO3 packages with build scripts

## Packages Using This Technique

| Package | Additional Steps | e2e Tests |
|---------|-----------------|-----------|
| orjson | Pre-compile yyjson.c → libyyjson.a; remove `cc` from Cargo.toml build-dependencies | 8/8 |
| tokenizers | Enable `fancy-regex` feature: `maturin build --features fancy-regex`; abi3 wheel | 10/10 |
| safetensors | Simple maturin build; abi3 wheel | Works |
| Any Rust/PyO3 with build scripts | Just use wrapper + maturin build | Varies |

## orjson Detailed Build Process

orjson uses the `cc` crate to compile yyjson.c via a build script, adding another build script to the signing loop. Reduce complexity by pre-compiling:

```bash
# Step 1: Install the rustc auto-sign wrapper (see Setup above)

# Step 2: Pre-compile yyjson.c into a static library
cd <orjson_source_dir>/src/yyjson/
/data/service/hnp/bin/clang -c yyjson.c -o yyjson.o -O3 -fPIC
/data/service/hnp/bin/ar rcs libyyjson.a yyjson.o

# Step 3: Modify Cargo.toml — remove cc from build-dependencies
# In src/yyjson/Cargo.toml, create a no-build-script crate that links libyyjson.a

# Step 4: Build with maturin
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3

# Step 5: Extract wheel, sign .so, rename suffix, install manually

# Step 6: Restore original rustc
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

## tokenizers Detailed Build Process

tokenizers requires one of `onig` or `fancy-regex` features. onig (C oniguruma library) doesn't compile on HarmonyOS. Use `fancy-regex` (pure Rust regex):

```bash
# Step 1: Install the rustc auto-sign wrapper

# Step 2: Download tokenizers source
wget https://files.pythonhosted.org/packages/source/t/tokenizers/tokenizers-0.23.1.tar.gz
tar xf tokenizers-0.23.1.tar.gz
cd tokenizers-0.23.1

# Step 3: Enable fancy-regex in Cargo.toml
# Change: default = ["progressbar"]
# To:     default = ["progressbar", "fancy-regex"]

# Step 4: Build with maturin
RUSTFLAGS="-C linker=/data/service/hnp/bin/clang" \
  maturin build --release --interpreter $HOME/.local/bin/python3 --features fancy-regex

# Step 5: Extract wheel, sign .so, install manually
# Note: abi3 wheel — .abi3.so suffix is compatible, no rename needed

# Step 6: Restore original rustc
mv $HOME/.rust/bin/rustc.real $HOME/.rust/bin/rustc
```

**e2e tests (10/10)**: encode, decode, batch_encode, batch_decode, from_pretrained, save, truncation, padding, special tokens, word_piece.