# Softhouse field review — every pipeline under ~/ (2026-10-01)

This document gathers what seven months of real Softhouse runs across nine projects taught, so it can be folded back into the canonical skills. It is the input for the next canonical release (v2.1 → v2.7 + an optional `softhouse-program` skill).

Sources reviewed: the canonical repo (v2.1, 2026-07-20), the globally installed skills (`~/.claude/skills/softhouse*`, v2.6, 2026-09-24), and the `.softhouse/` state plus project-level skill forks in:

| Project | Stack / domain | Runs | Dates | Skill lineage | State size |
|---|---|---|---|---|---|
| asla-mn-migration/{odoo-asla, roadcba, delibero/k1, delibero/mvp, autocad-asla} | Odoo, aiogram bots, Python LLM pipelines | 12 total | 2026-03-31 → 06-01 | v1 (global, pre-repo) | tiny |
| gerege-chess | NestJS + SvelteKit monorepo, live prod, child users | 56 postmortems / 73 archives, 342 tasks | 2026-06-03 → 07-07 | v1 shared-tree variant; never adopted v2.0+ | patterns.md 318 KB |
| digital_coop_bank | Requirements docs → FastAPI backend (coop bank) | 26 runs, 156 tasks | 2026-07-20 → 08-09 | project fork (2026-07-20), doc-centric roles | patterns.md 82 KB, 10 briefs |
| gerege-nbfi (+ worktrees oh-gerege-tierd31, oh-gerege-ciaagrade) | Fineract Java → Go strangler port | ~100 unattended fires, tasks to T560 | 2026-08-17 → 09-06 (STOPPED), hand-driven to 09-13 | project fork + new `softhouse-program` | 1.3 GB; patterns 342 KB, gates.md 409 KB |
| negdi-payment-platform | Go payment processor, RLS, HSM, 5 React portals | 20 runs (13 backfilled, 6 real under v2.2–2.6, 1 in flight) | 2026-04-04 → 10-01 | global v2.6 (written from this project) | metrics.jsonl 19 lines, 50 acceptance logs |

## 1. Headline findings

1. **The repo is five minor versions behind what is installed.** Canonical is v2.1. The global `softhouse` skill is v2.6 (14 KB of additions written on 2026-09-24 from the NEGDi audit). The global `softhouse-plan` only received the v2.2 changes and is missing v2.4–2.6 planning rules (files_hint from acceptance grep, `protected`, `budget_tokens`, handoff-index lookup). `softhouse-uat` is unchanged since v2. First action: land v2.6 in the repo, re-sync `softhouse-plan`, then apply everything below.
2. **Four independent forks exist and none were merged back.** digital_coop_bank (doc-centric roles, briefs, text-invariant gate), gerege-nbfi (program driver, gate register, instruments), gerege-chess (shared-tree sequential mode, CX tooling), NEGDi (v2.2–2.6, now plus two un-codified mechanisms from WS4). Each fork solved a real problem the others then re-hit.
3. **The single root cause behind every recurring failure: lessons stayed prose.** gerege-chess recorded the redundant `aria-live` trap at least 14 times, the Postgres CHECK trap 4 times, the agent-crash recovery 5 times. delibero hit "stale model IDs in tests" 3 runs in a row. NEGDi recorded "tests rewrote source" 3 times. The lesson only stopped recurring where it became a check a reviewer runs (chess `ui-rules.test.ts`, NEGDi test-scope diff check, dcb `verify-docs.sh`).
4. **patterns.md is unbounded and became unreadable in every long-lived project.** 318 KB (chess, 91 KB of which is a post-pipeline dev journal), 342 KB (nbfi, with postmortems appended *after* the END marker from run 2 on), 82 KB (dcb). Evidence it was effectively unread: 5 of 263 chess handoffs mention it. v2.6 added `patterns-archive.md` but no size cap, archival trigger, or promotion rule.
5. **Zero rejections is not a success signal.** chess: 0 `reviewer_notes`, 0 retries in 342 tasks because every failure was "recovered in-tree" by the orchestrator. dcb: 2 rejections in 156 tasks. NEGDi backfilled runs claimed `first_attempt_rate: 1.0`; honest measurement under v2.2+ gave 0.33–0.62 on security work. The pipeline only produces a failure taxonomy when the reviewer executes acceptance and has a tag vocabulary.
6. **The highest-value mechanism, measured, is the blind independent review of money/security diffs.** NEGDi: 42 reviews, 17 FAIL, every FAIL a real defect that compiled and passed worker tests (RLS fail-open on empty tenant, merchant key minting `admin:*`, PAN in events, settlement opening a second OPEN batch). dcb ran a paired independent reviewer on *every* writer task and the same ledger defect that self-review had shipped twice was caught. Cost: 25–40% of a security run's tokens.
7. **Agent self-reports are unreliable everywhere.** Misreported baselines, "waiting on background test" while a build break sat in the tree, "landed" commits origin never saw (nbfi incident 2026-09-04), handoffs lost because the branch had no commit (dcb run 1, both level-0 tasks). Orchestrator re-verification from the tree, the diff, and origin is the only fix that held.

