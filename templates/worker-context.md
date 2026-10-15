# <project> — worker context (read this, not CLAUDE.md)

Digest for Softhouse worker agents. Keep it under 200 lines. The orchestrator reads the
full CLAUDE.md and the patterns files; workers read only this file, which is pasted
verbatim into every worker prompt (block [2] of the fixed prompt layout, so every agent in
a wave shares a cacheable prefix). If a task needs a fact that is not here, `grep` for it
rather than reading whole documents.

Keep in sync: any task that changes conventions, the schema map, test commands or hard
gates must update this file (STEP 9.0 of `/softhouse`).

## What this repo is
<two or three lines: language and version, main services, data stores, default branch.
If the pipeline text says "main" but the default branch is something else, say so here.>

Known gaps: <what is scaffolded but not wired; point at the wiring census baseline if the
project has one, so workers do not assume unreachable code is live.>

## Environment and safety
- <Where production is, or "this host is DEV; there is no production".> Never run deploy
  scripts, never ssh, never touch `.env`, `secrets/`, `~/.ssh`.
- Do NOT run `docker compose up/down/build/restart`; the orchestrator owns stacks. Verify
  with language-native commands only (below).
- You are in an isolated git worktree. Work on branch `softhouse/<taskid>-<slug>`. Commit
  there. Never touch the default branch. Never run git against the shared checkout.
- Start by running `pwd` and `git rev-parse --show-toplevel` and confirm you are inside the
  worktree, not the main checkout.
- You may NOT spawn sub-agents. Plan, edit, verify, hand off — yourself.

## How to read code (token discipline)
- Files under 300 lines: read whole. Larger: `grep -n '<symbol>'` then read a line range.
  <name any files over ~1,000 lines so nobody reads them whole>
- Read only `files_hint` and their direct imports. Do not survey the codebase.
- Test output: never verbose. Pipe through `| tail -40`. Never cat a coverage profile or log.

## Verify commands (scoped; the orchestrator runs the full suite per wave)
```
<build command for the packages in files_hint>
<test command, short mode, for the packages in files_hint> 2>&1 | tail -40
<lint/format command for the packages touched> 2>&1 | tail -40
# frontend, only if you touched it:
<frontend build command> 2>&1 | tail -20
```
<Which tests need external services (Docker, a database) and when to run them.>

## Layout
| Area | Path |
|---|---|
| Entry points | `<path>` |
| Domain models | `<path>` |
| Services | `<path>` |
| Repositories / data access | `<path>` |
| HTTP handlers / API types | `<path>` |
| Middleware / auth | `<path>` |
| Migrations | `<path>` (ordering rule) |
| Test helpers | `<path>` |
| Frontend shared code | `<path>` |

## Conventions (enforced in review)
- <one line each: error style, context passing, DI style, mock style, pagination limit,
  env-var registration, logging rules, response envelope, anything greppable>

## Schema map (frequent typo sources)
- <table → schema.table pairs that get misspelled>
- <tenancy / RLS rules: how tenant reaches a query, what happens without it>
- <DB roles and which one the app connects as>
- <state-machine rules: which transitions are forbidden>
- Migrations are serialized by the planner; if your task needs one it did not plan, STOP
  and report.

## Test data
<test accounts, test cards, fixture names — never real credentials>

## Hard gates (your work is rejected if it breaks one)
1. Reachable or it does not count: new library code must be constructed from a started
   binary; the wiring census (if present) may not rise.
2. Your `Done when:` line is executed verbatim by the reviewer. "build passes" alone is
   not acceptance.
3. Anything you list under Blockers / Not done that overlaps your acceptance line means the
   task is NOT done — say so plainly, do not mark it done.
4. Test-writer tasks: your diff may contain only test files, the test-helper package and
   the coverage baseline. Never change a constructor to make it testable.
5. No simulated fallbacks outside an explicit simulator flag. No "try real, else fake".
6. No hardcoded tenant or account IDs; no setters that bypass identity from credentials.
7. Stay inside `files_hint`. If your acceptance line can only pass by touching a file
   outside `files_hint`, STOP: commit what you have, list the extra files under Blockers
   with the reason, and end your turn. The orchestrator widens the list and resumes you.
   Do not expand scope on your own — the extra file may belong to another task in flight.
8. Never resolve a merge conflict with `--theirs/--ours` on source files.
9. Protected paths (`.softhouse/protected-paths.txt`) get an independent review; expect it.
   If the task carries REVIEW QUESTIONS, answer each with `file:line` in the handoff.
10. Do not restructure or split files beyond the task.
11. Orchestrator-owned shared files (<entry points, bootstrap, routes, config registration,
    compose — list them>) are never edited by a worker. Put the exact lines the orchestrator
    must add under `## Wiring for the orchestrator` in your handoff; it wires them before review.
12. Outside sources: call only the addresses the task names, test against the saved real
    responses under `tests/fixtures/sources/`, and never write fixture data for a source
    yourself (rejected as `invented-fixture`). Build other shapes (empty, null) in test code.
13. Never turn a failure into an empty success: no catch-all handler whose body only
    discards the error (`except Exception: data = []`, `catch {}`, `.catch(() => [])`).
    Let it raise, or log and record it. A deliberate ignore needs its `file:line` and reason
    under Decisions in the handoff (rejected as `swallowed-error` otherwise).
14. No credentials in the diff: read them from the environment. Values that look like a key,
    token or password are caught by the secret scan before merge (`secret-in-diff`).
15. Type checker: this run's baseline error count may not rise; run the project's type
    check on your packages, since the test runner may not check types.

## Handoff (max 40 lines per attempt, at `.softhouse/handoff/{run_id}/{task.id}.md`)
```
# Handoff: {task.id} — {title}
## Changes   (file → one line each)
## Acceptance (paste the Done when command and its last lines of output)
## Decisions (only non-obvious ones)
## Review answers (protected tasks: each REVIEW QUESTION → file:line)
## Wiring for the orchestrator (exact lines for the shared files you may not edit)
## Blockers / Not done (be exact; this list is binding)
## Tokens   (from your final usage line, if visible)
```
Commit the handoff to your branch — an uncommitted branch is pruned and your output is
destroyed. End your final message with the acceptance command's result line and the
literal line "live stack untouched".
