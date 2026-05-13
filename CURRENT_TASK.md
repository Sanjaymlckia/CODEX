# CURRENT TASK

## Current Objective

Keep the CODEX Hub launcher portable across machines with different `CODEX_PROJECTS` drive letters while supporting hybrid Codex resume governance and default LIGHT operational mode.

## Current Runtime

- Workspace: `E:\Gdrive\01 SANJAY\Codex_Sync\CodexHub`
- Scope: CodexHub only
- Default operational mode: `LIGHT`
- Broad audit mode: `FULL_AUDIT` only when explicitly requested

## Active Blockers

- None confirmed.
- Stop if LIGHT mode weakens release safety, if CURRENT_TASK authority becomes ambiguous, or if operational correctness degrades.

## Next Action

- Validate root-authority normalization startup output and confirm LIGHT mode now shows `MODE: LIGHT` and `AUTH ROOT: E:\Gdrive\01 SANJAY\Codex_Sync` without fallback authority drift.

## Latest Accepted Release

- Current accepted hub baseline includes portable root resolution, hybrid resume governance, LIGHT mode launcher discipline, and root-authority normalization dated `2026-05-13`.

## Session History

- Objective: Keep the CODEX Hub launcher portable across machines with different `CODEX_PROJECTS` drive letters while supporting hybrid Codex resume governance and default LIGHT operational mode.
- Completed:
  - Fixed launcher input responsiveness and deterministic exit handling.
  - Added minimal Lite Ops display and initialization support.
  - Replaced generic last-root persistence with `state\machine_profile.json` storing `preferred_project_root`.
  - Added active-root discovery in priority order `D:\CODEX_PROJECTS`, `C:\CODEX_PROJECTS`, `E:\CODEX_PROJECTS`.
  - Normalized project resolution to `active root + folder name`, with configured registry paths used only as fallback.
  - Routed launch/menu path display through the shared resolver and added launch debug lines for active root, selected project, and resolved project path.
  - Promoted machine-aware `preferred_root` profile support to live `D:\CODEX`.
  - Live startup now prints `Active root: D:\CODEX_PROJECTS`.
  - Live numbered project, resume, T, V, and S paths verified against `D:\CODEX_PROJECTS`.
  - Audited live project registry against `D:\CODEX_PROJECTS`.
  - Updated Zoho CRM registry path to resolve to existing `D:\CODEX_PROJECTS\CODEX_CRM`.
  - Added separate `A. Open in Codex App` launcher action without changing numbered PowerShell launch behavior.
  - Updated hub startup prompts to use machine-aware workspace identity checks instead of C-only checks.
  - Replaced active hub README and command notes with concise portable dual-machine documentation.
  - Added Zoho CRM folder alias resolution so home can use `CODEX_CRM` and office can use `ZOHO_CRM` under the active project root.
- Notes:
  - Live machine currently resolves projects from `D:\CODEX_PROJECTS`.
  - Registry audit mismatch fixed: `ZOHO_CRM` menu entry now points at folder `CODEX_CRM`.
  - Registry audit mismatch reported: `FODE_RUNTIME` registry casing differs from existing folder `FODE_Runtime`; Windows resolves it case-insensitively.
  - Registry audit missing folders reported but not moved/renamed: `MLC_MARKETING`, `CAR_PRADO`, `GENERAL_LAB`.
  - `codex app <projectPath>` on this Windows machine prints `Opening Codex Desktop...` and instructs the user to open the workspace path; launcher therefore also prints the exact resolved path.
  - Live `RUN.ps1` backup created at `D:\CODEX\RUN.ps1.bak_20260426_175614`.
  - Active documentation is now `README.md` plus `COMMAND_LIBRARY.md`; use git history for older machine-specific notes.
  - Zoho CRM aliases are tried in resolver order `CODEX_CRM`, then `ZOHO_CRM`; the first existing folder under the active root is used.
- Zoho split session update (2026-04-27):
  - Preserved existing CODEX_CRM as the legacy/archive Zoho workspace.
  - Registered ZOHO_BOOKS_KIA_FODE, ZOHO_BOOKS_MLC, and ZOHO_CRM_INSTITUTIONAL in projects\projects.json.
  - Created restart-safe project folders under D:\CODEX_PROJECTS with CURRENT_TASK.md and AGENTS.md.
  - Did not create ZOHO_CRM_FODE; FODE CRM remains in the existing FODE project.
  - Did not move/delete existing files, modify Zoho data files, run imports, or touch live Zoho.
  - Launcher verification: active root D:\CODEX_PROJECTS; new entries resolve to folders 8, 9, and 10.
- Office readiness update (2026-05-08):
  - Requested office roots are `C:\CODEX` and `C:\CODEX_PROJECTS`; they are not present in the current session filesystem view.
  - Added DATA_GOVERNANCE to projects\projects.json with a C-root configured path so the machine-aware resolver can use `C:\CODEX_PROJECTS\DATA_GOVERNANCE` at office and `D:\CODEX_PROJECTS\DATA_GOVERNANCE` at home.
 Corrected FODE registry notes: FODE path authority is machine-specific and must be resolved through CodexHub machine_profile.json overrides.
  - No FODE runtime source, clasp, deployment, trigger, or Apps Script runtime mutation was performed.
- Machine-specific path override update (2026-05-08):
  - RUN.ps1 resolves project paths in order: local `state\machine_profile.json` project override, shared registry path, active-root fallback, then missing-path report.
  - Launcher menus now show resolved path source and warn when the configured registry path is missing on the current machine.
  - Shared FODE registry path remains the home authority path; office FODE should be supplied by a local machine profile override, not by replacing the shared registry path.
  - `state\machine_profile.json` is currently tracked; do not commit machine-specific local paths from it without an explicit tracking/ignore decision.
