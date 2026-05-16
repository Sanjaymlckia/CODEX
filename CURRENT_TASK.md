# CURRENT TASK

## Current Objective

Operate CodexHub as Hub Lite with a thin E-root-only launcher and placeholder workspace readiness.

## Current Runtime

- Workspace: `E:\Gdrive\01 SANJAY\Codex_Sync\CodexHub`
- Scope: CodexHub only
- Mode: `LIGHT`
- Authority root: `E:\Gdrive\01 SANJAY\Codex_Sync`

## Current State

- Hub Lite target architecture is adopted.
- Project registry uses `authority_root` plus per-project `folder` entries.
- Placeholder project folders have been created for future launch readiness under the authority root.
- `FODE_RUNTIME` remains the only confirmed fully active project.
- Resume metadata is display-only.
- No `C:\` or `D:\` roots are allowed in normal operation.
- CIS in progress: add LO-only local resume state validator under `tools/` with concise JSON/report output.

## Next Action

- Validate `tools/resume_state_check.ps1` and confirm local-only classification plus JSON output shape.

## Guardrails

- Do not modify `FODE_Runtime_1wog` from CodexHub maintenance unless explicitly authorized by CIS.
- Do not add fallback root scanning or generated bootstrap logic back into the normal launcher path.
- Keep launcher behavior boring, direct, and reversible.
