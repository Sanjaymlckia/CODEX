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

## Refresh Context Rule

When the operator says "refresh context", "reload context", or "resume context", the agent must perform a read-only project truth refresh from disk and the harness, not memory.

For git-backed projects, refresh context means: print `pwd`, `git rev-parse --show-toplevel`, `git status -sb`, `git log --oneline -5`, latest relevant staging tag, `CURRENT_TASK.md` summary, `AGENTS.md` summary if present, and `Config.js` version fields when release-related. Live Admin/Student `whoami` checks are only for deployment or release work.

For non-git projects, refresh context means: confirm the registered project root, read `CURRENT_TASK.md` or `PROJECT_STATE.md` if present, read `AGENTS.md` if present, and report the last known baseline, blockers, and next safe step. Do not scan the whole project unless explicitly requested.

The response must stay concise: project, registered root, actual git root if any, git state, latest release/tag, runtime version if relevant, dirty files, current task, warnings, and next safe step. Refresh context must not modify files.

## Operational Trust Priority

Operational trust is now more important than feature velocity. PASS 1 should prioritize dashboard visibility, email observability, WhatsApp fallback, duplicate protection, and runtime telemetry before broader integrations.
