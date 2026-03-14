#!/bin/bash
# klaudetool - CLI StatusLine + macOS Menu Bar App Installer
# Pins your last message, tracks rate limits, shows usage graphs

set -e

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "klaudetool - Claude Code Toolkit"
echo "================================="
echo ""

# Check if Claude Code is installed
if ! command -v claude &> /dev/null; then
    echo "Error: Claude Code is not installed."
    exit 1
fi

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# Copy hook script
cp "$SCRIPT_DIR/cli/hooks/pin-last-message.py" "$HOOKS_DIR/pin-last-message.py"
chmod +x "$HOOKS_DIR/pin-last-message.py"
echo "[+] Hook installed: $HOOKS_DIR/pin-last-message.py"

# Copy ratelimit proxy
cp "$SCRIPT_DIR/cli/ratelimit-proxy.py" "$HOOKS_DIR/ratelimit-proxy.py"
echo "[+] Proxy installed: $HOOKS_DIR/ratelimit-proxy.py"

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
        'command': 'python3 ~/.claude/hooks/pin-last-message.py',
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
            "command": "python3 ~/.claude/hooks/pin-last-message.py",
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
                cat "$SCRIPT_DIR/cli/statusline-patch.py"
                echo ""
                echo "See cli/statusline-patch.py for the full patch code."
            fi
            ;;
        2)
            cp "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh.bak"
            cp "$SCRIPT_DIR/cli/statusline.sh" "$CLAUDE_DIR/statusline.sh"
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
    cp "$SCRIPT_DIR/cli/statusline.sh" "$CLAUDE_DIR/statusline.sh"
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

# macOS Menu Bar App
echo ""
echo "Menu Bar App Setup (macOS only)"
echo "-------------------------------"

if [[ "$(uname)" == "Darwin" ]]; then
    echo "KlaudeTool menu bar app shows rate limit graphs and plays notification sounds."
    echo ""
    read -p "Build and install KlaudeTool.app? [y/N]: " build_app

    if [[ "$build_app" =~ ^[Yy]$ ]]; then
        echo "[*] Building KlaudeTool.app..."
        cd "$SCRIPT_DIR/app"
        make bundle
        APP_DEST="$HOME/Applications"
        mkdir -p "$APP_DEST"
        rm -rf "$APP_DEST/KlaudeTool.app"
        cp -R KlaudeTool.app "$APP_DEST/KlaudeTool.app"
        echo "[+] KlaudeTool.app installed to $APP_DEST/"
        echo ""
        read -p "Launch KlaudeTool now? [y/N]: " launch_app
        if [[ "$launch_app" =~ ^[Yy]$ ]]; then
            open "$APP_DEST/KlaudeTool.app"
        fi
        cd "$SCRIPT_DIR"
    else
        echo "[=] Skipped menu bar app"
    fi
else
    echo "[=] Skipped (macOS only)"
fi

# Subscription renewal day
echo ""
echo "Subscription Setup"
echo "------------------"
SUB_FILE="$CLAUDE_DIR/subscription.json"
if [ -f "$SUB_FILE" ]; then
    current_day=$(python3 -c "import json; print(json.load(open('$SUB_FILE')).get('renewal_day', 'not set'))" 2>/dev/null)
    echo "Current renewal day: $current_day"
    read -p "Change renewal day? [y/N]: " change_sub
    if [[ "$change_sub" =~ ^[Yy]$ ]]; then
        read -p "Enter your subscription renewal day (1-31): " renewal_day
        if [[ "$renewal_day" =~ ^[0-9]+$ ]] && [ "$renewal_day" -ge 1 ] && [ "$renewal_day" -le 31 ]; then
            echo "{\"renewal_day\": $renewal_day}" > "$SUB_FILE"
            echo "[+] Renewal day set to $renewal_day"
        else
            echo "[!] Invalid day, skipping"
        fi
    fi
else
    read -p "Enter your subscription renewal day (1-31, or skip): " renewal_day
    if [[ "$renewal_day" =~ ^[0-9]+$ ]] && [ "$renewal_day" -ge 1 ] && [ "$renewal_day" -le 31 ]; then
        echo "{\"renewal_day\": $renewal_day}" > "$SUB_FILE"
        echo "[+] Renewal day set to $renewal_day"
    else
        echo "[=] Skipped subscription setup (set later with: bash subscription.sh)"
    fi
fi

echo ""
echo "Done! Restart Claude Code to see your pinned messages."
echo ""
echo "Your last message will appear in orange above the stats bar."
echo "Each terminal session shows its own pinned message."