- Governance scaffold update (2026-05-08):
  - Make `state\machine_profile.json` local-only by ignoring it and removing it from Git tracking while preserving the local file.
  - Add `templates\project_scaffold\` with default project guardrail files.
  - Add hub prompts for new project bootstrap, project shutdown check, and drift check.
  - Expose the governance prompts from `RUN.ps1` as read-only prompt viewers.
- Governance hardening update (2026-05-08):
  - Add root governance templates for New Project creation.
  - Add read-only `tools\drift-audit.ps1` and operator-driven `tools\handoff.ps1`.
  - Add `.codex\GLOBAL_RULES.md` and `.codex\RULE_STATUS.md` for visible rule inventory only.
  - Add launcher commands: `N` New Project, `D` Drift Audit, `A` Audit selected project, `H` Handoff / Shutdown.
  - Move Codex App launch to `X` and hub-root launch to `O`.
  - Add lightweight branch, dirty state, handoff age, and health display to launcher project rows.
- Shutdown reliability update (2026-05-11):
  - Root cause isolated to child-process handoff input: `RUN.ps1` launched `tools\handoff.ps1`, then the child script waited on raw console reads for exit/menu flow.
  - Because the child pause was not owned by the parent launcher, shutdown could appear silent and consume an extra Enter before control visibly returned.
  - Fix scope is hub-only and generic for all projects: parent launcher now owns optional note capture, final shutdown report, explicit exit choice, and explicit `Press Enter to return to CodexHub menu` prompt.
  - Auto-handoff file and snapshot generation remain in the existing tool path under `state\handoffs` and `state\*_snapshot.json`.
- Hybrid resume governance update (2026-05-11):
  - Launcher startup now reads `state\<PROJECT>_resume_state.json` when present and validates repo path, git state, `CURRENT_TASK.md`, and machine name before trusting a saved Codex session.
  - Resume drift is classified as `CLEAN`, `WARNING`, or `BLOCKED`; only clean state uses native `codex resume <SESSION_ID>` automatically.
  - Warning or blocked state falls back to reconstruction from `CURRENT_TASK.md` instead of trusting session memory.
  - Shutdown now persists the current Codex thread ID, git summary, current task hash/timestamp, machine name, drift state, and recommended next launch mode for the next session.
- Office Google Drive readiness update (2026-05-13):
  - Active CodexHub root validated at `C:\GoogleDRIVE\Codex_Sync\CodexHub`.
  - Git status was clean before this CIS documentation update and remote is `https://github.com/Sanjaymlckia/CODEX.git`.
  - Local-only `state\machine_profile.json` override now resolves `FODE_RUNTIME` to `C:\GoogleDRIVE\Codex_Sync\FODE_Runtime_1wog`.
  - FODE runtime repo required Git safe-directory registration for the launcher to inspect branch/status from the Google Drive path.
  - Launcher menu renders successfully with FODE Runtime source `override`, branch `main`, state `CLEAN`, and health `AMBER`.
  - Added roadmap and governance validation docs: `ROADMAP.md`, `CODEXHUB_ROADMAP.md`, `GOVERNANCE.md`, `RULELOG.md`, `STAGES.md`, `PIPELINE.md`, and `LIFECYCLE.md`.
  - Roadmap now defines PASS 0 lifecycle/pipeline architecture, PASS 1 operational hardening, PASS 2 governance simplification, PASS 3 Books integration, and PASS 4 LMS convergence.
  - Next recommended operational priority: begin FODE PASS 1 operational hardening with dashboard visibility, email observability, WhatsApp fallback, duplicate protection, and trigger/runtime telemetry.
- LIGHT mode operational update (2026-05-13):
  - Added launcher-level operational mode selection with `LIGHT` default and `FULL_AUDIT` opt-in.
  - LIGHT startup now displays mode, token discipline state, resolved roots, project path, CURRENT_TASK path, and git status before Codex launch.
  - LIGHT bootstrap now limits startup context to compact `CURRENT_TASK.md` and `AGENTS.md` reads plus explicit operational rules injected ahead of project prompts.
  - `tools\project-status.ps1` now prefers authoritative current-task sections: current runtime, active blockers/risks, next action, and latest accepted release.
  - FULL_AUDIT preserves broader current-task and audit inspection when explicitly requested.
  - No project runtimes, deployments, Apps Script behavior, or cloud dependencies were modified.
- Root authority normalization update (2026-05-13):
  - Added `authoritative_root` to `projects\projects.json` and normalized the launcher to treat `E:\Gdrive\01 SANJAY\Codex_Sync` as the single authority root.
  - Resolution order is now explicit project path, authoritative root, then deprecated legacy fallback roots as recovery hints only.
  - Startup now prints `MODE: LIGHT` and `AUTH ROOT: E:\Gdrive\01 SANJAY\Codex_Sync`.
  - `state\last_project_root.txt` is rewritten to the authoritative root during startup initialization.
  - Resume-state normalization rewrites stale `C:\CODEX_PROJECTS` or `D:\CODEX_PROJECTS` references to the authoritative root only when the authoritative candidate exists.
  - Metadata persistence is refused when multiple valid roots are detected for the same repo and the launcher reports `ROOT AUTHORITY CONFLICT`.
  - Project health no longer turns `AMBER` merely because a deprecated fallback path was used.
