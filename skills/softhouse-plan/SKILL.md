---
name: softhouse-plan
description: Planning-only phase of the Softhouse pipeline — breaks a requirement into a reviewable task graph with executor routing, dependencies, and model assignments, writes it to .softhouse/tasks.json, and stops. Never spawns worker agents or modifies source code. Use when the user runs /softhouse-plan or wants to review a pipeline plan before executing it with /softhouse resume.
---

# /softhouse-plan — Plan Only (No Execution) (v2.9.1)

<!-- SOFTHOUSE_PIPELINE_VERSION: 2.9.1 -->
**PIPELINE VERSION: `2.9.1`** — must match `/softhouse`'s version exactly. These two skills share one schema; if they disagree, a plan written here will not execute correctly there.

Runs only the planning phase of the Softhouse pipeline (Steps 0-2) without executing any tasks. Use this to review and refine the task graph before committing to execution.

Schema and rules are IDENTICAL to `/softhouse` STEP 2 (v2.9.1) — a plan written here must execute unmodified under `/softhouse resume`.

## Usage
- `/softhouse-plan <requirement>` — Generate a task plan

## Steps

### STEP 0 — Pre-flight
1. Run `git status` — abort if working tree is dirty.
1b. **Pipeline-version check** — read `.softhouse/pipeline.json` and apply the SAME rules as `/softhouse` STEP 0: missing → pin at the current version and say so; major mismatch → stop and ask the user to adopt; minor mismatch → warn, re-pin, continue; pinned newer than the skill → warn and ask. A plan must be written by the same pipeline version that will execute it, or `/softhouse resume` will reject it.
2. Read `CLAUDE.md` (or project context file) if it exists.
3. Read `.softhouse/patterns.md` in full (capped at 150 lines; `HARD GATES` are acceptance rules, not advice), then grep `.softhouse/patterns-archive.md` (if present) for the files, symbols and tags this requirement touches. Archived lessons are still binding; do not read the archive whole.
3b. Read `.softhouse/metrics.jsonl` (last 5 lines). **Escalation rule:** if any `failure_tags` value appears in 2 or more of the last 3 runs, change the approach for that task type in this plan and state in the plan summary which tag fired and what changed. A stronger model alone is not a change. Create the file empty if missing.
3c. If 3 or more runs carry token data, apply the **model-efficiency rule** (`/softhouse` STEP 8): a role on which opus does not beat sonnet on first-attempt rate defaults to sonnet, and the plan summary says so.
4. Read `.softhouse/tasks.json` — check current state. If a run is already IN PROGRESS (any task `in_progress`), warn the user. If the previous run is terminal (all tasks done/approved/deferred/cancelled), it is safe to replace — archive it to `.softhouse/runs/` first if not already there.
5. Read the most recent `.softhouse/runs/*.json` archive and pull its `backlog` array into planning input.
6. Identify the environment-safety facts (live deployment? which compose project? isolated test command? a TEST environment distinct from production?) — they determine `executor` routing and the `promotion` field. Decide the run's `isolation` mode: `"worktree"` by default, `"shared-sequential"` only when CLAUDE.md/patterns.md say worktrees are impractical for this repo.
6b. **Scout before planning:** grep for an existing rudimentary version of what is asked; scope the plan to the gap, not the whole epic.
7. If `.softhouse/queue/*.json` exists and `tasks.json` is idle, tell the user which plans are queued; a new plan written now may be queued instead of replacing `tasks.json` if the user prefers (`git mv` it under `.softhouse/queue/<run_id>.json`).
8. If `.softhouse/protected-paths.txt` exists, read it: any task whose `files_hint` matches a protected path gets `"protected": true`, may not be `"haiku"`, and counts as security for metrics.
9. If the project has `scripts/ci/wiring-census.sh`, run `--check` and note the count; the plan must not add library code without a call-site task.

### STEP 1 — Mode
This command always plans. If a run is in progress, ask user whether to replace it or abort.

### STEP 2 — Plan
Break the requirement into a task graph following the same rules as `/softhouse` (v2):

Each task object:
```json
{
  "id": "T1",
  "title": "Short title",
  "description": "Detailed instructions including file paths, what to implement, acceptance criteria",
  "agent_role": "coder",
  "executor": "agent",
  "model": "sonnet",
  "target": "backend",
  "files_hint": ["path/to/file1.py"],
  "dependencies": [],
  "status": "pending",
  "attempts": 0,
  "note": "",
  "protected": false,
  "promotion": "prod",
  "review_questions": []
}
```
Optional: `spec` (§-pointer into a spec document), `notes_to_executor`, `out_of_scope`.

