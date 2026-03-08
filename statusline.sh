#!/usr/bin/env python3
# Claude Code Status Bar - Quota & Rate Limit Tracking + Pinned Last Message
# Shows session info, 5h/7d rate limits, and your last message pinned above stats

import sys
import json
import os
import time
import subprocess
import datetime

HOME = os.path.expanduser("~")
CACHE_FILE = os.path.join(HOME, ".claude", "ratelimit_cache.json")
CACHE_MAX_AGE = 300  # Refresh every 5 minutes

# --- Read session data from stdin ---
try:
    session = json.load(sys.stdin)
except Exception:
    session = {}

cost = session.get("cost", {}).get("total_cost_usd", 0)
cw = session.get("context_window", {})
used_pct = cw.get("used_percentage", 0)
remaining_pct = cw.get("remaining_percentage", 100)
cw_size = cw.get("context_window_size", 0)
input_tokens = cw.get("total_input_tokens", 0)
output_tokens = cw.get("total_output_tokens", 0)
total_tokens = input_tokens + output_tokens
model_info = session.get("model", {})
if isinstance(model_info, dict):
    model_name = model_info.get("display_name", model_info.get("id", "unknown"))
else:
    model_name = str(model_info)

model_short = model_name.replace(" (1M context)", "").replace("claude-", "")

def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}k"
    return str(n)

# --- Rate limit data ---
def get_oauth_token():
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            creds = json.loads(result.stdout.strip())
            return creds.get("claudeAiOauth", {}).get("accessToken", "")
    except Exception:
        pass
    return ""

def fetch_rate_limits(token):
    try:
        result = subprocess.run(
            ["curl", "-s", "-D", "-", "-o", "/dev/null",
             "https://api.anthropic.com/v1/messages",
             "-H", f"x-api-key: {token}",
             "-H", "anthropic-version: 2023-06-01",
             "-H", "content-type: application/json",
             "-d", '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}'],
            capture_output=True, text=True, timeout=10
        )
        headers = {}
        for line in result.stdout.split("\n"):
            if "anthropic-ratelimit-unified" in line:
                parts = line.strip().split(": ", 1)
                if len(parts) == 2:
                    key = parts[0].replace("anthropic-ratelimit-unified-", "")
                    headers[key] = parts[1].strip()
        return headers
    except Exception:
        return {}

