#!/usr/bin/env bash
# Prints the files changed between <base> and <branch> that match
# .softhouse/protected-paths.txt. Exit 0 on success; non-empty output means the
# task needs the independent review (SKILL STEP 5 4e) and may not run on haiku.
# Exit 2 = usage (an unresolvable ref): empty output then means nothing, so a
# caller that reads only the output must also check the exit status.
#
# Install into the consuming project as scripts/ci/protected-paths-touched.sh
# (the skill calls it by that path).
#
# Usage: scripts/ci/protected-paths-touched.sh main softhouse/T3-foo
# Pass EXPLICIT ref names: HEAD resolves in the repo this script lives in, not in
# the worktree you may be thinking of.
#
# Env:
#   TEST_FILE_PATTERN   regex for test files that never count as protected
#                       (default matches Go, JS/TS, Python test files)
#
# Portable: works on macOS bash 3.2 (no globstar/mapfile) by delegating to python3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
base="${1:-main}"; branch="${2:-HEAD}"
for ref in "$base" "$branch"; do
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null || { echo "not a commit: $ref" >&2; exit 2; }
done
TEST_FILE_PATTERN="${TEST_FILE_PATTERN:-(_test\.go|\.test\.[jt]sx?|\.spec\.[jt]sx?|^tests?/|/tests?/|test_[^/]*\.py|_test\.py)$}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
git diff --name-only "$base".."$branch" > "$tmp"
python3 - "$ROOT/.softhouse/protected-paths.txt" "$tmp" "$TEST_FILE_PATTERN" <<'EOF'
import sys, re, os
patfile, changed, testrx = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
if not os.path.exists(patfile):
    sys.exit(0)  # no protected-paths file: nothing is protected
pats=[l.strip() for l in open(patfile) if l.strip() and not l.startswith('#')]
def to_re(p):
    p=re.escape(p).replace(r'\*\*/', '(?:.*/)?').replace(r'\*\*', '.*').replace(r'\*', '[^/]*')
    return re.compile('^'+p+'$')
rx=[(p,to_re(p)) for p in pats]
hits=set()
for f in (l.strip() for l in open(changed)):
    if not f or testrx.search(f): continue
    for p,r in rx:
        if r.match(f): hits.add(f"{f}  <- {p}")
for h in sorted(hits): print(h)
EOF