## 2. What each fork invented (port candidates)

### 2.1 digital_coop_bank — doc-centric pipeline
- **Briefs** (`.softhouse/<feature>-brief.md`): a per-run single source of truth committed to main *before* workers spawn so every worktree forks with it. Sections: standing facts, scope IN/OUT, canonical rename/value tables with exact locations, HELD lists ("these are not oversights"), security requirements the reviews will attack, gates to run, what the handoff must contain. Task descriptions become `READ <brief> IN FULL` plus a short delta. Solves the N-parallel-agents consistency problem.
- **Honesty rule**: every material claim tagged `[VERIFIED: <source>]` or `[UNVERIFIED]`; reviewer traces every VERIFIED to its source; "a confident invention is a defect". Handoff template gains `Sources` and `Unverified` sections. A fabricated provenance marker was caught once and ruled "worse than none".
- **Non-code role set**: `analyst`, `spec_writer`, `reviewer` (independent, opus, spawned fresh, never given the planning rationale), `verifier`. Rule: every writer task gets a paired reviewer; "when adding a task mid-run, add its reviewer too".
- **Reviewer mechanics** (generic tooling knowledge): read the upstream handoff with `git show <branch>:.softhouse/handoff/<run>/<id>.md` (a plain path read in another worktree fails silently and "approves nothing"); diff with three-dot `main...<branch>`; "if you find nothing, say what you checked"; findings as severity / location / what is wrong / fix.
- **Textual invariant gate with ratchet** (`verify-docs.sh` + `baseline.txt`): HARD counts must be 0; DRIFT counts may never exceed the committed baseline; `--baseline` requires a stated reason in the postmortem after enumerating the residual; exemptions by exact filename only, never by pattern; the reviewer proved the exemption by planting violations. The right UAT shape for non-runnable repos.
- **Policy → Apply split** for mass mechanical changes with judgment calls: a read-only run produces a derivation table the owner confirms ("6 anchor decisions instead of 312 conversions"), a second run applies it line by line by role, never global find-replace.
- **Multi-lens audit**: three auditors with disjoint lenses who do not read each other's work; orchestrator synthesizes from source, not by majority vote. Two lenses caught a disguised money-loss formula the third and the orchestrator missed.
- **Merge guards after a real incident**: a worker ran `git checkout -b` in the shared checkout and moved the orchestrator's HEAD; four merges landed on the wrong branch and `push origin main` was a no-op. Rules: worker preamble opens with `pwd` + `git rev-parse --show-toplevel`; "never run git against the shared checkout"; orchestrator asserts `git branch --show-current == main` before every merge; stage explicit paths, never `git add -A`, while workers are live (it committed two worktrees as gitlinks); "spawn in the same action that flips the task to in_progress".
- Smaller: resume may proceed when the tree is dirty only under `.softhouse/`; MICRO-FIX is "mechanical only, never logic, never a number"; dependents of a failed task are marked `blocked` with the blocking id; a dead review agent is never an approval; install new dependencies in the orchestrator's gate environment before trusting a gate run; scale check (a 140 KB doc exhausts a worker; split by section); apply/ratify tasks depend on the artifact reaching `approved`, not on the review having run; `.softhouse/handoff/` must be tracked (the README's advice to not commit it destroyed work).