def load_cache():
    try:
        with open(CACHE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def save_cache(data):
    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(data, f)
    except Exception:
        pass

cache = load_cache()
cache_age = time.time() - cache.get("timestamp", 0)

if cache_age > CACHE_MAX_AGE:
    token = get_oauth_token()
    if token:
        rl = fetch_rate_limits(token)
        if rl:
            cache = {
                "timestamp": time.time(),
                "5h_util": float(rl.get("5h-utilization", 0)),
                "5h_reset": int(rl.get("5h-reset", 0)),
                "5h_status": rl.get("5h-status", "unknown"),
                "7d_util": float(rl.get("7d-utilization", 0)),
                "7d_reset": int(rl.get("7d-reset", 0)),
                "7d_status": rl.get("7d-status", "unknown"),
            }
            save_cache(cache)

def color_pct(utilization):
    pct = f"{utilization*100:.0f}%"
    if utilization < 0.5:
        return f"\033[38;2;39;245;70m{pct}\033[0m"
    elif utilization < 0.8:
        return f"\033[38;2;245;242;39m{pct}\033[0m"
    else:
        return f"\033[38;2;245;39;39m{pct}\033[0m"

def fmt_reset(ts):
    if not ts:
        return ""
    remaining = int(ts - time.time())
    if remaining <= 0:
        return "0m"
    days = remaining // 86400
    hours = (remaining % 86400) // 3600
    mins = (remaining % 3600) // 60
    parts = []
    if days > 0:
        parts.append(f"{days}d")
    if hours > 0:
        parts.append(f"{hours}h")
    if mins > 0 and days == 0:
        parts.append(f"{mins}m")
    return "".join(parts)

def get_subscription_days():
    sub_file = os.path.join(HOME, ".claude", "subscription.json")
    try:
        with open(sub_file) as f:
            renewal_day = json.load(f).get("renewal_day", 0)
        if not renewal_day:
            return None
        today = datetime.date.today()
        try:
            next_renewal = today.replace(day=renewal_day)
        except ValueError:
            import calendar
            last_day = calendar.monthrange(today.year, today.month)[1]
            next_renewal = today.replace(day=min(renewal_day, last_day))
        if next_renewal <= today:
            month = today.month + 1
            year = today.year
            if month > 12:
                month = 1
                year += 1
            import calendar
            last_day = calendar.monthrange(year, month)[1]
            next_renewal = datetime.date(year, month, min(renewal_day, last_day))
        return (next_renewal - today).days
    except Exception:
        return None

# --- Format output ---
util_5h = cache.get("5h_util", 0)
reset_5h = cache.get("5h_reset", 0)
util_7d = cache.get("7d_util", 0)
reset_7d = cache.get("7d_reset", 0)

pct_5h = color_pct(util_5h)
pct_7d = color_pct(util_7d)

DIM = "\033[2m"
GREEN = "\033[38;2;39;245;70m"
CYAN = "\033[36m"
YELLOW = "\033[38;2;245;242;39m"
RESET = "\033[0m"

if used_pct < 50:
    ctx_color = GREEN
elif used_pct < 80:
    ctx_color = YELLOW
else:
    ctx_color = "\033[38;2;245;39;39m"

sub_days = get_subscription_days()
sub_text = ""
if sub_days is not None:
    if sub_days > 10:
        sub_color = GREEN
    elif sub_days > 5:
        sub_color = YELLOW
    elif sub_days > 3:
        sub_color = "\033[38;2;255;165;0m"
    else:
        sub_color = "\033[38;2;245;39;39m"
    sub_text = f"{sub_color}{sub_days}d{RESET}"

# --- Read last prompt (session-specific) ---
ppid = os.getppid()
last_prompt = ""
prompt_file = os.path.join(HOME, ".claude", f"last-prompt-{ppid}.txt")
try:
    with open(prompt_file) as f:
        last_prompt = f.read().strip().replace("\n", " ")
except Exception:
    pass

def get_term_width():
    for method in [
        lambda: int(subprocess.run(
            ["stty", "size"], capture_output=True, text=True, timeout=2,
            stdin=open("/dev/tty")
        ).stdout.strip().split()[1]),
        lambda: int(os.environ.get('COLUMNS', '0')),
        lambda: os.get_terminal_size().columns,
        lambda: int(subprocess.run(
            ["tput", "cols"], capture_output=True, text=True, timeout=2
        ).stdout.strip()),
    ]:
        try:
            w = method()
            if w and w > 0:
                return w
        except Exception:
            continue
    return 60

term_width = get_term_width()

sep = f" {DIM}|{RESET} "

# Always show full stats
_parts = [
    f"{CYAN}{model_short}{RESET}",
    f"{ctx_color}{used_pct}%{RESET}",
    f"5h {pct_5h} {DIM}{fmt_reset(reset_5h)}{RESET}",
    f"7d {pct_7d} {DIM}{fmt_reset(reset_7d)}{RESET}",
    f"{DIM}{fmt_tokens(total_tokens)}/{fmt_tokens(cw_size)}{RESET}",
    f"{DIM}${cost:.2f}{RESET}",
]
if sub_text:
    _parts.append(sub_text)
stats = sep.join(_parts)

if last_prompt:
    PIN = "\033[38;2;255;180;50m"
    effective_width = max(term_width - 5, 25)
    msg_max = effective_width - 2
    display = last_prompt if len(last_prompt) <= msg_max else last_prompt[:msg_max - 1] + "…"
    print(f"{PIN}{display}{RESET}\n{stats}")
else:
    print(stats)
