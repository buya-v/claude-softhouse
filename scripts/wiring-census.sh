#!/usr/bin/env bash
# Wiring census: lists exported constructors under SCAN_DIRS that have NO call
# site outside tests and their own definition — i.e. library code that no
# started binary constructs. Softhouse runs it at STEP 0 and after the final
# merge (STEP 7). The count may go DOWN in a run (something got wired) but never
# UP. A task that adds a constructor must also add its call site, or the run
# fails here.
#
# Install into the consuming project as scripts/ci/wiring-census.sh and set the
# three variables below for your language. The defaults are for Go.
#
# Usage:
#   scripts/ci/wiring-census.sh            # print the list and the count
#   scripts/ci/wiring-census.sh --check    # exit 1 if count > .softhouse/wiring-baseline.txt
#   scripts/ci/wiring-census.sh --update   # write the current count to the baseline
#
# Known limitation: a constructor called only from another UNWIRED constructor
# counts as wired. Good enough as a ratchet; not a reachability proof.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
BASELINE=".softhouse/wiring-baseline.txt"
MODE="${1:-}"

# --- per-project configuration -------------------------------------------
SCAN_DIRS=(internal/service)                 # where library constructors live
CALLER_DIRS=(cmd internal pkg)               # where call sites may live
SOURCE_GLOB='*.go'                           # --include pattern
TEST_FILE_RX='_test\.go:'                    # grep -v pattern for test files
DEF_RX='^func New[A-Za-z0-9_]+\('            # a constructor definition line
NAME_SED='s/.*func (New[A-Za-z0-9_]+)\(.*/\1/'   # extract the name from that line
# For TypeScript, for example:
#   SOURCE_GLOB='*.ts'; TEST_FILE_RX='\.(test|spec)\.ts:'
#   DEF_RX='^export (class|function) [A-Z][A-Za-z0-9_]+'
#   NAME_SED='s/.*export (class|function) ([A-Z][A-Za-z0-9_]+).*/\2/'
# ---------------------------------------------------------------------------

unwired=()
while IFS= read -r line; do
  file="${line%%:*}"
  name="$(sed -E "$NAME_SED" <<<"$line")"
  callers=$(grep -rn --include="$SOURCE_GLOB" -E "(^|[^A-Za-z0-9_])${name}\(" "${CALLER_DIRS[@]}" \
    | grep -vE "$TEST_FILE_RX" \
    | grep -vE "(func|class|function) (\([^)]*\) )?${name}\b" \
    | grep -v "^${file}:" || true)
  if [[ -z "$callers" ]]; then
    unwired+=("${name}  (${file})")
  fi
done < <(grep -rn --include="$SOURCE_GLOB" -E "$DEF_RX" "${SCAN_DIRS[@]}" | grep -vE "$TEST_FILE_RX")

count=${#unwired[@]}
if (( count > 0 )); then printf '%s\n' "${unwired[@]}" | sort; fi
echo "UNWIRED_CONSTRUCTORS=${count}"

case "$MODE" in
  --update)
    mkdir -p "$(dirname "$BASELINE")"
    echo "$count" > "$BASELINE"; echo "baseline written: $count" ;;
  --check)
    if [[ ! -f "$BASELINE" ]]; then echo "no baseline at $BASELINE (run --update once)"; exit 2; fi
    base=$(cat "$BASELINE")
    if (( count > base )); then
      echo "FAIL: unwired constructors rose from ${base} to ${count} — new library code with no call site"; exit 1
    fi
    echo "OK: ${count} <= baseline ${base}" ;;
esac
