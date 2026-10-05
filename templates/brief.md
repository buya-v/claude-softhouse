# Brief — <feature> (run <run_id>)

Committed to main with the plan, BEFORE any worker is spawned, so every worktree forks with
it. This file is the single source of truth for every task in the run; task descriptions
say "read the brief in full" and carry only their own delta. Workers do not re-derive
anything stated here. Reviewers verify against it.

## Standing facts
<the 5–10 project facts every task in this run depends on, each with a file:line or a
command that proves it. Nothing here is "probably">

## Scope
**IN:** <what this run delivers, by task id>
**OUT (deferred, named):** <slices deliberately not in this run, so nobody "helpfully"
does them>

## Canonical tables
<the rename map / value table / mapping that several tasks apply, with the exact target
location for each row. Example columns: old → new · where (file:line or §) · role/context ·
task that applies it>

| old | new | where | applied by |
|---|---|---|---|
| | | | |

## HELD — these are not oversights
<items that look like gaps but are deliberately left, with the reason. A worker that
"fixes" one of these has created a defect>

## What the reviews will attack
<the security / money / correctness properties the independent reviewer will probe, as
questions. Workers answer them in `## Review answers` with file:line>

1. <for every handler task: which route and which auth reach this handler, and which test proves it?>
2.
3.

## Gates every task runs before handoff
```
<scoped build / test / lint commands>
<the project's hard-gate scripts, if any>
```

## What the handoff must contain
- Changes (file → one line)
- Acceptance: the `Done when:` command and its last lines
- Review answers (protected tasks)
- `[VERIFIED: …]` / `[UNVERIFIED]` on every material claim
- Blockers / Not done — binding; anything here that overlaps the acceptance line means
  the task is not done
- Wiring for the orchestrator — exact lines for shared files the worker may not edit
