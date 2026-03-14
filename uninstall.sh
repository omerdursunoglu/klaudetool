#!/bin/bash
# klaudetool - Uninstaller

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Removing klaudetool..."

# Remove hook
rm -f "$CLAUDE_DIR/hooks/pin-last-message.py"
echo "[x] Removed hook"

# Remove proxy
rm -f "$CLAUDE_DIR/hooks/ratelimit-proxy.py"
echo "[x] Removed proxy"

# Remove prompt files
rm -f "$CLAUDE_DIR"/last-prompt-*.txt
echo "[x] Removed prompt cache files"

# Remove data files
rm -f "$CLAUDE_DIR/ratelimit_cache.json"
rm -f "$CLAUDE_DIR/ratelimit_refresh.lock"
rm -f "$CLAUDE_DIR/proxy_debug.json"
rm -f "$CLAUDE_DIR/total_cost.json"
rm -f "$CLAUDE_DIR/klaudetool_history.json"
rm -f "$CLAUDE_DIR/claufication_history.json"
echo "[x] Removed data files"

# Remove UserPromptSubmit hook from settings
if [ -f "$SETTINGS_FILE" ]; then
    python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

if 'hooks' in settings and 'UserPromptSubmit' in settings['hooks']:
    del settings['hooks']['UserPromptSubmit']

if 'statusLine' in settings:
    del settings['statusLine']

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
"
    echo "[x] Removed hook and statusLine config from settings.json"
fi

# Restore statusline backup or remove installed one
if [ -f "$CLAUDE_DIR/statusline.sh.bak" ]; then
    mv "$CLAUDE_DIR/statusline.sh.bak" "$CLAUDE_DIR/statusline.sh"
    echo "[x] Restored original statusline"
elif [ -f "$CLAUDE_DIR/statusline.sh" ]; then
    rm -f "$CLAUDE_DIR/statusline.sh"
    echo "[x] Removed statusline"
fi

# Remove KlaudeTool.app if installed
if [[ "$(uname)" == "Darwin" ]]; then
    APP_PATH="$HOME/Applications/KlaudeTool.app"
    if [ -d "$APP_PATH" ]; then
        read -p "Remove KlaudeTool.app from ~/Applications? [y/N]: " remove_app
        if [[ "$remove_app" =~ ^[Yy]$ ]]; then
            # Quit app if running
            osascript -e 'quit app "KlaudeTool"' 2>/dev/null || true
            rm -rf "$APP_PATH"
            echo "[x] Removed KlaudeTool.app"
        else
            echo "[=] Kept KlaudeTool.app"
        fi
    fi
fi

echo ""
echo "Done! Restart Claude Code to apply changes."
