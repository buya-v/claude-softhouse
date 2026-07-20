# Design system — <project>

Read by `designer` agents before they produce any mockup, and by `cx_reviewer` agents when scoring implementation fidelity. Designers must reuse what is declared here; a new token or component requires stated justification in the handoff.

## UI paradigm

State what a coder can actually build, because it bounds what a designer may propose.

- e.g. Server-rendered Jinja templates + htmx + vanilla CSS. **No JS framework.** No client-side routing, no build step.
- e.g. React + Tailwind SPA; component library at `src/components/`.

Consequences for design: which CX checklist items apply at all. A server-rendered app has no client loading skeletons or toast layer; a SPA has both. Say so here so N/A justifications are consistent across runs.

## Tokens

The source of truth for tokens — point at the real file, don't duplicate values that will drift.

- **Defined in**: `<path to your CSS variables / theme file>`
- **Preview**: `.softhouse/design/tokens.html`

Cover: color (surface, text, primary, semantic states), type scale, spacing scale, radii, shadows, breakpoints.

## Breakpoints

Mockups must demonstrate behavior at all three: **375px** (mobile), **768px** (tablet), **1280px+** (desktop).

## Components

Reusable components live in `.softhouse/design/components/<name>.html`. Each preview file's **first line** must be:

```html
<!-- @dsCard group="<Group>" -->
```

The group name organizes the component in the design-system pane. Keep groups stable — renaming one re-shuffles the library.

## Design rules

Project-specific constraints beyond the CX checklist.

- One primary action per view.
- WCAG AA contrast (4.5:1 body text, 3:1 large text and UI boundaries).
- Spacing on the project scale — no arbitrary pixel values.
- <e.g. dark mode is required / not supported>
- <e.g. all dates render in the user's locale via the `fmt_date` filter>

## DesignSync target

Used by STEP 6.5 to sync component previews to claude.ai/design. Optional — omit to skip the sync.

- **Project name**: `<claude.ai design project name>`
- **Project ID**: `<id, once known>`
