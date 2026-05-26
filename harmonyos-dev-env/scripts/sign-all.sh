#!/bin/sh
# sign-all.sh - Batch signing script for HarmonyOS ELF binaries
# Usage: ./sign-all.sh <directory>
#
# HarmonyOS requires all ELF binaries (executables and .so files) to be signed
# before execution. This script signs all ELF files in a given directory.

set -e

SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
OBJCOPY="/data/service/hnp/bin/llvm-objcopy"

if [ -z "$1" ]; then
    echo "Usage: $0 <directory>"
    echo "Example: $0 ~/.rust/lib"
    exit 1
fi

TARGET_DIR="$1"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist"
    exit 1
fi

echo "Signing all ELF binaries in $TARGET_DIR..."

# Find all files and check if they are ELF. Use a list file so paths with spaces are preserved.
COUNT=0
FAILED=0
LIST_FILE="${TMPDIR:-$HOME/Claude/tmpdir}/sign-all-files.$$"
mkdir -p "$(dirname "$LIST_FILE")"
find "$TARGET_DIR" -type f 2>/dev/null > "$LIST_FILE"
while IFS= read -r FILE; do
    # Skip source files and known non-ELF files
    case "$FILE" in
        *.c|*.cpp|*.h|*.py|*.txt|*.md|*.json|*.toml|*.yaml|*.yml|*.sh|*.tar|*.gz|*.xz) continue ;;
    esac

    # Check if file is ELF
    if ! file "$FILE" 2>/dev/null | grep -q "ELF"; then
        continue
    fi

    COUNT=$((COUNT + 1))
    echo "[$COUNT] Signing: $FILE"

    # Create temp file for signed output
    SIGNED_FILE="${FILE}.signed"
    UNSIGNED_FILE="${FILE}.unsigned"

    # Remove existing signature section (if present)
    $OBJCOPY --remove-section=.codesign "$FILE" "$UNSIGNED_FILE" 2>/dev/null || cp "$FILE" "$UNSIGNED_FILE"

    # Sign the file
    if $SIGN_TOOL sign -selfSign 1 \
        -inFile "$UNSIGNED_FILE" \
        -outFile "$SIGNED_FILE" \
        -signAlg SHA256withECDSA 2>/dev/null; then
        # Replace original with signed version
        mv "$SIGNED_FILE" "$FILE"
        rm -f "$UNSIGNED_FILE"
        # Ensure executable permission
        chmod +x "$FILE"
    else
        echo "  WARNING: Failed to sign $FILE"
        rm -f "$UNSIGNED_FILE" "$SIGNED_FILE"
        FAILED=$((FAILED + 1))
    fi
done < "$LIST_FILE"
rm -f "$LIST_FILE"

if [ "$COUNT" -eq 0 ]; then
    echo "No ELF files found in $TARGET_DIR"
fi

echo ""
echo "Done! Signed $COUNT ELF files, $FAILED failed"