# CURRENT TASK

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

