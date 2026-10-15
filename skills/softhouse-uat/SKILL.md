---
name: softhouse-uat
description: Runs the current project's UAT acceptance suites against its live or staging system, resolving the UAT definition from .softhouse/uat.md, a CLAUDE.md verification section, or a generic fallback. Use when the user runs /softhouse-uat, asks to run UAT or acceptance tests, or needs to verify a deployed system end-to-end.
---

# /softhouse-uat — Run UAT Acceptance Tests (v2, project-parameterized)

Runs the CURRENT project's UAT suite against its live/staging system. v2: this skill no longer hardcodes any project — the UAT definition is resolved from the repo you are in.

## Usage
- `/softhouse-uat` — Run all UAT suites for this project
- `/softhouse-uat <suite>` — Run one named suite (names come from the project's UAT config)

## Resolution order (STEP 0)

Resolve the UAT definition for the current working directory, in this order:

1. **`.softhouse/uat.md`** in the repo — the canonical per-project UAT config. It declares:
   - **Pre-flight**: health/smoke URLs or commands that must succeed before testing
   - **Deploy/refresh**: how to get the system under test current (and whether that is orchestrator-only / user-scheduled — NEVER deploy a live system implicitly)
   - **Suites**: named suites with their exact commands
   - **Pass criteria** and where evidence (reports/screenshots) lands
2. A **"UAT" or "Verification" section** in CLAUDE.md or the project's OPERATIONS doc.
3. **The planned live check** in `.softhouse/tasks.json` `uat` (v2.9, written by the planner when there is no config): run its `setup`, then each probe (output must match its `expect` regex), then its `teardown`. A probe that only reruns the test suite does not count.
4. **Generic fallback** (no config found):
   - (a) full test suite green in an ISOLATED stack (never the live default compose project)
   - (b) live smoke: health endpoint returns 200 + one end-to-end domain action succeeds (e.g. an authenticated API round-trip with a test credential)
   - (c) for UI changes: fetch the changed pages, assert HTTP 200 and no raw errors ("undefined", "NaN", stack traces) in the HTML
   - Report which of a/b/c ran; recommend the user create `.softhouse/uat.md`.

## Steps

### 1. Pre-flight
- Run the project's declared pre-flight checks (or fallback: `curl -sf <health-url>`).
- **Binary proof:** when the suite is meant to verify a change, confirm the running system contains it before running anything — rebuild with an explicit `--build`, then grep the container's binary or bundle for a string unique to the change (or compare the image's build label to the commit). Record the proof at the top of the report. A green suite against a stale image is the most expensive false positive this skill can produce.
- If any fail: warn the user and ask whether to start/deploy services first. Do NOT deploy anything yourself unless the project config explicitly sanctions it — deploys to live systems are orchestrator actions and may need a user-scheduled window.

### 1b. Live-check hygiene (v2.9.1)
- Before a command that starts a server process itself (`uvicorn … &`, `npm start &`): `scripts/ci/uat-setup.sh port-free <port>`. A busy port means a server this run did not start would answer: stop and report its holder. Skip it for a deploy of a managed stack (`docker compose up -d --build` replaces what holds the port) and for a live or staging system the suites target.
- Python project: `scripts/ci/uat-setup.sh venv` (`.softhouse/uat-venv`, uv first). Never `pip install` into the host python and never `--break-system-packages`; a uv- or Homebrew-managed python refuses it, and a correct change then fails on a missing module.
- Start anything the suites need with `scripts/ci/uat-setup.sh start '<command>'` (own process group, output to a file: a backgrounded server can neither hang the run nor outlive it). Run suite commands that need the venv with `scripts/ci/uat-setup.sh run '<command>'`.
- At the end, pass or fail: `scripts/ci/uat-setup.sh stop`, and put its `stopped N …` line in the report.

### 2. Run Tests
- No argument (or `all`): run every declared suite.
- With an argument: run the matching named suite from the project config; if no match, list the available suite names.

### 3. Report Results
- Pass/fail summary with counts per suite
- For failures: test name, error message, evidence path (screenshot/report)
- Overall verdict: **PASS** (all green) or **FAIL** (any red)
- **Verified or not (v2.9):** say whether anything ran against the RUNNING system (config suites, the planned live check, or fallback b/c). Only isolated test suites — fallback (a), or a configured suite that just reruns `pytest`/`npm test`/`go test` — means **UNVERIFIED**: the tests agree with each other, which is not evidence that the feature works. `/softhouse` records this as `verified` in `tasks.json`.

### 4. Baseline updates (visual suites only)
If the project declares a visual-regression suite and failures are confirmed INTENTIONAL by the user, run the project's declared update-snapshots command. Never update baselines without explicit user confirmation.

## Writing a `.softhouse/uat.md` (template)

```markdown
# UAT config — <project>
## Pre-flight
- curl -sf https://<host>/health          # must be 200
## Deploy/refresh (orchestrator-only; user-scheduled if disruptive)
- git pull && docker compose up -d --build
## Suites
- **api**: docker compose -p <proj>_uat -f docker-compose.test.yml run --rm test pytest tests/api/
- **pages**: <command>
## Pass criteria
- all suites green; no "undefined"/"NaN"/stack traces in fetched pages
## Evidence
- <path>
```

## Example `.softhouse/uat.md` (Playwright-based project)
- Pre-flight: `curl -sf http://127.0.0.1:8080/healthz` + `curl -sf https://admin.example.com/`; re-register admin if auth-service restarted
- Suites (from `tests/playwright`, `--project=uat --reporter=list`): `pages` → `uat/admin-pages.spec.ts`, `bot` → `uat/bot-agent.spec.ts`, `api` → `uat/api-contracts.spec.ts`, `visual` → `uat/visual-regression.spec.ts`
- Visual baseline update: `npx playwright test uat/visual-regression.spec.ts --update-snapshots`
- Env: `ADMIN_BASE_URL`, `GATEWAY_URL`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`
