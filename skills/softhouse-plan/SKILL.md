---
name: softhouse-plan
description: Planning-only phase of the Softhouse pipeline — breaks a requirement into a reviewable task graph with executor routing, dependencies, and model assignments, writes it to .softhouse/tasks.json, and stops. Never spawns worker agents or modifies source code. Use when the user runs /softhouse-plan or wants to review a pipeline plan before executing it with /softhouse resume.
---

# /softhouse-plan — Plan Only (No Execution) (v2)

Runs only the planning phase of the Softhouse pipeline (Steps 0-2) without executing any tasks. Use this to review and refine the task graph before committing to execution.

Schema and rules are IDENTICAL to `/softhouse` STEP 2 (v2) — a plan written here must execute unmodified under `/softhouse resume`.

## Usage
- `/softhouse-plan <requirement>` — Generate a task plan

## Steps

### STEP 0 — Pre-flight
1. Run `git status` — abort if working tree is dirty.
2. Read `CLAUDE.md` (or project context file) if it exists.
3. Read `.softhouse/patterns.md` for learned patterns.
4. Read `.softhouse/tasks.json` — check current state. If a run is already IN PROGRESS (any task `in_progress`), warn the user. If the previous run is terminal (all tasks done/approved/deferred/cancelled), it is safe to replace — archive it to `.softhouse/runs/` first if not already there.
5. Read the most recent `.softhouse/runs/*.json` archive and pull its `backlog` array into planning input.
6. Identify the environment-safety facts (live deployment? which compose project? isolated test command?) — they determine `executor` routing.

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
- Apply constraints from `.softhouse/patterns.md`
- `model` defaults: coder/test_writer/cx_reviewer → `"sonnet"`; `"haiku"` for trivial tasks; `"opus"` for architecture/security/intricate-refactor/correctness-keystone tasks

**After planning:**
1. Write plan to `.softhouse/tasks.json`:
   ```json
   {
     "run_id": "<timestamp-based-id>",
     "feature": "<short feature name>",
     "requirement": "<full requirement text>",
     "status": "planning",
     "backlog": [],
     "tasks": [...]
   }
   ```
2. Display the task graph table:
   ```
   | ID | Title | Role | Executor | Model | Target | Deps | Files |
   |----|-------|------|----------|-------|--------|------|-------|
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