### 2.2 gerege-nbfi — the program layer
- **`/softhouse-program`**: the loop above `/softhouse`. Removes the idle stop, never a check. Reads `program.json` (contexts with dependencies/status/slices, policy as data, gates_pending, history, incidents, in_flight, cursor); a first-match decision table (run active → resume; run terminal → close and fall through; READY context → plan + execute; READY-FOR-ANALYSIS → contract-independent slice; only user gates left → surface and exit); a 7-item plan checklist that auto-approves in place of the human "approve?"; a never-halt table (fail → retry opus → park; UAT red → park; oracle down → park vector work, keep analysis); an exit protocol (attest, truthful tasks.json, `STATE.json` per non-terminal task, `RESUME.md` rewritten every exit, push); `/softhouse` STEP 10 hands control back.
- **READY vs READY-FOR-ANALYSIS**: an open gate on a contract blocks work that *consumes* it, not work that produces knowledge. "An open gate must never mean an idle factory."
- **Gate register** (`gates.md`): human-decision log with an authoritative table rebuilt from `program.json` plus append-only prose. Classes that always stop (CUTOVER, CONTRACT, REGULATORY, ACTIVATION); everything else is agent-decidable with `chosen_by: agent` and owner veto (G-3 was decided by the agent on 08-20 and reversed by the owner on 10-01, cleanly). `gates-proposed-answers.md` holds standing answers classified LEGAL / ENGINEERING / RESERVED.
- **Fire wrapper** (`fire-program.sh`, launchd 6×/day + a cloud routine): `STOPPED` sentinel in the repo (a host-local `launchctl bootout` did not survive a reboot); repo-tracked `LOCK` whose freshness is the holder's push recency to origin, not a heartbeat (a live fire that never pushed its dispatch record lost 4 worker branches to the cloud fire); chain loop that stops on "no commits"; exit guard that rescues WIP, prunes worktrees, reconciles, stamps `RESUME.md` with a staleness banner if the driver failed to.
- **Instruments**: `repo-state-attest.sh` (differential before/after snapshot vs a declared writ, because `git status --porcelain` was empty after a re-inited repo), `check-branch-published.py` (tasks.json claims vs origin), `no-op-fire-streak.sh` (cross-fire watchdog: no-op streak, silence, padded advance), `rehydrate-check.sh` (terminal tasks never re-run; a rejected task names its successor), `ready-tasks.py --reconcile` (dependency resolution against run archives; a task sat falsely blocked for several fires without it), `review.sh` (merge review from the diff, not the claim).
- **Findings directory** (`findings/F-<date>-<slug>.md`): first-class measured observations with status, measurement table, rule and counter-rule. Rules that came out: "a brief must carry the map, not just the destination" (3 of 4 agent cap-deaths were navigation); split oracle-writing from grading; refuse what you cannot grade; control-test every instrument on a known positive; a measurement that did not happen must not look like zero (silent zero = exit 2).
- **Exit-code discipline**: 0 = verdict pass, 1 = mismatch, 2 = harness unusable, 3 = wrong interpreter, never a verdict; drivers read the probe line's presence then value, never the exit code alone. "A guard that only works when someone remembers to run it enforces nothing" (P-45, the program's most-cited lesson). "'Not found' is a statement about the search, never about the world" (P-66/70/104).
- **Costs recorded honestly**: harness code grew to 1.5× the ported behaviour (the driver raised this itself as gate G-20); ~5 days of zero-turn fires went undetected (expired OAuth, weekly limit); push-before-spawn stayed a paragraph and was missed twice by drivers who had read it; two `P-n` numbering series collided; the owner stopped the program on 2026-09-06 in favour of hand-driven OpenHands briefs.

### 2.3 negdi-payment-platform — v2.2–2.6 and what WS4 added
Mechanism-by-mechanism evidence from 6 real runs:

| Mechanism | Evidence | Still open |
|---|---|---|
| `Done when:` runnable line | 100% of tasks; exposed planner defects (self-contradictory line, literal key); a worker gamed a loose grep with an import alias → anchor regexes | lines grew to 5–7 commands; stack-dependent assertions could not run in a worktree |
| Evidence-based approval | 50 PASS logs; `acceptance_logs == approved` held every run | harness bugs cost a wave: exit code read after `\| tail`, `HEAD` inside a script resolving in the main repo, stale coverage file (fixed in v2.6 text) |
| Independent opus review | 42 reviews / 17 FAIL, all real | fails twice on the same task often; third attempt allowed twice under budget pressure |
| files_hint from acceptance grep | 0 merge conflicts across 30 branches (vs 2 before) | greps find symbols, not interfaces/handler mappings/seed data: ~a dozen stop-and-widen cycles in 5 runs |
| Stop-and-report (gate 7) | every stop was a real dependency; no self-widening collisions since | each costs one agent turn plus a resume |
| Wiring census | 44 → 39, never rose; no `unwired-library-code` since April | Go-specific; a constructor called only from another unwired constructor counts as wired |
| Budget 80% stop | pacing worked; user raised budget on every security run | formula under-sizes protected opus work ~2× (measured 320–507k per approved task incl. review vs 190k+80k quoted) |
| Escalation rule | fired in 4 runs and forced real changes each time | `independent-review-failed` fires every run *by design* and can never clear; gate-7 stops mis-tagged as `acceptance-not-runnable` |
| worker-context.md digest | 145 lines, pasted verbatim; prevented a known TS2307 on first try | must be hand-maintained; work size, not prompt, dominates token cost |
| handoff-index.tsv | 193 rows, grep-able | manual append decays: sweep appended 2 of 8 rows |
| 40-line handoffs | mostly | multi-attempt handoffs reach 57–84 lines |

