# CURRENT TASK

## Current Objective

Keep CodexHub stable in LIGHT mode while enforcing `E:\Gdrive\01 SANJAY\Codex_Sync` as the sole normal-operation root and keeping launcher bootstrap output parser-safe.

## Current Runtime

- Workspace: `E:\Gdrive\01 SANJAY\Codex_Sync\CodexHub`
- Scope: CodexHub only
- Default operational mode: `LIGHT`
- Broad audit mode: `FULL_AUDIT` only when explicitly requested
- Sole authority root: `E:\Gdrive\01 SANJAY\Codex_Sync`

## Active Blockers

- None confirmed.
- Stop if launcher output reintroduces non-E normal-flow paths or if child bootstrap generation regresses.

## Next Action

- Keep future launcher edits limited to verified regressions and preserve the E-root-only registry discipline.

## Latest Accepted Release

- Current accepted hub baseline includes runtime stabilization, child-bootstrap hygiene repair, and E-root legacy-path cleanup dated `2026-05-13`.

## Notes

- The occasional `C:\PowerShellHistory` line seen in shell tool output was incidental child-process output from the local shell environment.
- It was not evidence that CodexHub was running from `C:\`.
- Root authority remains `E:\Gdrive\01 SANJAY\Codex_Sync`.

## Session History

- Child bootstrap generation now emits valid PowerShell for current-task summaries, including the exact form `$summary.Add("## $heading") | Out-Null`.
- Startup validation and `--selftest` remain the required fast checks before trusting menu/runtime behavior.
- Missing resume state now reports `INFO`; dirty or drifted resume conditions degrade to `RECOVERABLE`.
- Normal launcher flow now uses only E-root active projects; non-E workspaces are archived in the registry until authoritative E-root folders exist.
