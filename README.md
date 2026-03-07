# lastmessage

Pin your last message in Claude Code's status bar. Never lose track of what you asked while responses stream by.

![screenshot](screenshot.png)

## What it does

When you send a message in Claude Code, it gets pinned in the status bar area (orange text above the stats line). Each terminal session tracks its own pinned message independently - open 8 terminals and each one shows what you last asked in that specific session.

## How it works

1. **`UserPromptSubmit` hook** captures your message when you press Enter
2. Writes it to a session-specific file (`~/.claude/last-prompt-{pid}.txt`)
3. **StatusLine** reads and displays it above the stats bar

## Install

```bash
git clone https://github.com/dijitalbaslangic/lastmessage.git
cd lastmessage
bash install.sh
```

Then restart Claude Code.

## Uninstall

```bash
bash uninstall.sh
```

## Manual setup

If you prefer to set it up manually:

### 1. Copy the hook

```bash
mkdir -p ~/.claude/hooks
cp hooks/pin-last-message.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/pin-last-message.sh
```

### 2. Add hook to settings

Add this to your `~/.claude/settings.json` inside the `"hooks"` object:

```json
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
```

### 3. StatusLine (optional)

If you already have a statusline, add the patch from `statusline-patch.py` before your final `print()`.

If you don't have a statusline, copy the full one:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

And add to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 0
}
```

## Requirements

- Claude Code CLI
- Python 3
- macOS (for rate limit fetching via Keychain; the pin feature works on any OS)

## License

MIT
