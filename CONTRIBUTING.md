# Contributing to Softhouse

Thanks for your interest. Softhouse is prompt engineering, not code — every skill is a single Markdown file that Claude Code reads and executes. That makes contributing unusually approachable, and it also means changes need a different kind of care than a normal pull request.

## What makes a valuable contribution

The best contributions are **hardening rules learned from real runs**. Nearly every rule in the current pipeline exists because something went wrong without it: an agent forked from a stale main and its diff looked destructive, a worker restarted the live compose project, a mockup got approved and the implementation quietly drifted from it. If a step burned you, the fix probably belongs in the skill.

When you propose a rule, say what it prevents. "Add a merge-base check before merging" is a change; "a stale-fork branch's three-way merge silently drops co-edited files, so review must re-check merge-base" is a change someone can evaluate.

Also welcome: project templates for stacks not yet covered, clearer wording where the current phrasing is ambiguous to a model, and fixes for genuine contradictions between the three skills.

## Repository layout

```
skills/
  softhouse/SKILL.md        # the full pipeline (steps 0–9)
  softhouse-plan/SKILL.md   # planning only (steps 0–2)
  softhouse-uat/SKILL.md    # UAT execution
templates/                  # starter files for a consuming project's .softhouse/
install.sh                  # copies skills/* into ~/.claude/skills/
```

## Rules for editing skills

**Keep the plan schema synchronized.** `softhouse` STEP 2 and `softhouse-plan` STEP 2 define the same task-object schema and the same planning rules. A plan produced by `softhouse-plan` must execute unmodified under `/softhouse resume`. If you change the schema in one, change it in both, and check that the field is actually consumed somewhere downstream.

**Never weaken the safety boundaries.** Three things are load-bearing and a PR that erodes them will be declined:

- Host-level and live-production work stays `executor: "orchestrator"`. Worker agents must never be routed to nginx, crontab, secrets, live databases, deploys, or `git push`.
- The environment-safety preamble stays mandatory in every worker prompt.
- Isolated verification stays uniquely named, so a test stack can never collide with a live one.

If your change makes one of these more permissive, the PR needs to explain what replaces the protection.

**Write for a model, not a human skimmer.** Prefer explicit imperatives over implication. State the failure mode inline where the rule appears — a model following step 5 shouldn't have to remember why step 3 mattered. Concrete commands beat descriptions of commands. Where a rule has an exception, spell the exception out; a model will otherwise invent one.

**Keep it project-agnostic.** No hardcoded hostnames, project names, credentials, or paths from your own infrastructure. Anything site-specific belongs in the consuming project's `CLAUDE.md` or `.softhouse/`, and the skill should read it from there. Examples are fine; examples wearing a real production hostname are not.

**Version material changes.** New stages, schema changes, or new safety rules bump the version and get an entry in [CHANGELOG.md](CHANGELOG.md) plus the version note at the top of the affected `SKILL.md`. Wording and clarity fixes don't need a bump.

## Testing a change

There's no test suite — the way to validate a change is to run it.

1. Install your modified skills: `./install.sh`
2. Run the pipeline against a real (ideally non-critical) project: `/softhouse-plan <some requirement>`, inspect the graph, then `/softhouse resume`.
3. In the PR, describe what you ran it against and what the run produced — especially the postmortem section, since that's where pipeline problems surface.

For changes to `softhouse-plan` alone, a plan-only run is sufficient evidence: it never spawns agents or modifies source.

## Pull requests

Keep them focused — one rule or one stage per PR is much easier to evaluate than a broad rewrite. In the description, cover what changed, what failure it prevents, and what you ran it against. If the change affects both `softhouse` and `softhouse-plan`, confirm you updated both.

By contributing, you agree your contributions are licensed under the MIT License.
