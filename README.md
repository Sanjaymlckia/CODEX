# CODEX Hub

Portable launcher and operating notes for the CODEX hub.

The hub is designed to work on machines where the hub and project roots may use different drive letters. Do not create parallel active READMEs for machine variants; keep this file portable and use git history for rollback.

## Launch

Run from the hub root on the current machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

Known hub roots:

- Home/live: `D:\CODEX`
- Office/alternate: `C:\CODEX`

## Project Roots

The launcher resolves active projects under the current machine's active project root.

Project path resolution:

1. `state\machine_profile.json` machine-specific `project_path_overrides[project.name]`, when present and existing
2. `projects\projects.json` `path`, when existing
3. Active project root fallback from `state\machine_profile.json` machine-specific `preferred_root`
4. Existing fallback roots in this order:
   - `D:\CODEX_PROJECTS`
   - `C:\CODEX_PROJECTS`
   - `E:\CODEX_PROJECTS`
5. Missing-path report with the configured and resolved paths visible

The launcher menu prints each project name, resolved path, source (`override`, `default`, `fallback`, or `missing`), and warns when the configured registry path is absent on the current machine.

## Hub Files

- `RUN.ps1` - registry-driven portable launcher
- `projects\projects.json` - project registry and labels
- `prompts\` - per-project startup prompts
- `state\machine_profile.json` - machine-aware preferred project root and optional local project path overrides
- `state\last_project.txt` and `state\recent_projects.json` - launcher memory
- `COMMAND_LIBRARY.md` - short command reference
- `CURRENT_TASK.md` - current hub maintenance objective

## Launcher Options

- Number key - open the selected active project in PowerShell
- `R` - resume the last opened project
- `J` - open from recent projects
- `T` - quick-open a project's `CURRENT_TASK.md`
- `S` - create a snapshot handoff file
- `A` - open the selected project in Codex Desktop
- `C` - open the command library
- `H` - open the hub root
- `V` - initialize CODEX LITE OPS files
- `0` - exit

The launcher prints the active root and resolved project path before launching. If Codex Desktop does not open the requested workspace automatically, use the printed path.

## Project Discipline

Each active project should keep:

- `CURRENT_TASK.md` - active objective and next restart action
- `NOTES.md` - running notes and decisions
- `SNAPSHOT\` - handoff or state snapshots
- `EXPORTS\` - deliverables and generated outputs

Operating pattern:

1. Launch the correct project from `RUN.ps1`.
2. Read the project's `CURRENT_TASK.md` before working.
3. Update `CURRENT_TASK.md` before closing a major session.
4. Keep long-form notes in `NOTES.md`.
5. Preserve source evidence, imports, exports, and generated outputs.
