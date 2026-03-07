#!/usr/bin/env python3
# Claude Code - Pin Last Message Hook
# UserPromptSubmit hook: reads JSON from stdin, writes prompt to session-specific file

import sys
import json
import os

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

prompt = data.get("prompt", "")
if not prompt:
    sys.exit(0)

ppid = os.getppid()
msg_file = os.path.join(os.path.expanduser("~/.claude"), f"last-prompt-{ppid}.txt")
try:
    with open(msg_file, "w") as f:
        f.write(prompt)
except Exception:
    pass