**Planning rules:**
- `agent_role`: `"coder"`, `"test_writer"`, `"designer"` (HTML mockups + design spec BEFORE code), or `"cx_reviewer"`
- **UI feature chain rule (v2.1):** every NEW user-facing screen gets `T-design (designer) → [DESIGN GATE: orchestrator publishes mockup via Artifact, user approves] → T-implement (coder, depends on T-design) → T-cx (cx_reviewer)`; the coder's acceptance criterion is "match the approved mockup". Trivial UI tweaks may set `"design": "skip"` with a stated reason. Designer tasks read `.softhouse/design/` (tokens + component previews) and must reuse it.
- **`executor` — a safety boundary, not a label:**
  - `"agent"` (default) — repo-contained work verifiable in an isolated test stack; goes to a worktree worker agent.
  - `"orchestrator"` — host-level or live-prod-touching work (crontab, host configs like /etc/nginx, .env secrets, live-DB mutations, git push, restarts/redeploys, watching external CI). The main session does it inline; NEVER a worker agent.
  - `"user"` — decisions only the product owner can make (governance/legal sign-off, spend, restart windows). Surfaced, answered, recorded — never executed by an agent.
  - `"agent+orchestrator"` — agent writes the artifact, orchestrator installs/verifies on the host; state the split in the description.
