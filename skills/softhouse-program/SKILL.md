---
name: softhouse-program
description: Unattended multi-run driver above the Softhouse pipeline — reads a program of bounded contexts from .softhouse/program.json, picks the next READY context, plans and executes it with /softhouse, parks blocked work instead of halting, records human decisions in a gate register, and hands control back to itself until the program is complete or a user gate is the only thing left. Use when the user runs /softhouse-program, asks to drive a multi-context migration or roadmap unattended, or wants a scheduled fire (launchd, cron, cloud routine) to advance a program without a human in the loop.
---

# /softhouse-program — Program Driver (v1, optional)

`/softhouse` runs one requirement, then stops. `/softhouse-program` is the loop above it: a program is a list of bounded contexts with dependencies, and the driver advances it one context per invocation. What it removes is the *idle stop*, not a check — every gate in `/softhouse` still applies.

Proven on one project for ~100 unattended scheduled fires over three weeks (a Java → Go strangler port with 17 contexts). This skill is the domain-free skeleton of that driver. Read `docs/field-review-2026-10-01.md` in the Softhouse repo for what it cost as well as what it did.

## Usage
- `/softhouse-program init <goal>` — create `.softhouse/program.json` from a conversation about the contexts and their dependencies; never executes.
- `/softhouse-program` — one advance: close a terminal run if any, pick the next READY context, run it, persist, exit.
- `/softhouse-program status` — print contexts, gates pending, last history entries; no changes.
- `/softhouse-program stop <reason>` / `resume` — write or remove `.softhouse/STOPPED` in a commit that states why.

## `program.json`

```json
{
  "program_id": "<slug>",
  "goal": "<one paragraph>",
  "status": "active",
  "policy": {
    "one_context_per_fire": true,
    "auto_approve_plan_if_checklist_passes": true,
    "never_cross_user_gate": true,
    "park_and_continue_on_block": true,
    "max_retries_per_task": 1,
    "retry_model": "opus",
    "stop_conditions": ["STOPPED file present", "3 consecutive fires with no commits", "budget window exhausted"],
    "always_stop_gate_classes": ["CUTOVER", "CONTRACT", "REGULATORY", "ACTIVATION"]
  },
  "contexts": [
    {
      "id": "<ctx>", "title": "<name>", "tier": "A",
      "scope_paths": ["<globs the run may touch>"],
      "size_hint": 0,
      "dependencies": ["<ctx id>"],
      "status": "pending | in-progress | parked | done",
      "parked_reason": null,
      "run_id": null,
      "slices": [],
      "closed_on": null
    }
  ],
  "gates_pending": [],
  "cursor": {"last_context": null, "last_fire": null},
  "history": [],
  "incidents": [],
  "in_flight": null
}
```

A context is **READY** when every dependency is `done` (resolve against `.softhouse/runs/*.json` archives too — a context sat falsely blocked for several fires when only the live `tasks.json` was consulted) and no open gate in an `always_stop` class covers its scope. A context is **READY-FOR-ANALYSIS** when a gate blocks work that *consumes* a contract but not work that *produces knowledge* (analysis, extraction, test-corpus mining, gap audits): plan only that slice. An open gate must never mean an idle factory.

## Gate register — `.softhouse/gates.md`

Human decisions, append-only prose plus an authoritative table at the top (`| id | class | status | question | chosen_by | decided_on |`). When prose and table disagree, the table wins and is rebuilt from `program.json.gates_pending`.

- Classes: the project declares which ALWAYS stop (default: CUTOVER, CONTRACT, REGULATORY, ACTIVATION — anything that binds money, third parties, or production). Every other class (POLICY, ENGINEERING, PRODUCT) is **agent-decidable**: the driver chooses, records `chosen_by: agent` with the reasoning and the counter-option, and continues; the owner retains veto and reverses by appending a block that says why (this path was exercised cleanly in the field).
- A gate whose answer the owner has given in advance lives in `.softhouse/gates-proposed-answers.md` (classified LEGAL / ENGINEERING / RESERVED); the driver cites it instead of asking.
- Never split a RESERVED gate into an agent-decidable piece by rewording it.

## Steps

### STEP 0 — Pre-flight
1. If `.softhouse/STOPPED` exists: print its first lines and exit. (It lives in the repo because a host-local scheduler disable did not survive a reboot.)
2. Take the lock: `.softhouse/LOCK` is a tracked file containing `{holder, started_at, fire_id}`; commit and **push** it before anything else. Freshness is the holder's push recency to origin (`git log -1 --format=%ct origin/main -- .softhouse/LOCK`), never a heartbeat — a live fire that never pushed its dispatch record lost four worker branches to a second fire. A lock older than 24 h is stale; take it over and record an incident.
3. `git pull --ff-only`. Read CLAUDE.md, `.softhouse/patterns.md`, `program.json`, `tasks.json`, `RESUME.md` (if present), `gates.md`, the last 5 `metrics.jsonl` lines.
4. Apply `/softhouse` STEP 0 in full (escalation rule, budget, protected paths, census).

