#!/bin/bash
# lastmessage - Uninstaller

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Removing lastmessage..."

# Remove hook
rm -f "$CLAUDE_DIR/hooks/pin-last-message.sh"
echo "[x] Removed hook"

# Remove prompt files
rm -f "$CLAUDE_DIR"/last-prompt-*.txt
echo "[x] Removed prompt cache files"

# Remove UserPromptSubmit hook from settings
if [ -f "$SETTINGS_FILE" ]; then
    python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

if 'hooks' in settings and 'UserPromptSubmit' in settings['hooks']:
    del settings['hooks']['UserPromptSubmit']

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
"
    echo "[x] Removed hook from settings.json"
fi

# Restore statusline backup if exists
if [ -f "$CLAUDE_DIR/statusline.sh.bak" ]; then
    mv "$CLAUDE_DIR/statusline.sh.bak" "$CLAUDE_DIR/statusline.sh"
    echo "[x] Restored original statusline"
fi

echo ""
echo "Done! Restart Claude Code to apply changes."
