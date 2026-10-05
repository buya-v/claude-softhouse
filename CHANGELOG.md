# Changelog

All notable changes to the Softhouse pipeline. Versions refer to the pipeline itself, which all three skills share.

## [2.8] — 2026-10-05

From the first full run under 2.7: nine tasks on a Go payment platform, 16 blind reviews with 7 real FAILs, and five more defects that only live UAT found. Each item below is a gate for one of those five, or for a review failure the pipeline itself caused.

- **Binary proof** before any stack suite is recorded (STEP 5.5 and `softhouse-uat`): explicit `--build`, then grep the running binary or bundle for a run-unique string. Every suite in that run first passed against the pre-merge image because the project's `make dev-up` omitted `--build`.
- **Wire before review** (STEP 3.3): orchestrator-owned shared files are wired on the worker's branch, built and committed before the independent reviewer is spawned. Workers hand the exact lines over under `## Wiring for the orchestrator` (worker-context template, hard gate 11; brief template).
- **Reachability acceptance** (STEP 2): a task that makes something reachable carries an `orchestrator:` live probe through the real route with the real auth; handler tasks always get the review question *which route and which auth reach this handler, and which test proves it?*
- **Micro-fix means mechanical** (STEP 5.6): error mapping, TTL rules, auth lists, YAML folded scalars and return-value changes are logic at any line count — worker with a test, or orchestrator edit plus delta review.
- **Handler layer in `files_hint`** (STEP 2, `softhouse-plan`): a service-behaviour change lists the handler that maps its errors.
- Worktree fallback when the session cwd is not the project repo (STEP 3.2); `timeout` fallback for macOS (Error Handling).

## [2.7] — 2026-10-01

From a field review of every Softhouse pipeline run under one home directory: nine projects, four independent forks, seven months (`docs/field-review-2026-10-01.md`). The common root cause of every recurring failure was that lessons stayed prose; 2.7 makes the learning loop structural and ports the forks' proven mechanisms.

- **Bounded learning**: `patterns.md` is capped at 150 lines and STEP 9 refuses to complete a run over the cap; postmortems go to `patterns-archive.md`; STEP 8 may promote at most three one-line rules per run and each must name the check that enforces it; a lesson seen twice with no enforcing check is flagged "recurring lesson, no gate". STEP 0 reads the active file in full and greps the archive.
- **Review questions**: protected tasks carry `review_questions`; workers answer each with `file:line`; the independent reviewer verifies the answers before looking further. Orchestrator edits to protected files go back for a delta review. A dead review agent is never an approval.
- **Planning-time red result** recorded for every `Done when:`; `orchestrator:` prefix for assertions that need the full stack; anchored acceptance regexes; `SCOPE SELF-CHECK` as the first line of every description.
- **Briefs**: the assembled worker prompt is persisted under `.softhouse/briefs/{run}/{task}.md`; runs whose tasks share a spec get a committed `brief.md` (template added).
- **Honesty tags** `[VERIFIED: <source>]` / `[UNVERIFIED]` on material claims; a fabricated provenance marker is a rejection; new tag `unverified-claim`.
- **Agent-failure recovery**: on timeout, rate limit, "stopped" or a duplicate completion, verify the tree, run the acceptance line on what is there, finish the last mile or mark `agent-no-commit`; never re-spawn blindly.
- **Shared-sequential isolation mode** (`"isolation"` on the run) for repos where worktrees are impractical; the orchestrator re-runs the gate before every commit.
- **Promotion gate**: `promotion: "test"` stops child-facing, money-moving or outward-facing work at the TEST environment behind an `executor: "user"` decision.
- **Merge guards** from real incidents: assert the current branch before every merge; stage explicit paths while workers are live; read handoffs with `git show <branch>:<path>` and three-dot diffs; never `--theirs/--ours` on source; interim gating run after the first protected merge; legacy suites before gating ones.
- **Tags and metrics**: `files-hint-incomplete` (planning defect, not a worker one), `review-caught-defect` (excluded from the escalation rule — reviews catching defects is the mechanism working), every escalation carries a "resolved when"; metrics gain `pipeline_version`, `isolation`, `scope_stops`, `recovered_agents`, `orchestrator_repairs`, `delta_reviews`, `uat_suites`, `promoted_to_prod`, `parked_at_test`, `tokens_by_role`, `rules_promoted`, and `active_min` replaces `wall_clock_min`; review tokens count toward `tokens_per_approved_task`.
- Designer handoffs are copied to `.softhouse/design/specs/` so the design record survives handoff rotation; dependents of a failed task are marked `blocked`; `.softhouse/` must be excluded from the project's formatter.
- **New optional skill `softhouse-program`**: an unattended driver above the pipeline — `program.json` contexts with dependencies, a gate register with agent-decidable and always-stop classes, a never-halt table, an exit/resume protocol with a repo-tracked LOCK and STOPPED sentinel, and scheduled-fire guidance. Ported from the one project that ran it for ~100 fires, with its costs stated.
- `softhouse-plan` carries the same schema (`protected`, `promotion`, `review_questions`, `isolation`, `brief`).

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
