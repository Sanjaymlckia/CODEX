# CODEX Hub

Canonical office hub path: `C:\CODEX`

This office machine is now the authoritative CODEX hub structure. The GitHub repo baseline was used only as an advisory source for launcher behavior, prompts, and reusable project scaffold content.

## Launch

Run the hub from PowerShell with:

```powershell
powershell -ExecutionPolicy Bypass -File C:\CODEX\RUN.ps1
```

## Canonical Roots

- `C:\CODEX\` - hub files, launcher, registry, prompts, state
- `C:\CODEX_PROJECTS\` - active project workspaces
- `C:\CODEX_ARCHIVE\` - archive area by project
- `C:\CODEX_TEMP\` - temporary comparison and working area

## Hub Contents

- `RUN.ps1` - registry-driven launcher
- `COMMAND_LIBRARY.md` - quick operational commands
- `projects\projects.json` - canonical office project registry
- `prompts\` - per-project startup prompts
- `state\` - restart-safe launcher state such as the last opened and recent projects

## Launcher Features

- Recent-project memory with a dedicated recent-project menu
- Quick-open `CURRENT_TASK.md` for any active project
- Snapshot handoff helper that creates a dated file inside a selected project's `SNAPSHOT\` folder
- Per-project status line showing whether the target is a git repo or a standard folder
- Desktop shortcut support via `codexhub` and a `CODEX HUB` shortcut

Current launcher options:

- Number key - open the selected active project
- `R` - resume the last opened project
- `J` - open from recent projects
- `T` - quick-open `CURRENT_TASK.md`
- `S` - create a snapshot handoff file
- `C` - open the command library
- `H` - open the `C:\CODEX` hub root
- `0` - exit

## Project Discipline

Each active project should keep:

- `CURRENT_TASK.md` - active objective and next restart action
- `NOTES.md` - running notes and decisions
- `SNAPSHOT\` - handoff or state snapshots
- `EXPORTS\` - deliverables and generated outputs

Recommended operating pattern:

1. Launch the correct project from `RUN.ps1`.
2. Read `CURRENT_TASK.md` before working.
3. Update `CURRENT_TASK.md` before closing the session.
4. Keep long-form notes in `NOTES.md`.
5. Move completed outputs into `EXPORTS\` and older material into `C:\CODEX_ARCHIVE\`.
