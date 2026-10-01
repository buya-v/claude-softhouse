# Softhouse learned patterns — <project>

Softhouse reads this file in full during pre-flight. It is capped at **150 lines** (STEP 9
refuses to complete a run while it is over). Everything above the markers is hand-written
project knowledge; the postmortems themselves live in `patterns-archive.md`, and STEP 8
may promote at most three one-line rules per run into the markers below — each naming the
check that enforces it. A lesson with no enforcing check is not a pattern; it is a
recurring failure waiting to happen.

## HARD GATES

Acceptance rules, not advice. The reviewer executes these; a diff that breaks one is
rejected. Number them so acceptance logs can cite "gate 3".

1. <e.g. Reachable or it does not count: `scripts/ci/wiring-census.sh --check` may not rise.>
2. <e.g. Test-writer diffs contain only test files, `tests/helpers/`, and the coverage baseline.>
3. <e.g. No simulated fallback outside the `SIMULATOR_MODE` flag.>
4. <e.g. Never widen a role gate in `app/deps.py` to satisfy a test.>

## Project constraints

Rules a worker agent must not violate. Be specific — these get grepped against diffs
during review.

- e.g. Migrations are a linear chain; never branch them.
- e.g. `down -v` before every test run — the suite is brittle against stale volume state.

## Environment topology

This is what makes `executor` routing and the promotion gate correct. Be explicit.

- **Live deployment on this host**: yes/no — which compose project / service manager?
- **TEST / staging environment**: where, how to deploy to it (orchestrator-only)
- **Isolated test command**: e.g. `docker compose -p <proj>_<taskid> -f docker-compose.test.yml run --rm --build test`
- **Isolation mode**: `worktree` (default) or `shared-sequential` (say why: hoisted
  monorepo install, shared toolchain)
- **Host-managed config** (nginx, crontab, TLS) — orchestrator-only, not in the repo?
- **Secrets**: where they live, who may touch them.

## Codebase facts

Durable knowledge worth carrying between runs — module boundaries, the test entry point,
generated files that must not be hand-edited, libraries with a known gotcha. One line each,
with a path.

<!-- LEARNED PATTERNS START -->
<!-- promoted rules only: "- <rule> — enforced by: <check>  (run <id>)" -->
<!-- LEARNED PATTERNS END -->
