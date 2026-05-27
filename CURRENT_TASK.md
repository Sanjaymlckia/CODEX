# CURRENT TASK

<!-- CODEXHUB_STATE_BACKUP_START -->
## CodexHub State Backup

- Last state backup timestamp: 2026-05-27 11:42:49
- Project path: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- Repository state: DIRTY
- Current branch: `main`
- Latest commit: `52695cb feat: add manual state backup command`
- Latest matching staging tag: `Not found.`
- Config version / deploy number: Not applicable.
- Current release track: Not detected.
- Current blocker: None detected.
- Next exact action: - Validate `RUN.ps1` project menu entries, `tools\refresh-context.ps1`, GUI context guidance, and Advanced Checks exposure for release truth `LO`/`MED`/`HI`.
- Operator note: R recognition acceptance proof

### Git Status
```text
## main...origin/main
 M CURRENT_TASK.md
 M README.md
 M RUN.ps1
 M tools/project-status.ps1
 M tools/resume_state_check.ps1
?? state/FODE_RUNTIME_last_profile.txt
?? state/FODE_RUNTIME_last_project_root.txt
```

### Changed Files
- `CURRENT_TASK.md`
- `README.md`
- `RUN.ps1`
- `tools/project-status.ps1`
- `tools/resume_state_check.ps1`
- `state/FODE_RUNTIME_last_profile.txt`
- `state/FODE_RUNTIME_last_project_root.txt`
<!-- CODEXHUB_STATE_BACKUP_END -->

## Current Objective

Operate CodexHub as Hub Lite with a thin E-root-only launcher and placeholder workspace readiness.

## Current Runtime

- Workspace: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- Scope: CodexHub only
- Mode: `LIGHT`
- Authority root: `E:\Gdrive\01_SANJAY\Codex_Sync`

## Current State

- Hub Lite target architecture is adopted.
- Project registry uses `authority_root` plus per-project `folder` entries.
- Placeholder project folders have been created for future launch readiness under the authority root.
- `FODE_RUNTIME` remains the only confirmed fully active project.
- Resume metadata is display-only.
- No `C:\` or `D:\` roots are allowed in normal operation.
- CIS in progress: add project context launcher, GUI context support, and the read-only refresh context rule without centralizing project CURRENT_TASK files in CodexHub.

## Next Action

- Validate `RUN.ps1` project menu entries, `tools\refresh-context.ps1`, GUI context guidance, and Advanced Checks exposure for release truth `LO`/`MED`/`HI`.

## Guardrails

- Do not modify `FODE_Runtime_1wog` from CodexHub maintenance unless explicitly authorized by CIS.
- Do not add fallback root scanning or generated bootstrap logic back into the normal launcher path.
- Keep launcher behavior boring, direct, and reversible.
- "Refresh context", "reload context", and "resume context" mean read-only project truth refresh from the registered project root, not memory and not CodexHub's own CURRENT_TASK.md.

## GDrive Rename Path Authority Check

Active local authority root confirmed by operator:

`E:\Gdrive\01_SANJAY\Codex_Sync`

Old local root no longer exists:

`E:\Gdrive\01 SANJAY`

CodexHub path audit found active authority references already updated. Corrective cleanup targeted stale legacy examples, broad deprecated-root detection, and fallback-path wording only. No FODE runtime, Apps Script deployment, Sheets, or Drive content changes authorized.
