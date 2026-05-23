# COMMAND LIBRARY

Portable CODEX Hub commands. Run these from the active hub root.

## Launch

Current startup:

```powershell
cd "E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub"
.\RUN.ps1
```

From the active hub root:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

Historical/deprecated hub roots:

- `D:\CODEX`
- `C:\CODEX`

## Active Paths

Current live machine:

- Hub: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- Authority root: `E:\Gdrive\01_SANJAY\Codex_Sync`
- Registry: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub\projects\projects.json`
- Prompts: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub\prompts`

Historical/deprecated examples:

- Hub: `C:\CODEX`
- Projects: `C:\CODEX_PROJECTS`
- Hub: `D:\CODEX`
- Projects: `D:\CODEX_PROJECTS`

## Quick Checks

```powershell
Get-Content .\CURRENT_TASK.md
Get-Content .\projects\projects.json
Get-Content .\state\machine_profile.json
```

Historical project-folder examples only:

```powershell
Get-ChildItem D:\CODEX_PROJECTS
Get-Content D:\CODEX_PROJECTS\CODEX_CRM\CURRENT_TASK.md
```

## Notes

- Keep one active README: `README.md`.
- Use git history for rollback and older hub notes.
- Project paths should resolve as active root plus project folder name before falling back to registry paths.
- Read `CURRENT_TASK.md` before work and update it before ending a major session.
