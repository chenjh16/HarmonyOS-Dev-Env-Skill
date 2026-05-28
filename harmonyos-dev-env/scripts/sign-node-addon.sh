#!/bin/sh
# sign-node-addon.sh - Sign and patch Node.js native addon (.node) files for HarmonyOS
# Usage: sign-node-addon.sh <path-to-.node-file>
#
# On HarmonyOS, Node.js native addons (.node ELF shared objects) need two modifications:
# 1. Add libc++_shared.so to NEEDED list (C++ addons need C++ runtime symbols that Node doesn't export)
# 2. Add .codesign section (required by HarmonyOS kernel for dlopen from user-space directories)
#
# The signing must happen AFTER patchelf modification because patchelf cannot modify signed files.

set -e

ADDON_FILE="$1"

if [ -z "$ADDON_FILE" ]; then
  echo "Usage: sign-node-addon.sh <path-to-.node-file>"
  exit 1
fi

if [ ! -f "$ADDON_FILE" ]; then
  echo "Error: File not found: $ADDON_FILE"
  exit 1
fi

# Determine paths based on SCRIPT_DIR pattern
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR="${HOME}/Claude/tmpdir"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
OBJCOPY="/data/service/hnp/bin/llvm-objcopy"
PATCHELF="/data/service/hnp/bin/patchelf"

BASENAME=$(basename "$ADDON_FILE")
UNSIGNED="${TMPDIR}/${BASENAME}.unsigned"
SIGNED="${TMPDIR}/${BASENAME}.signed"

# Step 1: Copy to temp and remove .codesign section (if present)
cp "$ADDON_FILE" "$UNSIGNED"
$OBJCOPY --remove-section=.codesign "$UNSIGNED" 2>/dev/null || true

# Step 2: Add libc++_shared.so dependency (needed for C++ addons on HarmonyOS)
$PATCHELF --add-needed libc++_shared.so "$UNSIGNED"

# Step 3: Sign with self-sign
$SIGN_TOOL sign -selfSign 1 -inFile "$UNSIGNED" -outFile "$SIGNED"

# Step 4: Replace original file with signed version
rm -f "$ADDON_FILE"
cp "$SIGNED" "$ADDON_FILE"
chmod 775 "$ADDON_FILE"

# Cleanup temp files
rm -f "$UNSIGNED" "$SIGNED"

echo "Signed: $ADDON_FILE"