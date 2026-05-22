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
- Opens a project action menu with Codex App / GUI context, CLI profile launches, resume, refresh/state checks, and advanced checks.
- Launches Codex CLI with direct PowerShell handoff only.
- Codex App / GUI launch prepares `.codexhub\SESSION_CONTEXT.md` in the project and shows the operator the project root/context to use in the GUI.
- GUI and CLI sessions must read/write the same project `CURRENT_TASK.md` and `AGENTS.md`; CodexHub `CURRENT_TASK.md` is only for hub maintenance.
- Resume metadata is display-only and never blocks launch.
- LO/MED/HI release checks remain available under Advanced checks.
- Restore-from-remote is future work. If a missing project has a remote, the launcher reports that the remote is available, but does not clone automatically in this build.

## Refresh Context

When the operator says "refresh context", "reload context", or "resume context", perform a read-only project truth refresh from disk/harness, not memory.

For git-backed projects, use `tools\refresh-context.ps1 -ProjectName <KEY>` or the project menu refresh option. Report project, registered root, actual git root, git state, latest tag, runtime version if relevant, dirty files, current task, warnings, and next safe step. Do not modify files and do not scan the whole project unless explicitly requested.