Two mechanisms proven in WS4 (2026-10-01) that are not yet in any SKILL.md:
- **REVIEW QUESTIONS → REVIEW ANSWERS**: protected task descriptions carry the questions the reviewer will ask; the worker answers each with `file:line` before handoff; the reviewer verifies answers instead of discovering. First-attempt review pass went from 0.33–0.62 to 2/2.
- **Planning-time red result**: every `Done when:` is run at plan time and its red result recorded in the task ("grep → 0; lifecycle has 16 subtests"). A line that cannot run at fork time is impossible by construction. Plus an `orchestrator:` prefix for assertions that need the full stack, so workers skip them honestly.

Also: persisted assembled prompts under `briefs/{run}/{task}.md` (reproducible resumes; proves the cache prefix is byte-identical); `SCOPE SELF-CHECK (run first)` as the literal first line of a description; a "red compass" e2e test written first whose named subtests the run turns green (progress visible as 5→7→9→12 of 12); interim rebuild + gating e2e after the *first* protected merge; legacy suites before gating ones (a passing suite wedged the stack for the next); `uat.md` suites table with a "Who runs" column and advisory→gating promotion; orchestrator fixes in protected files go back to the same reviewer for a "delta PASS" (both such rounds found something); ratchet trio in CI (coverage, gosec, semgrep baselines may never rise); project `settings.json` denying `Write(.env*)` and `git push --force` behind the preamble; `bulletin_softhouse.go` shows an app generating `tasks.json` from a struct that predates v2.2, so the task schema should be published as a versioned JSON schema.

### 2.4 gerege-chess — the heaviest early user
- **Shared-tree sequential mode**: hoisted npm-workspace `node_modules` made worktrees impractical (full install per worktree). The project ran agents sequentially in the shared tree in dependency order, orchestrator re-running the gate before each commit. Canonical still assumes worktrees unconditionally.
- **`.plan.json` extras that kept 9-task runs at 0 rejects**: `spec` pointer with §-numbers ("tasks REFERENCE, never restate"), `notes_to_executor[]`, `out_of_scope[]`, per-task `acceptance_criteria[]`.
- **Design gate in practice** (used once, worked): T1 captured the design system first (16 `@dsCard` previews; specified missing tokens without touching CSS); T2 produced 3 mockups published as one Artifact via `<iframe srcdoc>` assembled by a script so the HTML never entered orchestrator context; the implementation plan (T3–T7) was written *after* approval and derived from what T2 invented; the cx_reviewer's mockup-fidelity check found 0 undocumented deviations. The design handoffs were later overwritten by the next run's T2 (flat handoff dir), so the spec design.md points at is gone.
- **CX tooling**: `ui/` primitives + `ui-rules.test.ts` (the one lesson that stopped recurring because it became a test) + `/gallery` + `npm run visual-review` (axe + ARIA tree + screenshots; "read report.md and the ARIA tree first, open screenshots only for sign-off, images are token-expensive"); "new critical/serious on a changed surface blocks, pre-existing baseline items are tracked".
- **Promotion gate by instinct**: "default-decision autonomy is not authority to ship an unreviewed redesign to real school children — deploy to TEST only, prod awaits the user's eyes." Canonical has no TEST→PROD field.
- **Agent-crash recovery**: on timeout/529/"stopped"/double completion → `git status`, run the gate on what is in the tree, finish the last ≤10 lines, write a recovery handoff; never re-spawn blindly. Recorded 5 times, never codified.
- **Codebase-map pass before planning**: "the feature was ~40% done; always ask whether a rudimentary version already ships". Same lesson in dcb ("scope the task to the gap, not the whole epic").
- Hygiene: `.softhouse/` must be in the formatter ignore list; absolute paths and `git -C` after a context compaction reset cwd; one deps-install task per run; the orchestrator runs the *build*, not only tests (test+typecheck miss duplicate declarations and ESM-in-CJS boot crashes); test_writer = "audit existing tests + fill gaps incl. the page-level mount gate, never duplicate" because coders now write substantial tests.
- Runtime-only defects that only live smoke caught: ESM import boot crash, provider `max_tokens` contract, null birth-year → adult inversion. Canonical's fallback "health 200 + one domain action" is the right instinct but was never run as a per-task gate.

