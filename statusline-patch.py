#!/usr/bin/env python3
"""
Claude Code StatusLine Patch - Last Message Pin
Adds pinned last message display above the stats line in Claude Code's status bar.

This patch should be appended to your existing statusline.sh script,
right before the final print statement.

If you don't have a statusline.sh, use the full statusline.sh from this repo instead.
"""

# --- Append this block to your existing statusline.sh ---
# Place it right before your final print() statement

# === PIN LAST MESSAGE - START ===
import re

# Read last prompt (session-specific)
ppid = os.getppid()
last_prompt = ""
prompt_file = os.path.join(HOME, ".claude", f"last-prompt-{ppid}.txt")
try:
    with open(prompt_file) as f:
        last_prompt = f.read().strip().replace("\n", " ")
except Exception:
    pass

# Get terminal width
try:
    term_width = os.get_terminal_size().columns
except Exception:
    term_width = 100

# Print pinned message above stats
if last_prompt:
    PIN_COLOR = "\033[38;2;255;180;50m"
    RESET_COLOR = "\033[0m"
    max_len = term_width - 2
    display = last_prompt if len(last_prompt) <= max_len else last_prompt[:max_len - 3] + "..."
    print(f"{PIN_COLOR}{display}{RESET_COLOR}")
# === PIN LAST MESSAGE - END ===

# Then print your stats line:
# print(stats)
