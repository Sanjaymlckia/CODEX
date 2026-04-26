# COMMAND LIBRARY

Portable CODEX Hub commands. Run these from the active hub root.

## Launch

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

Known hub roots:

- `D:\CODEX`
- `C:\CODEX`

## Active Paths

Current live machine:

- Hub: `D:\CODEX`
- Projects: `D:\CODEX_PROJECTS`
- Registry: `D:\CODEX\projects\projects.json`
- Prompts: `D:\CODEX\prompts`

Alternate machine root:

- Hub: `C:\CODEX`
- Projects: `C:\CODEX_PROJECTS`

## Quick Checks

```powershell
Get-Content .\CURRENT_TASK.md
Get-Content .\projects\projects.json
Get-Content .\state\machine_profile.json
```

Check resolved project folders on the live machine:

```powershell
Get-ChildItem D:\CODEX_PROJECTS
Get-Content D:\CODEX_PROJECTS\CODEX_CRM\CURRENT_TASK.md
```

## Notes

- Keep one active README: `README.md`.
- Use git history for rollback and older hub notes.
- Project paths should resolve as active root plus project folder name before falling back to registry paths.
- Read `CURRENT_TASK.md` before work and update it before ending a major session.
