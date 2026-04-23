# COMMAND LIBRARY

Canonical hub root: `C:\CODEX`

Primary launch command:

```powershell
powershell -ExecutionPolicy Bypass -File C:\CODEX\RUN.ps1
```

Useful paths:

- Hub: `C:\CODEX`
- Projects: `C:\CODEX_PROJECTS`
- Archive: `C:\CODEX_ARCHIVE`
- Temp: `C:\CODEX_TEMP`
- Registry: `C:\CODEX\projects\projects.json`
- Prompts: `C:\CODEX\prompts`

Quick checks:

```powershell
Get-ChildItem C:\CODEX_PROJECTS
Get-Content C:\CODEX\projects\projects.json
Get-Content C:\CODEX_PROJECTS\ZOHO_CRM\CURRENT_TASK.md
```

Project discipline:

- Read `CURRENT_TASK.md` before making changes.
- Update `CURRENT_TASK.md` before closing a work session.
- Keep long-form project notes in `NOTES.md`.
- Preserve imports, exports, and evidence files.
