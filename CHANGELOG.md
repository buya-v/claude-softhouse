# Changelog

All notable changes to the Softhouse pipeline. Versions refer to the pipeline itself, which all three skills share.

## [2.6] — 2026-09-24

Landed in the repo on 2026-10-01 from the globally installed skill, together with 2.2–2.5 (all written the same day from an audit of a Go payment-platform project). See `docs/field-review-2026-10-01.md` for the measured evidence behind each mechanism.

- `files_hint` is derived from the task's acceptance grep at planning time, including tests, mocks and adapters; workers that need a file outside it **stop and report** instead of widening their own scope, and the orchestrator widens the list and resumes them.
- Acceptance logs run under `pipefail`, capture exit codes before any `| tail`, compare diffs against `git merge-base`, and pass explicit ref names to helper scripts.

## [2.5] — 2026-09-24

Token economy.

- Workers read a ≤200-line `.softhouse/worker-context.md` digest instead of CLAUDE.md and the patterns files; the orchestrator keeps it in sync (STEP 9.0). Template in `templates/worker-context.md`.
- Fixed worker-prompt layout — safety preamble → worker context → role text → task block — so every agent in a wave shares a cacheable prefix.
- Workers run scoped verify commands only; the orchestrator runs the full suite per wave. Read-by-range and `| tail -40` discipline; no sub-agents from workers; 40-line handoffs.

## [2.4] — 2026-09-24

- **Wiring census** (`scripts/wiring-census.sh`): the count of library constructors with no call site may never rise within a run; STEP 7 reverts the responsible merge with tag `unwired-library-code`.
- **Protected paths** (`.softhouse/protected-paths.txt`, `scripts/protected-paths-touched.sh`): any task or diff touching them gets the independent review and may not run on haiku.
- Per-run `budget_tokens` as a pacing guard: at 80% the orchestrator stops launching workers and asks.
- Queued plans under `.softhouse/queue/`.

## [2.3] — 2026-09-24

- **Independent review** for money and security diffs: a separate opus agent sees only the acceptance line, the diff and the security requirements — never the handoff — and its FAIL is a rejection. The planner and the orchestrator are the same session and would otherwise review their own plan.
- A retry must change the prompt (exact signatures, narrower scope, a split, or an explicit prohibition), not only the model.
- Opus is reserved for tasks whose failure is silent; loud-failure tasks stay on sonnet. The orchestrator always runs on the strongest model.

## [2.2] — 2026-09-24

Closes the learning loop. Rationale: the same lesson was recorded three times in one project and recurred each time, because lessons were prose read by a planner rather than gates checked by a reviewer.

- STEP 0 reads `patterns-archive.md` and `metrics.jsonl` and applies the **escalation rule**: a failure tag seen in 2 of the last 3 runs forces a changed approach, stated in the plan summary.
- Every task description ends with a runnable `Done when:` line.
- STEP 5 **executes** the acceptance line and stores the output under `.softhouse/uat-evidence/`; no evidence, no approval. It also rejects on the handoff's own "not done" list and enforces test-scope diffs for test writers.
- STEP 8 appends a machine-readable line to `metrics.jsonl` with tagged failures and tokens by model; a model-efficiency rule feeds back into planning.
- STEP 9 appends to `handoff-index.tsv`, the planner's grep-able "similar past tasks" lookup (`scripts/handoff-index-append.sh`).

## [2.1] — 2026-07-02

Added the **design stage** — design now happens before code, not after.

- New `designer` agent role: produces self-contained HTML mockups from the project design system (`.softhouse/design/`), using real domain data and covering the applicable CX states as variants in the same file.
- **Design gate**: the orchestrator publishes the mockup via the Artifact tool for browser review; the user approves, revises (one designer retry with notes injected), or skips. The gate blocks only the dependent coder task — unrelated tasks keep running.
- Approved mockups become the coder's binding acceptance criterion; the CX reviewer's first and highest-weight check becomes mockup-vs-implementation fidelity, and undocumented deviations are failures.
- **UI feature chain rule**: every new user-facing screen gets `designer → [gate] → coder → cx_reviewer`. Trivial tweaks may set `"design": "skip"` with a stated reason.
- New component previews carry a `@dsCard` annotation for design-system indexing.
- **STEP 6.5 DesignSync**: best-effort, incremental post-merge sync of component previews to a claude.ai design project. Orchestrator-only, skipped without authorization, never a gate.

Rationale: rejecting a mockup costs minutes; rejecting implemented code costs a full agent cycle.

## [2.0] — 2026-07-02

Hardening release, drawn from production build and recovery runs.

- **`executor` routing** (`agent` / `orchestrator` / `user` / `agent+orchestrator`) as an explicit safety boundary. Host-level and live-production work can no longer be routed to worker agents.
- **Mandatory environment-safety preamble** in every worker prompt: names the live deployment, requires a uniquely-named isolated test stack, and requires the worker to report `live stack untouched`.
- **Fork-from-current-main guarantee**: main is committed and pushed before any agent batch launches; review re-checks `git merge-base` before merging, because a three-way merge preserves disjoint files but not co-edited ones.
- **Run-namespaced handoffs** (`.softhouse/handoff/{run_id}/`) — task IDs collide across runs.
- **Concrete review checklist**: scope check, fork-freshness check, non-negotiables grep against `CLAUDE.md`, CX scoring with a <70% rejection threshold.
- **Micro-fix verdict**: defects that are small and mechanical (≲10 lines) are fixed inline post-merge rather than triggering a full retry cycle. Logic and design defects still get a retry.
- **Batched integration testing**: the suite runs per merge batch instead of per merge, with a mandatory final full-suite run regardless.
- **Project-parameterized UAT**: resolved from `.softhouse/uat.md` → a `CLAUDE.md` section → a generic fallback. No project is hardcoded in the skill anymore.
- **Backlog carry-forward**: gaps found mid-run are archived with the run and read as planning input by the next one.
- **Cleanup hygiene**: worktree removal and pruning, deletion of merged `softhouse/*` branches, and unmerged branches listed rather than deleted.
- Atomic live-system windows (config + secret + restart) must be planned as explicitly linked tasks and applied in a single window.
- Retries upgrade the worker model to Opus.

## [1.0]

Initial 9-step pipeline: plan → execute (parallel worktree agents) → review → merge → integration test → postmortem → cleanup, with a CX checklist for UI tasks, learned patterns in `.softhouse/patterns.md`, and resumable state in `.softhouse/tasks.json`.
