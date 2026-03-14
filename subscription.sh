#!/bin/bash
# klaudetool - Subscription Management
# Set, update, or remove your subscription renewal day

SUB_FILE="$HOME/.claude/subscription.json"

show_status() {
    if [ -f "$SUB_FILE" ]; then
        day=$(python3 -c "import json; print(json.load(open('$SUB_FILE')).get('renewal_day', 0))" 2>/dev/null)
        if [ "$day" -gt 0 ] 2>/dev/null; then
            days_left=$(python3 -c "
import json, datetime
day = json.load(open('$SUB_FILE')).get('renewal_day', 0)
today = datetime.date.today()
try:
    nxt = today.replace(day=day)
except ValueError:
    import calendar
    nxt = today.replace(day=min(day, calendar.monthrange(today.year, today.month)[1]))
if nxt <= today:
    m, y = today.month + 1, today.year
    if m > 12: m, y = 1, y + 1
    import calendar
    nxt = datetime.date(y, m, min(day, calendar.monthrange(y, m)[1]))
print((nxt - today).days)
" 2>/dev/null)
            echo "Renewal day: $day"
            echo "Days until renewal: $days_left"
        else
            echo "No renewal day set."
        fi
    else
        echo "No subscription configured."
    fi
}

case "${1:-}" in
    set)
        if [[ -n "${2:-}" ]]; then
            day="$2"
        else
            read -p "Enter renewal day (1-31): " day
        fi
        if [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
            echo "{\"renewal_day\": $day}" > "$SUB_FILE"
            echo "Renewal day set to $day."
            show_status
        else
            echo "Error: Day must be between 1 and 31."
            exit 1
        fi
        ;;
    remove)
        rm -f "$SUB_FILE"
        echo "Subscription config removed."
        ;;
    status|"")
        show_status
        ;;
    *)
        echo "Usage: bash subscription.sh [set [day] | remove | status]"
        echo ""
        echo "Commands:"
        echo "  set [day]  - Set renewal day (1-31)"
        echo "  remove     - Remove subscription tracking"
        echo "  status     - Show current subscription info (default)"
        echo ""
        echo "Examples:"
        echo "  bash subscription.sh set 16"
        echo "  bash subscription.sh set"
        echo "  bash subscription.sh remove"
        ;;
esac
