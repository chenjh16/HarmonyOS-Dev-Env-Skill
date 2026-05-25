#!/bin/sh
# env-setup.sh - One-time HarmonyOS development environment setup
#
# Creates:
#   - $HOME/Claude/tmpdir (writable temp, /tmp is read-only)
#   - $HOME/Claude/lib/linker_wrapper/ld.lld (ld.bfd wrapper, SDK lld broken)
#   - $HOME/.zshenv (PATH, LD_LIBRARY_PATH, LD_PRELOAD)
#   - $HOME/.claude/ssh-fetch-polyfill.js (SSH V8 crash workaround)
#   - $HOME/.claude/start-claude.sh (Claude Code startup with SSH detection)
#
# Usage: sh ~/.claude/skills/harmonyos-dev-env/scripts/env-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== HarmonyOS Development Environment Setup ==="
echo ""

# ── 1. Writable tmpdir ───────────────────────────────────────────

echo "[1/6] Creating writable tmpdir..."
mkdir -p "$HOME/Claude/tmpdir"
echo "  Created: $HOME/Claude/tmpdir"

# ── 2. Linker wrapper (SDK lld requires libxml2.so.16 which doesn't exist) ──

echo "[2/6] Creating ld.bfd linker wrapper..."
WRAPPER_DIR="$HOME/Claude/lib/linker_wrapper"
mkdir -p "$WRAPPER_DIR"
if [ ! -f "$WRAPPER_DIR/ld.lld" ]; then
    cat > "$WRAPPER_DIR/ld.lld" << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
    chmod +x "$WRAPPER_DIR/ld.lld"
    echo "  Created: $WRAPPER_DIR/ld.lld"
else
    echo "  Already exists: $WRAPPER_DIR/ld.lld"
fi

# ── 3. Shell environment ─────────────────────────────────────────

echo "[3/6] Installing shell environment config..."
cp "$SKILL_DIR/config/zshenv" "$HOME/.zshenv"
echo "  Installed: $HOME/.zshenv"
echo "  Run 'source ~/.zshenv' to activate in current session."

# ── 4. Claude Code config ────────────────────────────────────────

echo "[4/6] Installing Claude Code helper scripts..."
mkdir -p "$HOME/.claude"

cp "$SCRIPT_DIR/ssh-fetch-polyfill.js" "$HOME/.claude/ssh-fetch-polyfill.js"
echo "  Installed: $HOME/.claude/ssh-fetch-polyfill.js"

cp "$SCRIPT_DIR/start-claude.sh" "$HOME/.claude/start-claude.sh"
echo "  Installed: $HOME/.claude/start-claude.sh"

# ── 5. Global CLAUDE.md rules ────────────────────────────────────

echo "[5/6] Installing global CLAUDE.md rules..."
if [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
    cp "$SKILL_DIR/rules/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    cp "$SKILL_DIR/rules/CLAUDE.cn.md" "$HOME/.claude/CLAUDE.cn.md"
    echo "  Installed: $HOME/.claude/CLAUDE.md + CLAUDE.cn.md"
else
    echo "  Already exists: $HOME/.claude/CLAUDE.md (not overwritten)"
    echo "  To update, run: cp $SKILL_DIR/rules/CLAUDE.md ~/.claude/CLAUDE.md"
fi

# ── 6. Onboarding skip ───────────────────────────────────────────

echo "[6/6] Configuring Claude Code onboarding..."
if [ ! -f "$HOME/.claude/config.json" ]; then
    echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude/config.json"
    echo "  Created: $HOME/.claude/config.json (onboarding skipped)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run: source ~/.zshenv"
echo "  2. Install toolchains as needed (see SKILL.md docs/ references)"
echo "  3. Start a new Claude Code session (Skill will auto-load)"
echo ""
echo "To verify the environment:"
echo "  sh $SKILL_DIR/scripts/verify-env.sh"