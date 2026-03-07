#!/bin/bash
# lastmessage - Claude Code Pin Last Message Installer
# Pins your last message above the status bar so you never lose track of what you asked.

set -e

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "lastmessage - Claude Code Pin Last Message"
echo "============================================"
echo ""

# Check if Claude Code is installed
if ! command -v claude &> /dev/null; then
    echo "Error: Claude Code is not installed."
    exit 1
fi

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# Copy hook script
cp "$SCRIPT_DIR/hooks/pin-last-message.sh" "$HOOKS_DIR/pin-last-message.sh"
chmod +x "$HOOKS_DIR/pin-last-message.sh"
echo "[+] Hook installed: $HOOKS_DIR/pin-last-message.sh"

# Add UserPromptSubmit hook to settings.json
if [ -f "$SETTINGS_FILE" ]; then
    # Check if UserPromptSubmit hook already exists
    if grep -q "UserPromptSubmit" "$SETTINGS_FILE"; then
        echo "[=] UserPromptSubmit hook already configured in settings.json"
    else
        # Use python to safely merge the hook into existing settings
        python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

settings['hooks']['UserPromptSubmit'] = [{
    'hooks': [{
        'type': 'command',
        'command': 'python3 ~/.claude/hooks/pin-last-message.sh',
        'timeout': 3
    }]
}]

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
"
        echo "[+] UserPromptSubmit hook added to settings.json"
    fi
else
    # Create minimal settings with the hook
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/pin-last-message.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
EOF
    echo "[+] Created settings.json with UserPromptSubmit hook"
fi

# Handle statusline
echo ""
echo "StatusLine Setup"
echo "----------------"

if [ -f "$CLAUDE_DIR/statusline.sh" ]; then
    echo "You already have a statusline.sh."
    echo ""
    echo "Options:"
    echo "  1) Patch your existing statusline (adds pin message above your stats)"
    echo "  2) Replace with full statusline (includes rate limits + pin message)"
    echo "  3) Skip statusline setup"
    echo ""
    read -p "Choose [1/2/3]: " choice

    case $choice in
        1)
            # Check if already patched
            if grep -q "last-prompt-" "$CLAUDE_DIR/statusline.sh"; then
                echo "[=] Statusline already has pin message support"
            else
                echo ""
                echo "Add this block to your statusline.sh, right before your final print():"
                echo ""
                cat "$SCRIPT_DIR/statusline-patch.py"
                echo ""
                echo "See statusline-patch.py for the full patch code."
            fi
            ;;
        2)
            cp "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh.bak"
            cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
            chmod +x "$CLAUDE_DIR/statusline.sh"
            echo "[+] Statusline replaced (backup: statusline.sh.bak)"
            ;;
        3)
            echo "[=] Skipped statusline setup"
            ;;
        *)
            echo "[=] Invalid choice, skipping"
            ;;
    esac
else
    cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
    chmod +x "$CLAUDE_DIR/statusline.sh"

    # Add statusLine config if not present
    python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

if 'statusLine' not in settings:
    settings['statusLine'] = {
        'type': 'command',
        'command': '~/.claude/statusline.sh',
        'padding': 0
    }

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
"
    echo "[+] Statusline installed: $CLAUDE_DIR/statusline.sh"
fi

echo ""
echo "Done! Restart Claude Code to see your pinned messages."
echo ""
echo "Your last message will appear in orange above the stats bar."
echo "Each terminal session shows its own pinned message."
