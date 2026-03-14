#!/usr/bin/env bash
# Claude Code Statusline — Installer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing Claude Code Statusline..."

# 1. Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo ""
  echo "ERROR: jq is required but not installed."
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt install jq"
  echo "  Arch:   sudo pacman -S jq"
  exit 1
fi

# 2. Ensure ~/.claude exists
mkdir -p "$HOME/.claude"

# 3. Copy script
cp "$SCRIPT_DIR/statusline-command.sh" "$TARGET"
chmod +x "$TARGET"
echo "  Copied statusline-command.sh to $TARGET"

# 4. Configure settings.json
if [ -f "$SETTINGS" ]; then
  # Check if statusLine is already configured
  if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "  statusLine already configured in $SETTINGS — skipping."
  else
    # Add statusLine to existing settings
    tmp=$(mktemp)
    jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  Added statusLine config to $SETTINGS"
  fi
else
  # Create new settings file
  echo '{"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}}' | jq . > "$SETTINGS"
  echo "  Created $SETTINGS with statusLine config"
fi

echo ""
echo "Done! Restart Claude Code to see your new status line."
