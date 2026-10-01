#!/usr/bin/env bash
# Appends one line per task of the current run to .softhouse/handoff-index.tsv
# (STEP 9 0b of /softhouse). Columns:
#   run_id  task  role  model  status  attempts  failure_tags  title  files_hint
# Plain TSV, grep-able, no database. Idempotent: lines already present for this
# run_id are not duplicated.
#
# Install into the consuming project as scripts/ci/handoff-index-append.sh and
# run it from STEP 9 before archiving tasks.json. Manual appends decay; this
# script exists because a run that appended 2 of 8 rows by hand was observed.
#
# Usage: scripts/ci/handoff-index-append.sh [path/to/tasks.json]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
TASKS="${1:-.softhouse/tasks.json}"
INDEX=".softhouse/handoff-index.tsv"
[[ -f "$INDEX" ]] || printf 'run_id\ttask\trole\tmodel\tstatus\tattempts\tfailure_tags\ttitle\tfiles_hint\n' > "$INDEX"
python3 - "$TASKS" "$INDEX" <<'EOF'
import json, sys
tasks_path, index_path = sys.argv[1], sys.argv[2]
run = json.load(open(tasks_path))
run_id = run.get("run_id")
if not run_id:
    print("tasks.json is idle; nothing to index"); sys.exit(0)
existing = {tuple(l.rstrip("\n").split("\t")[:2]) for l in open(index_path)}
added = 0
with open(index_path, "a") as out:
    for t in run.get("tasks", []):
        key = (run_id, t.get("id", ""))
        if key in existing: continue
        row = [run_id, t.get("id",""), t.get("agent_role",""), t.get("model",""),
               t.get("status",""), str(t.get("attempts",0)),
               ",".join(t.get("failure_tags") or []),
               (t.get("title","") or "").replace("\t"," "),
               ",".join(t.get("files_hint") or [])]
        out.write("\t".join(row) + "\n"); added += 1
print(f"handoff-index: appended {added} row(s) for {run_id}")
EOF
