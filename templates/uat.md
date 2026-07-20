# UAT config — <project>

Read by `/softhouse-uat` and by STEP 5.5 of `/softhouse`. Without this file both fall back to a generic check (isolated suite + health endpoint + page fetch), which is weaker than anything you'd write here.

## Pre-flight

Must succeed before any suite runs.

```bash
curl -sf https://<host>/health          # expect 200
```

## Deploy / refresh

How to bring the system under test current. **Orchestrator-only** — a worker agent never deploys. Mark it user-scheduled if it is disruptive.

```bash
git pull && docker compose up -d --build
```

## Suites

Named suites and their exact commands. Suite names are what `/softhouse-uat <suite>` matches on.

- **api**: `docker compose -p <proj>_uat -f docker-compose.test.yml run --rm test pytest tests/api/`
- **pages**: `npx playwright test uat/pages.spec.ts --project=uat --reporter=list`
- **visual**: `npx playwright test uat/visual-regression.spec.ts --project=uat --reporter=list`

## Pass criteria

- All suites green.
- No `undefined`, `NaN`, or stack traces in any fetched page.
- <any project-specific gate>

## Visual baseline updates

Only run after the user confirms failures are intentional.

```bash
npx playwright test uat/visual-regression.spec.ts --update-snapshots
```

## Environment

Variables the suites need: `BASE_URL`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`, …
Note where the values come from — never inline real credentials in this file.

## Evidence

Where reports and screenshots land: `<path>`
