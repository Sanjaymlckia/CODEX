# Governance Maturity Findings

## Current Assessment

| Area | Finding |
| --- | --- |
| Rule sprawl | Moderate. `.codex` has a small rule inventory, but prompts, tools, CURRENT_TASK.md, and project files all carry governance fragments. |
| Obsolete rules | No retired project rules are recorded beyond `Background monitoring`; older D-root and E-root references remain as migration history. |
| Duplicate governance | Present. Startup, shutdown, drift, and resume rules appear in launcher code, prompts, and task notes. |
| Shutdown/recovery maturity | Stronger than baseline. Auto-handoff, snapshots, and resume-state validation exist and are launcher-visible. |
| Drift handling | Mature enough for operation. Drift audit and resume validation classify clean, warning, and blocked states. |
| Snapshot trust model | Acceptable with limits. Snapshots support reconstruction but should not override CURRENT_TASK.md or live runtime truth. |
| Token overhead risk | Moderate. The launcher and task file preserve useful history but can grow into repeated context overhead. |
| Governance compression opportunities | Consolidate active rules into `.codex\GLOBAL_RULES.md` and `.codex\RULE_STATUS.md`; keep prompts procedural and task files factual. |

## Direction

CodexHub should move from governance-heavy to operations-light. Do not create new mandatory rituals. Compress existing rules before adding new ones.

## Operational Trust Priority

Operational trust is now more important than feature velocity. PASS 1 should prioritize dashboard visibility, email observability, WhatsApp fallback, duplicate protection, and runtime telemetry before broader integrations.
