# Changelog

All notable changes to the Softhouse pipeline. Versions refer to the pipeline itself, which all three skills share.

## [2.2] — 2026-07-20 — MINOR

Added **per-project pipeline version pinning**. No task-schema or stage changes, so adopting this is safe and automatic.

- New `.softhouse/pipeline.json` (committed project config) pins the pipeline version a project runs under.
- **STEP 0 version check** in both `/softhouse` and `/softhouse-plan`: missing pin → created silently; MINOR drift → warn, list changes, re-pin, continue; MAJOR drift → **stop** and require explicit user adoption; pin newer than the installed skill → warn and ask, since running an old pipeline over new-schema state can corrupt `tasks.json`.
- A run already in progress under a different version is never continued under the new one — mid-run schema drift is the most damaging case.
- `tasks.json` and every `runs/{run_id}.json` archive now carry `pipeline_version`, making each run self-describing; postmortem advice from a different version is treated as version-qualified.
- Documented **MAJOR vs MINOR semantics**: MAJOR = task schema, stage set, or a safety boundary changed; MINOR = wording, checklists, defaults, model routing.

Rationale: Softhouse is installed once globally and shared by every project on a host, and Claude Code resolves same-named skills enterprise → personal → project — *personal overrides project*, so vendoring a copy into a repo does **not** shadow the global one. Pinning by version marker is the only mechanism that actually works; without it, editing the global skill silently changes how every project runs.

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
