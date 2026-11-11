#!/usr/bin/env bash
# Hook-level test: feeds fake hook JSON to bin/sdd-status with a stub herdr.
# Usage: test/run.sh   (exit 0 = all checks passed)
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
bin="$here/bin/sdd-status"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export SDD_STATUS_STATE_DIR="$tmp/state" SDD_STATUS_HERDR="$tmp/herdr" HERDR_PANE_ID="wT:p1"
printf '#!/bin/sh\necho "$@" >> %s/herdr.log\n' "$tmp" >"$tmp/herdr"; chmod +x "$tmp/herdr"

fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

repo="$tmp/repo"; mkdir -p "$repo/docs" "$repo/.superpowers/sdd/plan"
git -C "$repo" init -q
printf '# Plan\n### Task 1: a\n### Task 2: b\n### Task 3: c\n' >"$repo/docs/plan.md"
ws="$repo/.superpowers/sdd/plan"; echo docs/plan.md >"$ws/plan-path"
printf '# SDD ledger — plan: docs/plan.md\n' >"$ws/progress.md"

hook() { jq -n "$2" | "$bin" "$1"; }
bind=$(printf '{session_id:"S1",tool_name:"Bash",tool_input:{command:"bash scripts/sdd-workspace docs/plan.md; cat docs/plan.md; git rev-parse HEAD"},tool_response:{stdout:"%s\\n# Plan\\n### Task 1: a\\nabc123\\n"}}' "$ws")

hook post-tool "$bind" >/dev/null
check "binds session to workspace" '[ -f "$tmp/state/S1.json" ]'
check "label 0/3" 'grep -q "sdd=SDD 0/3" "$tmp/herdr.log"'

echo "Task 1: dispatched (BASE abc)" >>"$ws/progress.md"
hook post-tool '{session_id:"S1",tool_name:"Agent",tool_input:{}}' >/dev/null
check "label shows T1 impl" 'tail -1 "$tmp/herdr.log" | grep -q "SDD 0/3 · T1 impl"'

printf 'Task 1: complete (commits a..b, review clean)\nTask 2: dispatched\nTask 2: fix round 2/5 (1 open)\n' >>"$ws/progress.md"
hook post-tool '{session_id:"S1",tool_name:"Agent",tool_input:{}}' >/dev/null
check "label shows 1/3 · T2 fix 2/5" 'tail -1 "$tmp/herdr.log" | grep -q "SDD 1/3 · T2 fix 2/5"'

r=$("$bin" render "$ws")
check "one task: full words" '[ "$r" = "SDD 1/3 · T2 fix 2/5" ]'
cp "$ws/progress.md" "$tmp/ledger.bak"
printf 'Task 3: implemented\n' >>"$ws/progress.md"
r=$("$bin" render "$ws")
check "two tasks shortened to fit 22 cols" '[ "$r" = "SDD 1/3 T2 fix2 T3 rev" ]'
r=$(SDD_STATUS_WIDTH=40 "$bin" render "$ws")
check "wider sidebar keeps full words" '[ "$r" = "SDD 1/3 · T2 fix 2/5, T3 review" ]'
cp "$tmp/ledger.bak" "$ws/progress.md"

n=$(wc -l <"$tmp/herdr.log")
hook post-tool '{session_id:"S1",tool_name:"Read",tool_input:{}}' >/dev/null
check "no herdr call when label unchanged" '[ "$(wc -l <"$tmp/herdr.log")" = "$n" ]'

out=$(hook pre-tool "{session_id:\"S1\",tool_name:\"Edit\",tool_input:{file_path:\"$repo/src/app.ts\"}}")
check "guard denies orchestrator edit" 'grep -q "\"deny\"" <<<"$out"'
out=$(hook pre-tool "{session_id:\"S1\",tool_name:\"Write\",tool_input:{file_path:\"$ws/progress.md\"}}")
check "guard allows ledger write" '[ -z "$out" ]'
out=$(hook pre-tool "{session_id:\"S1\",agent_id:\"a1\",tool_name:\"Edit\",tool_input:{file_path:\"$repo/src/app.ts\"}}")
check "guard allows subagent edit" '[ -z "$out" ]'
out=$(hook pre-tool "{session_id:\"OTHER\",tool_name:\"Edit\",tool_input:{file_path:\"$repo/src/app.ts\"}}")
check "guard ignores other sessions" '[ -z "$out" ]'

printf 'Task 2: complete (x)\nTask 3: complete (y)\n' >>"$ws/progress.md"
hook post-tool '{session_id:"S1",tool_name:"Agent",tool_input:{}}' >/dev/null
check "label 3/3 · final review" 'tail -1 "$tmp/herdr.log" | grep -q "SDD 3/3 · final review"'

rm -rf "$ws"
hook post-tool '{session_id:"S1",tool_name:"Bash",tool_input:{command:"rm -rf ws"}}' >/dev/null
check "workspace deleted: label cleared" 'tail -1 "$tmp/herdr.log" | grep -q -- "--clear-token sdd"'
check "workspace deleted: state removed" '[ ! -f "$tmp/state/S1.json" ]'

mkdir -p "$ws"; echo docs/plan.md >"$ws/plan-path"
hook post-tool "$bind" >/dev/null
hook session-end '{session_id:"S1"}' >/dev/null
check "session end clears state" '[ ! -f "$tmp/state/S1.json" ]'

hook post-tool "$bind" >/dev/null
"$bin" off >/dev/null
check "off releases this pane" '[ ! -f "$tmp/state/S1.json" ]'

exit $fail
