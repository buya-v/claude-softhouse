#!/usr/bin/env bash
# Fixture provenance: in a run whose plan has probed external sources, list
# the fixture data a worker added or changed itself, instead of using the real
# responses the orchestrator saved. Softhouse runs it in STEP 5 for every task
# branch; any output is a REJECTED verdict with tag `invented-fixture`.
#
# Why: a softfactory run on mongolbank-rates wrote tests/fixtures/bom_latest.html
# from imagination, so 127 tests agreed with each other and with nothing real.
#
# A file is flagged when it sits under a fixture directory (fixtures,
# __fixtures__, testdata, test_data, samples, mocks), has a data extension
# (.html .htm .json .xml .csv .txt), was added or modified on the branch, and
# is not one of the saved responses or a declared local fixture. A saved
# response the branch changed is always flagged: workers may read it, never
# edit it.
#
# Local fixtures: data that does NOT stand in for an outside source (a Go
# testdata/golden.json, a sample config) is declared per task in tasks.json
# `local_fixtures` with a reason, and passed here with --allow, so the plan and
# this check agree on every file (a plan that lists a file this check rejects
# deadlocks the task).
#
# Install into the consuming project as scripts/ci/fixture-provenance.sh.
#
# Usage:
#   scripts/ci/fixture-provenance.sh <base-ref> <branch> [--allow <path>]... [saved-response-path ...]
#     The saved responses are the tasks.json external_sources[].path values,
#     normally tests/fixtures/sources/<name>.<ext>; --allow names each of the
#     task's local_fixtures. Diff is <base>...<branch> (three dots: what the
#     branch changed since it forked).
# Exit 0 = nothing invented, 1 = flagged files printed one per line, 2 = usage.
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '25,30p' "$0" >&2
  exit 2
fi
BASE="$1"; BRANCH="$2"; shift 2
SAVED=(); ALLOWED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --allow) [ $# -ge 2 ] || { echo "--allow needs a path" >&2; exit 2; }; ALLOWED+=("$2"); shift 2 ;;
    *) SAVED+=("$1"); shift ;;
  esac
done
is_allowed() {
  local file="$1" allowed
  for allowed in ${ALLOWED[@]+"${ALLOWED[@]}"}; do [ "$file" = "$allowed" ] && return 0; done
  return 1
}

is_saved() {
  local file="$1" saved
  for saved in ${SAVED[@]+"${SAVED[@]}"}; do [ "$file" = "$saved" ] && return 0; done
  return 1
}

flagged=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if is_saved "$file"; then
    echo "$file (a saved response; workers may not edit it)"
    flagged=1
    continue
  fi
  is_allowed "$file" && continue
  lower="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"
  case "/$lower" in
    */fixtures/*|*/__fixtures__/*|*/testdata/*|*/test_data/*|*/samples/*|*/mocks/*) ;;
    *) continue ;;
  esac
  case "$lower" in
    *.html|*.htm|*.json|*.xml|*.csv|*.txt) echo "$file"; flagged=1 ;;
  esac
done < <(git diff --name-only --diff-filter=AM "$BASE...$BRANCH")

exit $flagged
