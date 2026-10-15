# Softhouse

**A multi-agent development pipeline for [Claude Code](https://claude.com/claude-code).**

Softhouse turns a one-line requirement into a planned, parallelized, reviewed, and merged change set. It plans a task graph, fans the work out to isolated git-worktree agents, gates new UI behind a human design approval, reviews every branch against a concrete checklist, verifies against your project's UAT definition, merges, and writes down what it learned for the next run.

It ships as three Claude Code skills plus an optional fourth for unattended multi-run programs — no dependencies, no runtime, no service to host. Just Markdown that Claude Code executes.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-2.10-blue)

---

## Quick start

```bash
git clone https://github.com/buya-v/claude-softhouse.git
cd claude-softhouse
./install.sh              # copies skills to ~/.claude/skills/
```

Then, in a Claude Code session inside your project:

```
/softhouse-plan add a CSV export button to the reports page
```

Review the task graph it prints. When it looks right:

```
/softhouse resume
```

That's it. For the full pipeline in one shot, skip the plan step and run `/softhouse <requirement>` directly.

## The three skills

| Skill | Command | What it does |
|-------|---------|--------------|
| [`softhouse`](skills/softhouse/SKILL.md) | `/softhouse <requirement>` | The full 9-step pipeline: plan → design gate → parallel execution → review → UAT → merge → postmortem → cleanup. `/softhouse resume` continues an interrupted run. |
| [`softhouse-plan`](skills/softhouse-plan/SKILL.md) | `/softhouse-plan <requirement>` | Planning only (steps 0–2). Produces a task graph you can inspect and edit before committing to execution. Never spawns agents or touches source code. |
| [`softhouse-uat`](skills/softhouse-uat/SKILL.md) | `/softhouse-uat [suite]` | Runs your project's UAT suite, resolved from `.softhouse/uat.md` with sensible fallbacks. |
| [`softhouse-program`](skills/softhouse-program/SKILL.md) | `/softhouse-program` | Optional. Drives a program of bounded contexts unattended, one context per invocation, parking blocked work and recording human decisions in a gate register. For long, well-specified migrations with a mechanical oracle. |

## Why this exists

Handing a large requirement to a single agent produces one long serial session where a mistake in step 2 quietly poisons step 9. Softhouse breaks that up. The design principles it encodes came out of running it against live production systems, and each one exists because something went wrong without it:

**Executor routing is a safety boundary, not a label.** Every task declares who performs it. `agent` tasks go to an isolated worktree worker and must be repo-contained and verifiable in a throwaway test stack. `orchestrator` tasks — nginx configs, crontab, `.env` secrets, live-DB mutations, deploys, `git push` — are performed inline by the main session and are *never* handed to a worker. `user` tasks are decisions only a product owner can make: governance sign-off, spend, scheduling a restart window. A worker agent cannot reach the live system because the plan never routes it there.

**Every worker prompt carries an environment-safety preamble.** It names the live deployment on the host, gives the isolated test-stack command with a unique project name, and requires the worker to end its report with the literal line `live stack untouched`. A worker that can't say that truthfully has told you something important.

**Workers fork from current main, and merges re-check it.** Main is committed and pushed before any batch launches, and review re-runs `git merge-base` before merging. Without this, a stale fork's diff looks like it deletes recent work — and a three-way merge silently preserves disjoint files but not co-edited ones.

**Design happens before code.** New user-facing screens get a `designer` agent that produces self-contained HTML mockups from your project's design system, using real domain data and covering empty/error/loading states. The orchestrator publishes the mockup for you to look at in a browser; you approve, revise, or skip. The approved mockup then becomes the coder's binding acceptance criterion. Rejecting a mockup costs minutes. Rejecting implemented code costs a full agent cycle.

**UI work is scored, not vibe-checked.** Every UI task carries an explicit CX checklist — loading, empty, and error states; responsive at 375/768/1280; keyboard reachability; ARIA and semantic HTML; contrast; action feedback; form validation; no raw errors leaking to users; consistent design tokens. A reviewer scores it against the items applicable to your UI paradigm, and every skipped item needs a stated justification. Silence is not a justification. Below 70% is a rejection.

