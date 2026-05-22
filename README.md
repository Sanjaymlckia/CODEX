# CODEX Hub Lite

Thin launcher for Codex workspaces under the single authority root:
`E:\Gdrive\01_SANJAY\Codex_Sync`

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

Optional fast validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1 -SelfTest
```

## Registry

`projects\projects.json` uses this shape:

```json
{
  "authority_root": "E:\\Gdrive\\01_SANJAY\\Codex_Sync",
  "projects": [
    {
      "name": "FODE_RUNTIME",
      "display_name": "FODE Runtime",
      "folder": "FODE_Runtime_1wog",
      "remote": "https://github.com/Sanjaymlckia/FODE_Runtime_1wog.git",
      "status": "active"
    }
  ]
}
```

Rules:

- Store only one `authority_root`.
- Store project `folder`, not full local paths.
- Normal operation does not use `C:\` or `D:\` roots.
- `active` means ready to launch now.
- `placeholder` means the folder exists for future work, but remote/purpose may still need confirmation.

## Launcher Behavior

- Shows `LIGHT` mode and the authority root.
- Lists active and placeholder projects from the registry.
- Computes local project path as `authority_root + folder`.
- Launches Codex with direct PowerShell handoff only.
- Resume metadata is display-only and never blocks launch.
- Restore-from-remote is future work. If a missing project has a remote, the launcher reports that the remote is available, but does not clone automatically in this build.

