# Softhouse

**A multi-agent development pipeline for [Claude Code](https://claude.com/claude-code).**

Softhouse turns a one-line requirement into a planned, parallelized, reviewed, and merged change set. It plans a task graph, fans the work out to isolated git-worktree agents, gates new UI behind a human design approval, reviews every branch against a concrete checklist, verifies against your project's UAT definition, merges, and writes down what it learned for the next run.

It ships as three Claude Code skills — no dependencies, no runtime, no service to host. Just Markdown that Claude Code executes.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-2.1-blue)

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

## Why this exists

Handing a large requirement to a single agent produces one long serial session where a mistake in step 2 quietly poisons step 9. Softhouse breaks that up. The design principles it encodes came out of running it against live production systems, and each one exists because something went wrong without it:

**Executor routing is a safety boundary, not a label.** Every task declares who performs it. `agent` tasks go to an isolated worktree worker and must be repo-contained and verifiable in a throwaway test stack. `orchestrator` tasks — nginx configs, crontab, `.env` secrets, live-DB mutations, deploys, `git push` — are performed inline by the main session and are *never* handed to a worker. `user` tasks are decisions only a product owner can make: governance sign-off, spend, scheduling a restart window. A worker agent cannot reach the live system because the plan never routes it there.

**Every worker prompt carries an environment-safety preamble.** It names the live deployment on the host, gives the isolated test-stack command with a unique project name, and requires the worker to end its report with the literal line `live stack untouched`. A worker that can't say that truthfully has told you something important.

**Workers fork from current main, and merges re-check it.** Main is committed and pushed before any batch launches, and review re-runs `git merge-base` before merging. Without this, a stale fork's diff looks like it deletes recent work — and a three-way merge silently preserves disjoint files but not co-edited ones.

**Design happens before code.** New user-facing screens get a `designer` agent that produces self-contained HTML mockups from your project's design system, using real domain data and covering empty/error/loading states. The orchestrator publishes the mockup for you to look at in a browser; you approve, revise, or skip. The approved mockup then becomes the coder's binding acceptance criterion. Rejecting a mockup costs minutes. Rejecting implemented code costs a full agent cycle.

**UI work is scored, not vibe-checked.** Every UI task carries an explicit CX checklist — loading, empty, and error states; responsive at 375/768/1280; keyboard reachability; ARIA and semantic HTML; contrast; action feedback; form validation; no raw errors leaking to users; consistent design tokens. A reviewer scores it against the items applicable to your UI paradigm, and every skipped item needs a stated justification. Silence is not a justification. Below 70% is a rejection.

**Runs learn from each other.** Each run appends a postmortem to `.softhouse/patterns.md` — what worked, what got caught in review, codebase facts discovered, planning advice — and archives its state to `.softhouse/runs/`. Gaps a worker noticed but couldn't fix land in a `backlog` array that the *next* run's planner reads as input. Nothing found mid-run gets lost.

**Everything is resumable.** All state lives in `.softhouse/tasks.json`. Any interruption — context limit, crash, you closing the laptop — resumes with `/softhouse resume`.

## How a run flows

```
STEP 0  Pre-flight      clean tree check; read CLAUDE.md, patterns.md, prior backlog;
                        identify environment-safety facts for this host
STEP 2  Plan            build the task graph; route each task by executor;
                        show it as a table; WAIT for your approval
STEP 3  Execute         push main, then fan out worktree agents by dependency level;
                        orchestrator tasks run inline in parallel
STEP 5  Review          scope check, fork-freshness check, non-negotiables scan,
                        CX score → APPROVED / MICRO-FIX / REJECTED (one retry, model upgraded)
   5b   Design gate     publish mockup → you approve/revise/skip → inject into coder task
  5.5   UAT             per-project, from .softhouse/uat.md; must PASS to complete
STEP 6  Merge           --no-ff in dependency order, batched integration tests, push per batch
  6.5   DesignSync      best-effort component-library sync (skippable, never a gate)
STEP 7  Integration     full suite on merged main, clean state
STEP 8  PostMortem      append lessons to patterns.md
STEP 9  Cleanup         archive run, reset state, prune worktrees/branches, final push
```

## Per-project state

Softhouse keeps its state in a `.softhouse/` directory inside the repo you're working on — not in this repo:

```
.softhouse/
  tasks.json           # current run state; idle between runs
  patterns.md          # learned patterns, appended by each postmortem
  uat.md               # your project's UAT definition (see templates/)
  handoff/<run_id>/    # worker handoff files, namespaced per run
  runs/<run_id>.json   # archived runs — carries the backlog forward
  design/
    design.md          # design rules + which claude.ai design project to sync to
    tokens.html        # token preview
    components/        # reusable component previews (@dsCard annotated)
    mockups/           # per-task screen mockups
```

Starter templates for `patterns.md`, `uat.md`, and `design/design.md` are in [`templates/`](templates/). Copy the ones you need:

```bash
mkdir -p .softhouse && cp path/to/claude-softhouse/templates/* .softhouse/
```

Only `patterns.md`, `uat.md`, and `design/` are worth committing in your project — the rest is run state.

## Adapting it to your project

Softhouse is deliberately project-agnostic; it reads your conventions rather than imposing its own.

- **`CLAUDE.md`** — your project context file. Softhouse reads it in pre-flight and greps diffs against any "non-negotiables" you declare there. Put your live-vs-test topology here; it's what makes executor routing correct.
- **`.softhouse/uat.md`** — how to verify against a real system. Without it, `softhouse-uat` falls back to a generic isolated-suite + health-check + page-fetch check and tells you to write one.
- **`target` values** — the area labels in the task graph (`backend`, `frontend`, `api`, `ops`, `ci`, …). Rename them to match how your project is actually divided.
- **Test stack command** — the safety preamble's isolated-verification command is a docker-compose example. Adapt it to your harness; the requirement is that it's *isolated and uniquely named*, not that it's Docker.
- **Model routing** — roles default to Sonnet, with Haiku for trivial mechanical tasks and Opus for architecture, security, intricate refactors, and any retry.

## Requirements

Claude Code, and a git repository. That's the whole list. The design gate additionally uses the Artifact tool, and the optional DesignSync step needs claude.ai design scopes — both degrade gracefully when unavailable.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how the skills are structured and what makes a good change. The most valuable contributions are hardening rules learned from real runs: if a pipeline step burned you, the fix probably belongs in the skill.

## License

MIT — see [LICENSE](LICENSE).