- Tasks with overlapping `files_hint` MUST be serialized via `dependencies`
- Non-overlapping tasks CAN run in parallel
- Migration-creating tasks MUST be serialized with each other (linear chain)
- Work that must land atomically on the live system (config + secret + restart) → explicitly linked tasks + a stated single application window
- Add translation sub-tasks for user-facing strings
- Add index sub-tasks for new DB queries
- UI tasks: include the CX checklist (applicable subset for the project's UI paradigm; N/A items need justification); add a `cx_reviewer` task for user-facing pages
- Apply constraints from `.softhouse/patterns.md` and `.softhouse/patterns-archive.md`
- **Look up similar past tasks first:** `grep -i '<file or keyword>' .softhouse/handoff-index.tsv` (if present). A hit with a non-empty `failure_tags` column means the previous approach failed; the new task description must state what is different.
- **Derive `files_hint` from the acceptance line, not from memory.** For every deletion, rename or consolidation task, run the task's `Done when:` grep (and `grep -rln '<symbol>'` across the repo, including tests, mocks and adapters) against current main NOW and put every file it hits into `files_hint`. For an interface change also list its adapters; for a service-behaviour change, the handler that maps its errors to status codes. If the grep hits a file another task owns, serialize or split.
- **Every task `description` MUST end with a line starting `Done when:`** that names at least one runnable command and its expected result (exit code, grep count, HTTP status, coverage number). "build passes" alone is not acceptable. The reviewer executes this line verbatim in `/softhouse` STEP 5. A plan with a task lacking one is invalid — fix it before showing the plan.
- Run each `Done when:` line now against current main and record its red result in the description (e.g. `Planning-time result (red): grep → 0`). A line that cannot run at fork time cannot be satisfied by a worker; mark stack-dependent assertions with an `orchestrator:` prefix so the worker skips them honestly. A task that makes something reachable (route, guard, middleware) carries an `orchestrator:` live probe through the real route with the real auth and its expected status — unit tests do not prove a route is mounted or that its auth admits the intended caller.
- Tasks whose `files_hint` matches `.softhouse/protected-paths.txt` get `"protected": true` and will receive an independent review in `/softhouse` STEP 5 4e. **Every protected task carries 3–6 `review_questions`** the reviewer will ask ("where is the tenant checked before the query?"); the worker answers each with `file:line` in its handoff. Any task that adds or changes a handler always carries "which route and which auth reach this handler, and which test proves it?". If the plan assigns shared files (entry points, bootstrap, routes, config, compose) to the orchestrator, say so in the task and tell the worker to put the exact lines under `## Wiring for the orchestrator` in the handoff.
- **External sources, fixtures and the live check (v2.9)** — the same three rules as `/softhouse` STEP 2: list every outside URL the shipped code calls in `external_sources` (exact url, method, expect, purpose; never a guessed address, never a URL that is only test data); never list a fixture file for a source in `files_hint` or ask a worker to save a sample response — the orchestrator commits the real one at `tests/fixtures/sources/<name>.<ext>` and tests build other shapes in code; with no `uat.md` and no CLAUDE.md UAT section, write the planned live check into `uat` (setup that starts it as a user would, probes through the real routes with an `expect` regex; never a probe that only reruns the test suite), or `"uat": null` with the reason. Write setup as plain commands (`uvicorn app.main:app --port 8000 &` then a wait for the port) and set `"port"`: `/softhouse` runs them through `scripts/ci/uat-setup.sh` (venv for Python, own process group, stopped afterwards), so the plan needs no teardown just to kill the server.
- Every description's first line is `SCOPE SELF-CHECK (run first):` plus the one command that proves the listed files are the right ones.
- **Brief:** when 3 or more tasks share a spec, value table, rename map or security list, write it once to `.softhouse/briefs/{run_id}/brief.md` (template: `templates/brief.md` in the Softhouse repo), set top-level `"brief"` to that path, commit it with the plan, and keep task descriptions to their delta.
- Scale check: split a task that spans several whole large files or documents. Keep dependency installs in ONE task per run.
- Apply/ratify/deploy tasks depend on the producing task reaching `approved`, not `done`.
- **`promotion`:** `"test"` on any task whose surface is child-facing, money-moving, outward-facing or a visible redesign — the run stops at the TEST environment and production promotion becomes an `executor: "user"` decision in `/softhouse` STEP 5.5.
- `model` defaults: coder/test_writer/cx_reviewer → `"sonnet"`; `"haiku"` for trivial tasks (never on a protected task); `"opus"` for tasks whose failure is SILENT — code that compiles and passes tests while being wrong (security, tenancy, crypto, payment or settlement state machines, cross-package refactors). Loud-failure tasks stay on sonnet even when large; the executed acceptance line is the quality lever, not the model tier.
- **Token budget:** set a top-level `budget_tokens` from `metrics.jsonl` (`sum of tokens_per_approved_task[model]` + protected tasks × measured review cost, × 1.3 for retries). First run with no data: 250k per sonnet task, 500k per opus task (≈400k per protected opus task including its review), 60k per haiku task. It is a pacing guard — `/softhouse` stops and asks at 80%.

**After planning:**
1. Write plan to `.softhouse/tasks.json` (`pipeline_version` records which pipeline produced the graph — `/softhouse resume` checks it before executing):
   ```json
   {
     "run_id": "<timestamp-based-id>",
     "pipeline_version": "<current pipeline version>",
     "feature": "<short feature name>",
     "requirement": "<full requirement text>",
     "status": "planning",
     "isolation": "worktree",
     "budget_tokens": 0,
     "brief": null,
     "external_sources": [],
     "uat": null,
     "verified": null,
     "backlog": [],
     "tasks": [...]
   }
   ```
1b. **Probe every source**, exactly as `/softhouse` After planning step 1b: `scripts/ci/source-probe.sh` per `external_sources` entry, saving OK responses to `tests/fixtures/sources/<name>.<ext>`; a NOT OK entry is fixed (real address) or dropped (not really called) and probed again, never kept; requirement URLs are probed as advisory, skipping placeholders and duplicates of a listed source; fixture paths for a source are removed from every `files_hint`.
2. Display the task graph table (and, in the summary under it, each source's probe line, the live check or `uat: none — <reason>` (a run without one can only complete UNVERIFIED), which escalation tags fired and what changed, and the budget):
   ```
   | ID | Title | Role | Executor | Model | Target | Deps | Files | Protected | Promotion |
   |----|-------|------|----------|-------|--------|------|-------|-----------|-----------|
   ```
3. Show the dependency/parallelism structure visually, and call out which tasks are orchestrator/user-executed (they gate live-system windows)
4. Commit AND push: `git add .softhouse/tasks.json && git commit -m "softhouse: plan — <feature>"`, then each OK source's response in its own commit (`git add tests/fixtures/sources/<name>.<ext> && git commit -m "softhouse: probe <name>"`), then `git push`

### Output
Tell the user:
> Plan saved to `.softhouse/tasks.json`. Review the task graph above.
> To execute: run `/softhouse resume`
> To re-plan: run `/softhouse-plan <updated requirement>`

## Notes
- This command NEVER spawns worker agents or modifies project source code
- It only reads project files to inform the plan
- Safe to run multiple times — each run overwrites the previous plan (prior runs live in `.softhouse/runs/` + git history)