**Runs learn from each other.** Each run appends a postmortem to `.softhouse/patterns.md` — what worked, what got caught in review, codebase facts discovered, planning advice — and archives its state to `.softhouse/runs/`. Gaps a worker noticed but couldn't fix land in a `backlog` array that the *next* run's planner reads as input. Nothing found mid-run gets lost.

**Everything is resumable.** All state lives in `.softhouse/tasks.json`. Any interruption — context limit, crash, you closing the laptop — resumes with `/softhouse resume`.

**Each project pins a pipeline version.** Softhouse installs once per machine and is shared by every project on it, so editing it would otherwise change how all of them run at once. Each project commits a `.softhouse/pipeline.json` pin that pre-flight checks: a minor drift warns and re-pins, a major drift (schema loss, stage set, or a safety boundary) stops the run until you adopt it, and a run already in progress is never continued under a different version. Vendoring a copy of the skill into a repo does *not* work as an alternative — Claude Code resolves same-named skills enterprise → personal → project, so a personal skill overrides a project one.

## How a run flows

```
STEP 0  Pre-flight      clean tree check; read CLAUDE.md, patterns.md (+archive), prior backlog,
                        metrics.jsonl (escalation rule: a failure tag seen in 2 of the last 3
                        runs forces a changed approach); protected paths; wiring census;
                        token budget; environment-safety facts for this host
STEP 2  Plan            build the task graph; route each task by executor; every task ends
                        with a runnable "Done when:"; files_hint derived from that grep;
                        probe every outside source the code will call and commit its real
                        response as the only fixture; plan the live check; show it as a
                        table; WAIT for your approval
STEP 3  Execute         push main, then fan out worktree agents by dependency level with a
                        fixed, cache-friendly prompt (safety → worker-context digest → role →
                        task) persisted under briefs/; workers stop-and-report at a scope
                        boundary; crashed agents are recovered from the tree, never re-spawned
                        blindly; shared-sequential mode for repos where worktrees don't work
STEP 5  Review          scope check, fork-freshness check, non-negotiables scan, the
                        orchestrator EXECUTES the acceptance line and stores evidence,
                        type gate against the run's baseline, invented-fixture and
                        swallowed-error scans, a real test case in any language,
                        blind independent review for protected/security diffs that verifies
                        the worker's review answers, CX score
                        → APPROVED / MICRO-FIX / REJECTED (one retry, prompt must change)
   5b   Design gate     publish mockup → you approve/revise/skip → inject into coder task
  5.5   UAT             per-project, from .softhouse/uat.md, else the planned live check;
                        project venv, setup in its own process group, stopped afterwards;
                        must PASS to complete; "verified" only if it ran against the
                        running system; promotion: "test" work stops at TEST
STEP 6  Merge           secret scan, then --no-ff in dependency order, batched integration
                        tests, push per batch; environment faults halt without a retry
  6.5   DesignSync      best-effort component-library sync (skippable, never a gate)
STEP 7  Integration     wiring census may not have risen; full suite on merged main
STEP 8  PostMortem      postmortem to patterns-archive.md; promote ≤3 rules to patterns.md,
                        each naming its enforcing check; one line to metrics.jsonl
STEP 9  Cleanup         patterns.md ≤150 lines or the run does not complete; sync digest,
                        append handoff-index, archive run, reset state, prune, final push
                        report COMPLETED — VERIFIED or — UNVERIFIED, with the assumptions
                        the run never checked
```

## Per-project state

Softhouse keeps its state in a `.softhouse/` directory inside the repo you're working on — not in this repo:

```
.softhouse/
  pipeline.json        # pinned pipeline version — commit it
  tasks.json           # current run state; idle between runs
  patterns.md          # HARD GATES + constraints + promoted rules; capped at 150 lines
  patterns-archive.md  # every postmortem; grepped by STEP 0, never read whole
  briefs/<run_id>/     # the assembled prompt per task, plus brief.md when tasks share a spec
  metrics.jsonl        # one JSON line per run; drives the escalation rule
  worker-context.md    # ≤200-line digest workers read instead of CLAUDE.md (see templates/)
  protected-paths.txt  # globs that force the independent review (see templates/)
  handoff-index.tsv    # one row per past task; the planner greps it for similar work
  uat.md               # your project's UAT definition (see templates/)
  handoff/<run_id>/    # worker handoff files, namespaced per run — COMMIT these
  uat-evidence/<run_id>/ # acceptance logs ending RESULT: PASS|FAIL — COMMIT these
  runs/<run_id>.json   # archived runs — carries the backlog forward
  queue/               # plans waiting to run
  design/
    design.md          # design rules + which claude.ai design project to sync to
    tokens.html        # token preview
    components/        # reusable component previews (@dsCard annotated)
    mockups/           # per-task screen mockups
    specs/             # designer handoffs, copied here so they survive handoff rotation
  program.json         # only with softhouse-program: contexts, gates, history
  gates.md             # only with softhouse-program: the human-decision register
```

Starter templates for `patterns.md`, `uat.md`, `worker-context.md`, `protected-paths.txt`, `brief.md`, and `design/design.md` are in [`templates/`](templates/). The helper scripts the skill calls (`wiring-census.sh`, `protected-paths-touched.sh`, `handoff-index-append.sh`, and since 2.9 `source-probe.sh`, `fixture-provenance.sh`, `uat-setup.sh`, `swallowed-errors.sh`, `secret-scan.sh`) are in [`scripts/`](scripts/) and belong under `scripts/ci/` in your project; `scripts/tests/run.sh` tests them without network access:

```bash
mkdir -p .softhouse scripts/ci
cp path/to/claude-softhouse/templates/* .softhouse/
cp path/to/claude-softhouse/scripts/*.sh scripts/ci/
```

Commit all of `.softhouse/`. Handoffs, run archives, evidence logs, metrics and the handoff index are what the next run learns from; a project that kept handoffs out of git lost two tasks' output when their worktrees were pruned.

## Adapting it to your project

Softhouse is deliberately project-agnostic; it reads your conventions rather than imposing its own.

- **`CLAUDE.md`** — your project context file. Softhouse reads it in pre-flight and greps diffs against any "non-negotiables" you declare there. Put your live-vs-test topology here; it's what makes executor routing correct.
- **`.softhouse/uat.md`** — how to verify against a real system. Without it, `softhouse-uat` falls back to a generic isolated-suite + health-check + page-fetch check and tells you to write one.
- **`target` values** — the area labels in the task graph (`backend`, `frontend`, `api`, `ops`, `ci`, …). Rename them to match how your project is actually divided.
- **Test stack command** — the safety preamble's isolated-verification command is a docker-compose example. Adapt it to your harness; the requirement is that it's *isolated and uniquely named*, not that it's Docker.
- **Model routing** — roles default to Sonnet, with Haiku for trivial mechanical tasks (never on a protected path) and Opus for tasks whose failure is silent: security, tenancy, crypto, money state machines, cross-package refactors, and any retry. The model is not the quality lever; the executed acceptance line and the independent review are.
- **`.softhouse/worker-context.md`** — the digest workers actually read. Keep it under 200 lines and in sync with CLAUDE.md; the pipeline reminds you at cleanup.
- **Isolation mode** — worktrees by default. If your repo makes a fresh worktree expensive (hoisted monorepo installs), say so in `patterns.md` and the plan uses `shared-sequential`: one agent at a time in the shared tree, the orchestrator re-running the gate before each commit.
- **Promotion** — if you have a TEST environment distinct from production, declare it in `patterns.md`; tasks marked `promotion: "test"` stop there and production is your call.

## Requirements

Claude Code, and a git repository. That's the whole list. The design gate additionally uses the Artifact tool, and the optional DesignSync step needs claude.ai design scopes — both degrade gracefully when unavailable.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how the skills are structured and what makes a good change. The most valuable contributions are hardening rules learned from real runs: if a pipeline step burned you, the fix probably belongs in the skill.

## License

MIT — see [LICENSE](LICENSE).