### 2.5 asla (Mar–Jun) — where v2.0 came from
Agents ran sudo/nginx/certbot/DB init on a live host (→ executor routing); "build, deploy, verify" was given to a haiku agent (→ model floor); opus "over-delivered" and dependent simple tasks were collapsed into it; "for 2-line changes skip delegation, reserve agents for >10 lines of logic"; cross-project lessons were copied by hand between patterns files.

## 3. Consolidated rules worth promoting into canonical

**Planning**
1. Derive `files_hint` from the acceptance grep at plan time, then widen for every removed symbol (`grep -rln` incl. tests, mocks, adapters) and every interface change (its adapters). Record the planning-time red result in the task.
2. Every protected task carries REVIEW QUESTIONS; the worker answers them with `file:line`; the reviewer verifies.
3. Scout before planning: grep for an existing rudimentary version; scope the task to the gap.
4. Tasks reference a spec by §-pointer; the plan carries `notes_to_executor`, `out_of_scope`, and a brief committed to main before the first spawn.
5. Scale check: a worker's context is bounded; split by file/section/package before it blows out. One deps-install task per run. Policy → Apply split for mass mechanical changes.
6. Apply/ratify tasks depend on `approved`, not `done`. Add a reviewer when adding a task mid-run. Dependents of a failed task become `blocked`.
7. Model tier is not the quality lever; route opus by silent-failure risk, pay for the independent review, and size the budget from measured per-task cost including review.

**Worker prompting**
8. Fixed prompt layout (safety → digest → role → task) persisted per task under `briefs/`. First line of every description: `SCOPE SELF-CHECK (run first)`. Honesty tags on every material claim. Commit the handoff to the branch or the output is destroyed. `pwd` + `git rev-parse --show-toplevel` self-check; never run git against the shared checkout; no sub-agents.
9. Workers stop and report at a scope boundary; the orchestrator widens and resumes; a scope stop is not a failure and does not trigger the retry model upgrade.

**Verification and review**
10. The orchestrator executes the `Done when:` line itself (pipefail, exit codes before `| tail`, merge-base comparisons, explicit refs) and runs the build, not only tests. No evidence log ending `RESULT: PASS`, no approval.
11. Blind independent review for money/security/protected diffs: diff + acceptance line + security requirements only; re-derive every money computation; "state what you checked"; delta review of any orchestrator fix in a protected file; a dead reviewer is never an approval.
12. Read the upstream handoff via `git show <branch>:<path>`; diff with three-dot. Never trust a worker's self-reported gate.
13. Anchor acceptance regexes. For safety invariants the bar is "trace every path and prove the test would fail if violated"; for security the bar is "the reviewer wrote a working exploit attempt and it failed"; for concurrency, mutation-test the guard.
14. Full-corpus seam reconciliation at the orchestrator after any parallel split; per-slice reviews cannot see seams (missed ops, half-applied renames, stale cross-doc claims).
15. Install new dependencies in the orchestrator's gate environment before trusting a gate run.

**Merge and git**
16. Push before every spawn (worktrees fork from the pushed head). Assert `git branch --show-current == main` before every merge. Stage explicit paths while workers are live. Never `--theirs/--ours` on source. Waves ≤4 agents; one bootstrap-wiring task per wave, run last by the orchestrator. Record claims only after `check-branch-published` confirms origin has them.

