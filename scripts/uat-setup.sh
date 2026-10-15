#!/usr/bin/env bash
# Live-check hygiene for STEP 5.5 and /softhouse-uat: a project venv for
# Python, setup steps in their own process group with output to a file, the
# leftover groups stopped afterwards, and a free-port check before starting.
#
# Why (softfactory, 2026-10-13/14, the mongolbank-rates live check):
#  - the host python3 was uv-managed and refused `pip install`, so the check
#    failed on `No module named 'requests'` with correct code: Python checks
#    get their own venv and never install into the host python;
#  - setup ran `uvicorn app.main:app --port 8000 &` with no teardown, and the
#    server still held port 8000 three hours after the run: every setup step
#    runs in its own process group, and `stop` ends what is left;
#  - a backgrounded server that inherits the runner's output pipe keeps the
#    runner waiting until its timeout: output goes to a file, never a pipe;
#  - a stale server from an earlier run would answer the probes with old
#    code: `port-free` refuses to start while something listens.
#
# Install into the consuming project as scripts/ci/uat-setup.sh.
#
# Usage:
#   scripts/ci/uat-setup.sh venv                # Python project only: create .softhouse/uat-venv, install deps
#   scripts/ci/uat-setup.sh port-free <port>    # exit 1 (and name the holder) if something listens
#   scripts/ci/uat-setup.sh start '<command>'   # run one setup step in its own group; exit = its exit
#   scripts/ci/uat-setup.sh run '<command>'     # run a probe or suite command in the venv (no group kept)
#   scripts/ci/uat-setup.sh stop                # stop every group `start` recorded; SIGTERM, 5 s, SIGKILL
# `start` and `run` activate .softhouse/uat-venv when it exists. State lives in
# .softhouse/uat-run/ (git-ignored by this script). Always call `stop`, pass or fail.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VENV="${SOFTHOUSE_UAT_VENV:-$ROOT/.softhouse/uat-venv}"
STATE="${SOFTHOUSE_UAT_STATE:-$ROOT/.softhouse/uat-run}"
MODE="${1:-}"

ignore_dir() { mkdir -p "$1" && printf '*\n' > "$1/.gitignore"; }
activate() { printf '[ -f %q ] && . %q; ' "$VENV/bin/activate" "$VENV/bin/activate"; }
group_alive() { kill -0 -- "-$1" 2>/dev/null; }

case "$MODE" in
  venv)
    cd "$ROOT"
    if [ -f requirements.txt ]; then uv_src=(-r requirements.txt); pip_src=(-r requirements.txt)
    elif [ -f pyproject.toml ]; then uv_src=(-r pyproject.toml); pip_src=(-e .)
    else echo "not a Python project (no requirements.txt or pyproject.toml): no venv needed"; exit 0; fi
    if [ ! -x "$VENV/bin/python" ]; then
      if command -v uv >/dev/null 2>&1; then uv venv --quiet "$VENV" || exit 1
      else python3 -m venv "$VENV" || exit 1; fi
    fi
    printf '*\n' > "$VENV/.gitignore"
    if command -v uv >/dev/null 2>&1; then uv pip install --quiet --python "$VENV/bin/python" "${uv_src[@]}" || exit 1
    else "$VENV/bin/python" -m pip install --quiet "${pip_src[@]}" || exit 1; fi
    echo "dependencies installed in $VENV"
    ;;

  port-free)
    port="${2:?usage: uat-setup.sh port-free <port>}"
    if command -v lsof >/dev/null 2>&1; then
      holder="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $1 " (pid " $2 ")"; exit }')"
    elif (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      holder="an unknown process"
    else holder=""; fi
    if [ -n "$holder" ]; then echo "port $port is held by $holder: stop it before the live check, or the probes test old code"; exit 1; fi
    echo "port $port is free"
    ;;

  start)
    command="${2:?usage: uat-setup.sh start '<command>'}"
    ignore_dir "$STATE"
    n=$(( $(ls "$STATE"/setup-*.log 2>/dev/null | wc -l) + 1 ))
    log="$STATE/setup-$n.log"
    cd "$ROOT"
    # perl's setpgrp gives the shell its own group (macOS has no setsid); a
    # child started with `&` inherits it. Output to a file, so nothing keeps
    # this script's caller waiting on a pipe.
    perl -e 'setpgrp(0, 0); exec "sh", "-c", $ARGV[0]' "$(activate)$command" > "$log" 2>&1 < /dev/null &
    pid=$!
    echo "$pid" >> "$STATE/groups"
    wait "$pid"; rc=$?
    tail -40 "$log"
    exit $rc
    ;;

  run)
    command="${2:?usage: uat-setup.sh run '<command>'}"
    cd "$ROOT" && sh -c "$(activate)$command"
    ;;

  stop)
    [ -f "$STATE/groups" ] || { echo "nothing to stop"; exit 0; }
    stopped=0
    while IFS= read -r pgid; do
      [ -n "$pgid" ] && group_alive "$pgid" || continue
      kill -TERM -- "-$pgid" 2>/dev/null
      for _ in $(seq 50); do group_alive "$pgid" || break; sleep 0.1; done
      if group_alive "$pgid"; then
        kill -KILL -- "-$pgid" 2>/dev/null
        for _ in $(seq 20); do group_alive "$pgid" || break; sleep 0.1; done
      fi
      stopped=$((stopped + 1))
    done < "$STATE/groups"
    rm -f "$STATE/groups"
    echo "stopped $stopped background process group(s) left by setup"
    ;;

  *)
    sed -n '20,27p' "$0" >&2
    exit 2
    ;;
esac
