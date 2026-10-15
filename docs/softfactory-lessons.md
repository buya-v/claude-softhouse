# Softfactory lessons in Softhouse 2.9–2.10

Softhouse's mechanisms were ported into the [softfactory CLI](https://github.com/buya-v/softfactory-cli) in its 5.4–6.3 releases. Running it on a real project — a FastAPI service for Bank of Mongolia exchange rates, built with Gemini workers — then taught softfactory lessons Softhouse did not have. This table is where each one landed. The founding failure: the plan scraped `https://www.mongolbank.mn/en/rates`, which answers HTTP 200 with a "404 - Page Not Found" page; workers invented HTML fixtures, 127 tests passed against them, and the run reported success.

| Softhouse | Rule | Where | Enforced by | From softfactory |
| --- | --- | --- | --- | --- |
| 2.9 | Probe every outside source before any worker launches; a bad one rejects the plan | STEP 2 step 1b, softhouse-plan | `scripts/source-probe.sh` | 6.4.0 #82, #93, #94; 6.4.6 #102 (placeholders, duplicates) |
| 2.9 | The orchestrator owns fixtures for a source; no task declares one | STEP 2, 3, 5 4g | `scripts/fixture-provenance.sh` | #83; 6.4.6 #102 (the five-attempt deadlock) |
| 2.9 | A planned live check when there is no uat.md; test-suite probes do not count | STEP 2, 5.5, softhouse-uat | `tasks.json` `uat` | #84, #89 |
| 2.9 | Verified is separate from completed | STEP 5.5, 8, 9 | `verified` in tasks.json and metrics | #86 |
| 2.9 | Unverified assumptions in the postmortem and the report | STEP 8, 9 | report section | #86 |
| 2.9.1 | Python live checks in a project venv, never the host python | STEP 5.5, softhouse-uat | `scripts/uat-setup.sh venv` | 6.4.4 #99 |
| 2.9.1 | Setup in its own process group, output to a file, stopped afterwards; a busy port stops the check | STEP 5.5, softhouse-uat | `scripts/uat-setup.sh start/stop/port-free` | 6.4.5 #100, #101 |
| 2.9.1 | Environment faults halt without spending a retry | Error Handling, STEP 6 | `status: "halted"`, tag `environment-fault` | 6.0; the mongolbank `.pyc` merge halt |
| 2.10 | Swallowed-error scan | STEP 5 4h | `scripts/swallowed-errors.sh` | 6.4.0 #85 |
| 2.10 | Secret scan on values, not names | STEP 6 0b, STEP 9 | `scripts/secret-scan.sh` | 6.2.0 #62 |
| 2.10 | Type gate against the run's baseline | STEP 0 4g, 5 4b, 7 | `type_baseline` | 5.7 |
| 2.10 | Test evidence in every language | STEP 5 4d | review rule | 6.3.2 #81 |

Not ported: model preflight (`agy models`), CLI-provider timeouts and NUL-byte stripping in prompts. Softhouse runs its workers as Claude Code agents, which do not have those failure modes.