**UAT, promotion, design**
17. `uat.md` suites with a "Who runs" column and advisory→gating promotion; legacy suites before gating ones; rebuild between; interim gating e2e after the first protected merge; a per-task live smoke for anything that compiles but can fail at boot or on a provider contract.
18. A `promotion: test | prod` field; child-facing, money, and outward surfaces stop at TEST behind an `executor: user` decision.
19. Design: bootstrap task captures the design system if `.softhouse/design/` is missing; two-phase plan (design run → gate → then plan implementation); multi-mockup Artifact via `<iframe srcdoc>` assembled by script; designer handoffs copied to `design/specs/` so they survive handoff rotation.

**Learning loop**
20. Bound `patterns.md` structurally: ≤150 lines of HARD GATES + constraints + environment + codebase facts; postmortems go to `patterns-archive.md`; anything not produced by STEP 8 goes to a journal. STEP 8 may promote at most 3 one-line rules and each must name the check that enforces it. A rule seen in ≥2 postmortems without an enforcing check is flagged in the plan summary as "recurring lesson, no gate". STEP 9 rejects an over-cap file the way it rejects a plan without `Done when:`.
21. Script STEP 9: append `handoff-index.tsv` rows and archive the run from `tasks.json`; manual appends decay.
22. Tags: add `files-hint-incomplete` (gate-7 stop) and `review-caught-defect`; exclude the latter from the escalation trigger or give every escalation a "resolved when".
23. Metrics: adopt the extra keys NEGDi's orchestrator invented (`uat_suites`, `tokens_by_role`, `tokens_review_agents`, `orchestrator_repairs`, `pipeline_versions`, `backfilled`); replace `wall_clock_min` with `active_min`; count review tokens in `tokens_per_approved_task`.

**Execution modes and autonomy**
24. Shared-tree sequential mode for hoisted monorepos (run-level `isolation`), keeping the safety preamble.
25. Agent-crash recovery procedure in STEP 3 (see 2.4).
26. Optional `softhouse-program` skill with `program.json`, gate register, exit/resume protocol, fire wrapper skeleton, STOPPED/LOCK semantics, and the watchdog instruments; push-before-spawn as a wrapper step, not a paragraph.

## 4. Templates and scripts to ship in `templates/`
- `worker-context.template.md` (from NEGDi's 145-line digest: what the repo is / environment and safety / how to read code / scoped verify commands / layout table / conventions / schema map / test data / numbered hard gates / handoff template).
- `brief.template.md` (dcb), `gates.template.md` and `program.json` schema (nbfi), `protected-paths.txt` with its rules header, `uat.template.md` with the suites table.
- `scripts/protected-paths-touched.sh` (as-is, test-file pattern parameterized), `scripts/wiring-census.sh` (constructor pattern per language), `scripts/verify-docs.sh` ratchet skeleton, `scripts/handoff-index-append.sh`, `scripts/check-branch-published.py`, `scripts/repo-state-attest.sh`.
- A versioned JSON schema for `tasks.json` (fields observed in practice: top-level `budget_tokens`, `budget_note`, `tokens_spent`, `escalations_applied`; per task `protected`, `evidence`, `failure_tags`, `reviewer_notes`, `tokens_spent`, `review_tokens`, `design`, `promotion`, `acceptance_criteria`, `notes_to_executor`, `out_of_scope`).

## 5. Project-specific, do not port
Mongolian money/name/timezone non-negotiables; dcb's five legal questions and `run_pipeline.py` budget warning; nbfi's PIN/capabilities/vector schemas, `conformance.sh` guards, `ledgerguard`/`reachguard`, capture rigs, oracle image; NEGDi's Go constructor regexes and 31 protected globs; chess's Svelte/axe tooling specifics.

## 6. Housekeeping observed in the field (for the owners of those projects)
- gerege-chess: move patterns.md lines 1793–3114 to `docs/journal.md`, lines 272–1792 to `patterns-archive.md`, convert "Known traps" to HARD GATES with enforcing commands, create `worker-context.md`.
- gerege-nbfi: `STOPPED` since 09-06; `RESUME.md` frozen with T555–T560 never run; T512's deliverable lost; gates G-4, G-5, G-8, G-12, G-23 open; launchd plist cadence drifted from the documented 2×/day to 6×/day; the cloud routine may still tick and refuse.
- digital_coop_bank: 23 of 26 run archives still say `executing`; 19 verifier tasks left `pending` though the work was done inline; backlog is 19 prose paragraphs never pruned; the skill fork still says coder is inactive while 21 coder tasks ran.
- negdi-payment-platform: handoff-index behind by most of the sweep run; WS4 in flight at 68% of budget.
