#!/bin/zsh
# Prints the numbers from Orbit's reports, reading the database with your own Cloudflare login. There's no public
# page for these. Usage: scripts/metrics.sh [days, default 30]   or: scripts/metrics.sh crash <id>
set -euo pipefail
cd "${0:A:h}/.."
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"

query() {
  print -r -- "\n$1"
  npx --yes wrangler d1 execute orbit-reports --remote --json --command "$2" 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read()
rows = json.loads(text[text.index("["):])[0]["results"]
if not rows:
    print("  (none yet)")
    raise SystemExit
keys = list(rows[0])
widths = [max(len(k), *(len(str(r[k])) for r in rows)) for k in keys]
print("  " + "  ".join(k.ljust(w) for k, w in zip(keys, widths)))
for r in rows:
    print("  " + "  ".join(str(r[k]).ljust(w) for k, w in zip(keys, widths)))
'
}

if [[ "${1:-}" == "crash" ]]; then
  npx --yes wrangler d1 execute orbit-reports --remote --json --command "SELECT call_stack FROM crashes WHERE id = ${2:?crash id}" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.dumps(json.loads(json.load(sys.stdin)[0]["results"][0]["call_stack"]), indent=2))'
  exit 0
fi

days="${1:-30}"
[[ "$days" == <-> ]] || { echo "Days must be a number."; exit 2; }
since="date('now', '-$days days')"
print "Orbit, last $days days. Usage counts only people who opted in; one report is one Mac on one day."
query "Reporting Macs per day" "SELECT day, SUM(reports) AS macs FROM usage_daily WHERE day >= $since GROUP BY day ORDER BY day DESC LIMIT 14"
for column label in version "Version" os "macOS" arch "Chip" events_view "Events view" menu_bar_style "Menu bar style" text_size "Text size" event_density "Spacing" calendars "Calendars"; do
  query "$label" "SELECT $column AS value, SUM(reports) AS reports FROM usage_daily WHERE day >= $since GROUP BY $column ORDER BY reports DESC"
done
query "Crashes by version" "SELECT version, COUNT(*) AS crashes FROM crashes WHERE day >= $since GROUP BY version ORDER BY crashes DESC"
query "Latest crashes (scripts/metrics.sh crash <id> for the stack)" "SELECT id, day, version, build, os, arch, exception_type, signal FROM crashes WHERE day >= $since ORDER BY id DESC LIMIT 20"
