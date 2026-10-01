---
name: softhouse-plan
description: Planning-only phase of the Softhouse pipeline — breaks a requirement into a reviewable task graph with executor routing, dependencies, and model assignments, writes it to .softhouse/tasks.json, and stops. Never spawns worker agents or modifies source code. Use when the user runs /softhouse-plan or wants to review a pipeline plan before executing it with /softhouse resume.
---

# /softhouse-plan — Plan Only (No Execution) (v2.6)

Runs only the planning phase of the Softhouse pipeline (Steps 0-2) without executing any tasks. Use this to review and refine the task graph before committing to execution.

Schema and rules are IDENTICAL to `/softhouse` STEP 2 (v2.6) — a plan written here must execute unmodified under `/softhouse resume`.

## Usage
- `/softhouse-plan <requirement>` — Generate a task plan

## Steps

### STEP 0 — Pre-flight
1. Run `git status` — abort if working tree is dirty.
2. Read `CLAUDE.md` (or project context file) if it exists.
3. Read `.softhouse/patterns.md` AND `.softhouse/patterns-archive.md` (if present) for learned patterns. Archived lessons are still binding. Any `HARD GATES` section is acceptance rules, not advice.
3b. Read `.softhouse/metrics.jsonl` (last 5 lines). **Escalation rule:** if any `failure_tags` value appears in 2 or more of the last 3 runs, change the approach for that task type in this plan and state in the plan summary which tag fired and what changed. A stronger model alone is not a change. Create the file empty if missing.
3c. If 3 or more runs carry token data, apply the **model-efficiency rule** (`/softhouse` STEP 8): a role on which opus does not beat sonnet on first-attempt rate defaults to sonnet, and the plan summary says so.
4. Read `.softhouse/tasks.json` — check current state. If a run is already IN PROGRESS (any task `in_progress`), warn the user. If the previous run is terminal (all tasks done/approved/deferred/cancelled), it is safe to replace — archive it to `.softhouse/runs/` first if not already there.
5. Read the most recent `.softhouse/runs/*.json` archive and pull its `backlog` array into planning input.
6. Identify the environment-safety facts (live deployment? which compose project? isolated test command?) — they determine `executor` routing.
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
  "note": ""
}
```

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
- **Derive `files_hint` from the acceptance line, not from memory.** For every deletion, rename or consolidation task, run the task's `Done when:` grep (and `grep -rln '<symbol>'` across the repo, including tests, mocks and adapters) against current main NOW and put every file it hits into `files_hint`. For an interface change also list its adapters. If the grep hits a file another task owns, serialize or split.
- **Every task `description` MUST end with a line starting `Done when:`** that names at least one runnable command and its expected result (exit code, grep count, HTTP status, coverage number). "build passes" alone is not acceptable. The reviewer executes this line verbatim in `/softhouse` STEP 5. A plan with a task lacking one is invalid — fix it before showing the plan.
- Run each `Done when:` line now against current main and record its red result in the description (e.g. `Planning-time result (red): grep → 0`). A line that cannot run at fork time cannot be satisfied by a worker; mark stack-dependent assertions with an `orchestrator:` prefix so the worker skips them honestly.
- Tasks whose `files_hint` matches `.softhouse/protected-paths.txt` get `"protected": true` and will receive an independent review in `/softhouse` STEP 5 4e.
- `model` defaults: coder/test_writer/cx_reviewer → `"sonnet"`; `"haiku"` for trivial tasks (never on a protected task); `"opus"` for tasks whose failure is SILENT — code that compiles and passes tests while being wrong (security, tenancy, crypto, payment or settlement state machines, cross-package refactors). Loud-failure tasks stay on sonnet even when large; the executed acceptance line is the quality lever, not the model tier.
- **Token budget:** set a top-level `budget_tokens` from `metrics.jsonl` (`sum of tokens_per_approved_task[model]` + protected tasks × measured review cost, × 1.3 for retries). First run with no data: 250k per sonnet task, 500k per opus task (≈400k per protected opus task including its review), 60k per haiku task. It is a pacing guard — `/softhouse` stops and asks at 80%.

**After planning:**
1. Write plan to `.softhouse/tasks.json`:
   ```json
   {
     "run_id": "<timestamp-based-id>",
     "feature": "<short feature name>",
     "requirement": "<full requirement text>",
     "status": "planning",
     "budget_tokens": 0,
     "backlog": [],
     "tasks": [...]
   }
   ```
2. Display the task graph table (and, in the summary under it, which escalation tags fired and what changed, and the budget):
   ```
   | ID | Title | Role | Executor | Model | Target | Deps | Files | Protected |
   |----|-------|------|----------|-------|--------|------|-------|-----------|
   ```
3. Show the dependency/parallelism structure visually, and call out which tasks are orchestrator/user-executed (they gate live-system windows)
4. Commit AND push: `git add .softhouse/tasks.json && git commit -m "softhouse: plan — <feature>" && git push`

### Output
Tell the user:
> Plan saved to `.softhouse/tasks.json`. Review the task graph above.
> To execute: run `/softhouse resume`
> To re-plan: run `/softhouse-plan <updated requirement>`

## Notes
- This command NEVER spawns worker agents or modifies project source code
- It only reads project files to inform the plan
- Safe to run multiple times — each run overwrites the previous plan (prior runs live in `.softhouse/runs/` + git history)
