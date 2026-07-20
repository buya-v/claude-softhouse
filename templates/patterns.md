# Softhouse learned patterns — <project>

Softhouse reads this file during pre-flight and applies it when planning. Anything above the markers is hand-written project knowledge; everything between the markers is appended automatically by each run's postmortem.

## Project constraints

State the rules a worker agent must not violate. Be specific — these get grepped against diffs during review.

- e.g. Auth checks in `app/deps.py` are non-negotiable; never widen a role gate to satisfy a test.
- e.g. Migrations are a linear chain; never branch them.
- e.g. `down -v` before every test run — the suite is brittle against stale volume state.

## Environment topology

This is what makes `executor` routing correct. Be explicit about what is live.

- **Live deployment on this host**: yes/no — which compose project / service manager?
- **Isolated test command**: e.g. `docker compose -p <proj>_<taskid> -f docker-compose.test.yml run --rm --build test`
- **Host-managed config** (nginx, crontab, TLS) — orchestrator-only, not in the repo?
- **Secrets**: where they live, who may touch them.

## Codebase facts

Durable knowledge worth carrying between runs — module boundaries, the test entry point, generated files that must not be hand-edited, libraries with a known gotcha.

<!-- LEARNED PATTERNS START -->
<!-- LEARNED PATTERNS END -->