### STEP 1 — Decide (first match wins)
| Condition | Action |
|---|---|
| program `status: complete` | report, release lock, exit |
| `tasks.json` has a run that is not terminal | `/softhouse resume` → STEP 4 |
| `tasks.json` has a terminal run | close it (`/softhouse` STEP 8–9), mark its context `done` or `parked`, append history, **fall through** |
| a READY context exists | STEP 2 with the smallest-id READY context (or the cursor's next) |
| a READY-FOR-ANALYSIS context exists | STEP 2 with the analysis slice only |
| only user gates remain | surface them (one message, all gates, evidence paths), release lock, exit |
| everything parked | print every `parked_reason`, release lock, exit |

### STEP 2 — Plan
Build the `/softhouse-plan` requirement from the context entry: title, `scope_paths`, dependencies' handoff paths, open gates that constrain it. If `size_hint` exceeds the project's split threshold (default: the size at which one run would need more than ~12 tasks), plan one **slice** and append it to `contexts[].slices`.

**Plan checklist (replaces the human "approve?" — all seven must hold or the driver asks instead of proceeding):**
1. every task has a runnable `Done when:` with a planning-time red result;
2. every task's `files_hint` lies inside `scope_paths` (an out-of-scope diff is a rejection in review);
3. no task touches an `always_stop` gate's subject;
4. protected tasks have `review_questions` and are not haiku;
5. `budget_tokens` is set from metrics and fits the remaining daily window;
6. no two tasks share a file without a dependency;
7. the escalation rule's required changes are present.

Record `plan_auto_approved: true` on the run with the checklist result.

### STEP 3 — Execute
`/softhouse resume`. Worktree isolation is mandatory in program mode; `shared-sequential` is not allowed unattended. Record every spawn in `program.json.in_flight` and push before the first `git worktree add`; make this a wrapper step, not a paragraph — it was missed twice by drivers who had read the paragraph.

### STEP 4 — Never-halt table
| Event | Action |
|---|---|
| task failed after its retry | park the task with a WIP note (`needs_retry`), continue the run |
| UAT red at run end | park the context with the evidence path; do not mark done |
| external dependency (oracle, service, credential) unreachable | park only the work that needs it; keep analysis tasks running |
| a `Done when:` exits non-zero because the harness itself is broken (exit 2 convention) | corpus/harness defect: open an ENGINEERING gate, park nothing else |
| 80% budget | `/softhouse` stop-and-ask becomes: finish in-flight workers, close the run as partial, exit; the next fire continues |
| a worker touched a file outside `scope_paths` | reject the task (`scope-creep`), record a violation in history |

### STEP 5 — Gate triage
For every new question the run raised: classify. `always_stop` class → append to `gates.md` as OPEN, add to `gates_pending`, continue with unaffected work. Otherwise decide now, cite evidence, record `chosen_by: agent`. Never decide a gate the owner has marked RESERVED.

### STEP 5.5 — Exit protocol (every exit, including failures)
1. No live workers at exit: wait, or rescue their WIP into `needs_retry` with a `STATE.json` per non-terminal task (`{task, branch, last_commit, wip_note}`).
2. `tasks.json` is truthful: every `in_progress` task has a live agent or is demoted.
3. Rewrite `.softhouse/RESUME.md`: what this fire did, what is parked and why, the next READY context, open gates. Stamp it with the fire id and time.
4. Verify every claimed commit exists on origin (`git branch -r --contains <sha>`); a run once recorded five "landed" commits that origin never saw.
5. Append to `program.json.history`: `{fire_id, context, run_id, outcome, commits, tokens, parked, gates_opened}`. Update `cursor`.
6. Commit, **push**, release `LOCK` (delete + commit + push).

### STEP 6 — Hand-back
If `one_context_per_fire` is true, exit after one context. Otherwise, if commits were made and a READY context remains, return to STEP 1. A fire with **no commits** stops the chain: three consecutive no-commit fires is a stop condition (expired credentials and rate limits once produced five days of zero-turn fires that looked like progress).

## Scheduled fires (optional)
- macOS launchd or cron runs `claude -p "/softhouse-program"` in the repo under a wrapper that: checks `STOPPED` → preflight → runs the driver → runs the exit protocol even if the driver crashed (prune worktrees, demote dead `in_progress`, stamp `RESUME.md` with a staleness banner, push). Keep the documented cadence and the plist in sync; they drifted in the field.
- A cloud routine may run the analysis-only path on the same program; it must take the same `LOCK` and must park any work that needs host-local services.
- Watchdog: count consecutive fires with no commits, no turns, or only `.softhouse/` changes; alert past 3. "Real progress is earned, never inherited."

## What this layer costs (say so in `init`)
On the one program that ran it, harness and instrument code grew to 1.5× the delivered product code, four agents died on navigation (briefs without a map), and the owner stopped the program after three weeks in favour of hand-driven briefs. Use it for a long, well-specified migration with a mechanical oracle; do not use it to explore.
