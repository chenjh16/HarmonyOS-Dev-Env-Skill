#!/bin/sh
# install-skill.sh - Install HarmonyOS-Dev-Env Skill into Claude Code
#
# This script copies the self-contained harmonyos-dev-env/ skill directory
# into ~/.claude/skills/ (global) or <project>/.claude/skills/ (project-level).
#
# Usage:
#   sh install-skill.sh              # Global install (recommended)
#   sh install-skill.sh --project <path>  # Project-level install

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL_SRC="$REPO_ROOT/harmonyos-dev-env"

SCOPE="global"
PROJECT_PATH=""
NEXT_ARG=""
for arg in "$@"; do
    case $arg in
        --global) SCOPE="global" ;;
        --project)
            SCOPE="project"
            NEXT_ARG="project"
            ;;
        *)
            if [ "$NEXT_ARG" = "project" ]; then
                PROJECT_PATH="$arg"
                NEXT_ARG=""
            fi
            ;;
    esac
done

if [ "$SCOPE" = "project" ] && [ -z "$PROJECT_PATH" ]; then
    echo "Error: --project requires a path argument"
    echo "Usage: sh install-skill.sh --project <project-path>"
    exit 1
fi

if [ "$SCOPE" = "project" ]; then
    SKILL_DIR="$PROJECT_PATH/.claude/skills/harmonyos-dev-env"
else
    SKILL_DIR="$HOME/.claude/skills/harmonyos-dev-env"
fi

echo "=== Installing HarmonyOS-Dev-Env Skill ==="
echo "Source: $SKILL_SRC"
echo "Target: $SKILL_DIR"
echo "Scope:  $SCOPE"
echo ""

# Remove old installation if exists (to get clean update)
if [ -d "$SKILL_DIR" ]; then
    echo "Removing previous installation..."
    rm -rf "$SKILL_DIR"
fi

# Copy entire skill directory
mkdir -p "$(dirname "$SKILL_DIR")"
cp -r "$SKILL_SRC" "$SKILL_DIR"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Skill installed to: $SKILL_DIR"
echo ""
echo "The skill will be auto-loaded in your next Claude Code session."
echo "You can also invoke it directly: /harmonyos-dev-env"
echo ""
echo "To set up the shell environment (PATH, LD_LIBRARY_PATH, etc.):"
echo "  sh $SKILL_DIR/scripts/env-setup.sh"
echo ""
echo "To verify the installation:"
echo "  1. Start a new Claude Code session"
echo "  2. Ask: 'What HarmonyOS platform rules do you know?'"
echo "  3. Or run: sh $SKILL_DIR/scripts/verify-env.sh"