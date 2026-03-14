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
LOCK_FILE = os.path.join(HOME, ".claude", "ratelimit_refresh.lock")
PROXY_SCRIPT = os.path.join(HOME, ".claude", "hooks", "ratelimit-proxy.py")
TOTAL_COST_FILE = os.path.join(HOME, ".claude", "total_cost.json")
CACHE_MAX_AGE = 600  # Refresh every 10 minutes

# --- Read session data from stdin ---
try:
    session = json.load(sys.stdin)
except Exception:
    session = {}

cost = session.get("cost", {}).get("total_cost_usd", 0)
session_id = session.get("session_id", "")

# --- Total cost tracking (resets each subscription period) ---
def get_billing_period_start():
    """Get the start date of the current billing period."""
    sub_file = os.path.join(HOME, ".claude", "subscription.json")
    try:
        with open(sub_file) as f:
            renewal_day = json.load(f).get("renewal_day", 0)
        if not renewal_day:
            return None
        today = datetime.date.today()
        # Current period started on renewal_day of this or last month
        try:
            period_start = today.replace(day=renewal_day)
        except ValueError:
            import calendar
            last_day = calendar.monthrange(today.year, today.month)[1]
            period_start = today.replace(day=min(renewal_day, last_day))
        if period_start > today:
            # renewal_day hasn't passed yet this month, period started last month
            month = today.month - 1
            year = today.year
            if month < 1:
                month = 12
                year -= 1
            import calendar
            last_day = calendar.monthrange(year, month)[1]
            period_start = datetime.date(year, month, min(renewal_day, last_day))
        return period_start.isoformat()
    except Exception:
        return None

def get_total_cost(session_id, session_cost):
    """Track cumulative cost within the current billing period."""
    try:
        with open(TOTAL_COST_FILE) as f:
            tc = json.load(f)
    except Exception:
        tc = {}

    period = get_billing_period_start()

    # Reset if new billing period
    if period and period != tc.get("period", ""):
        tc = {"period": period, "total_previous": 0, "current_session_id": "", "current_session_cost": 0}

    if not tc.get("period"):
        tc["period"] = period or ""

    if session_id and session_id != tc.get("current_session_id", ""):
        tc["total_previous"] = tc.get("total_previous", 0) + tc.get("current_session_cost", 0)
        tc["current_session_id"] = session_id
        tc["current_session_cost"] = session_cost
    else:
        tc["current_session_cost"] = session_cost

    try:
        with open(TOTAL_COST_FILE, "w") as f:
            json.dump(tc, f)
    except Exception:
        pass

    return tc.get("total_previous", 0) + session_cost

total_cost = get_total_cost(session_id, cost)

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
def load_cache():
    try:
        with open(CACHE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def is_refresh_running():
    try:
        if os.path.exists(LOCK_FILE):
            lock_age = time.time() - os.path.getmtime(LOCK_FILE)
            if lock_age < 120:
                return True
            os.remove(LOCK_FILE)
    except Exception:
        pass
    return False

def start_background_refresh():
    """Spawn background process: starts a local proxy, runs claude through it,
    proxy captures rate limit headers from API response and writes to cache."""
    if is_refresh_running():
        return

    try:
        with open(LOCK_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        return

    try:
        pid = os.fork()
    except Exception:
        try:
            os.remove(LOCK_FILE)
        except Exception:
            pass
        return

    if pid > 0:
        return  # Parent continues with statusline

    # Child process - do the refresh
    try:
        os.setsid()
        sys.stdin.close()
        sys.stdout.close()
        sys.stderr.close()
        devnull = os.open(os.devnull, os.O_RDWR)
        os.dup2(devnull, 0)
        os.dup2(devnull, 1)
        os.dup2(devnull, 2)

        # Start proxy
        proxy_proc = subprocess.Popen(
            ["python3", PROXY_SCRIPT],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        port_line = proxy_proc.stdout.readline().decode().strip()
        if not port_line:
            proxy_proc.terminate()
            return

        # Run claude through proxy
        env = os.environ.copy()
        env["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{port_line}"

        subprocess.run(
            ["sh", "-c",
             "echo h | claude -p --model haiku --max-turns 1 "
             "--settings '{\"hooks\":{},\"statusLine\":null}' "
             "--no-session-persistence"],
            capture_output=True, text=True, timeout=45, env=env
        )

        # Give proxy a moment to write cache
        time.sleep(0.5)
        proxy_proc.terminate()
        try:
            proxy_proc.wait(timeout=5)
        except Exception:
            proxy_proc.kill()

    except Exception:
        pass
    finally:
        try:
            os.remove(LOCK_FILE)
        except Exception:
            pass
        os._exit(0)

# --- Cache check and background refresh ---
cache = load_cache()
cache_age = time.time() - cache.get("timestamp", 0)
now = time.time()

# Refresh if cache is stale OR if any reset time has passed
reset_passed = (
    (cache.get("5h_reset", 0) and now > cache.get("5h_reset", 0)) or
    (cache.get("7d_reset", 0) and now > cache.get("7d_reset", 0))
)
if cache_age > CACHE_MAX_AGE or reset_passed:
    start_background_refresh()

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
    def _stty_width():
        with open("/dev/tty") as tty:
            r = subprocess.run(["stty", "size"], capture_output=True, text=True, timeout=2, stdin=tty)
        return int(r.stdout.strip().split()[1])

    for method in [
        _stty_width,
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
    f"{DIM}${cost:.2f}{RESET} {DIM}(${total_cost:.2f}){RESET}",
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
