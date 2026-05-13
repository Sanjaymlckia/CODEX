# CODEX Hub

Portable launcher and operating notes for the CODEX hub.

The hub uses a single authoritative project root: `E:\Gdrive\01 SANJAY\Codex_Sync`. Normal launcher operation resolves only E-root workspaces.

## Launch

Run from the hub root on the current machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

For a broader audit session:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1 -OperationalMode FULL_AUDIT
```

Fast validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1 --selftest
```

Known hub root:

- `E:\Gdrive\01 SANJAY\Codex_Sync\CodexHub`

## Project Roots

The launcher resolves active projects only under the authoritative root.

Project path resolution:

1. `projects\projects.json` explicit `path`, when present and valid
2. `projects\projects.json` `authoritative_root` + project leaf name
3. Missing-path report with the configured and resolved paths visible

The launcher menu prints each project name, resolved path, source (`override`, `explicit`, `authoritative`, or `missing`), and reports `ROOT AUTHORITY CONFLICT` when multiple roots are detected for the same repo. Conflict state blocks metadata persistence.

## Hub Files

- `RUN.ps1` - registry-driven launcher
- `projects\projects.json` - project registry and labels
- `prompts\` - per-project startup prompts
- `templates\project_scaffold\` - default governance files for new projects
- `tools\drift-audit.ps1` - read-only project drift audit
- `tools\handoff.ps1` - operator-driven shutdown handoff writer
- `.codex\` - visible rule inventory and status files
- `state\machine_profile.json` - deprecated synced state note only
- `state\last_project.txt` and `state\recent_projects.json` - launcher memory
- `state\<PROJECT>_resume_state.json` - per-project Codex resume session state and validation metadata
- `COMMAND_LIBRARY.md` - short command reference
- `CURRENT_TASK.md` - current hub maintenance objective

## Launcher Options

- Number key - open the selected active project in PowerShell
- `A` - audit a selected project
- `D` - run drift audit for a selected project
- `H` - run handoff/shutdown for a selected project
- `N` - create a new project from governance templates
- `R` - resume the last opened project
- `J` - open from recent projects
- `T` - quick-open a project's `CURRENT_TASK.md`
- `S` - create a snapshot handoff file
- `X` - open the selected project in Codex Desktop
- `C` - open the command library
- `B` - open the new project bootstrap prompt
- `P` - open the project shutdown check prompt
- `O` - open the hub root
- `V` - initialize CODEX LITE OPS files
- `0` - exit

## Operational Modes

- `LIGHT` is the default operational mode.
- `FULL` normalizes to `FULL_AUDIT`.
- `LIGHT` reads `CURRENT_TASK.md`, `AGENTS.md`, changed files, and explicitly requested files only.
- `LIGHT` startup surfaces `MODE`, `AUTH ROOT`, resolved project path, `CURRENT_TASK` path, and git status.
- `FULL_AUDIT` is opt-in and allows broad audits when explicitly needed.

## Resume Semantics

- Missing resume state reports `INFO`, not `BLOCKED`.
- Dirty or drifted resume state reports `RECOVERABLE` unless a true blocking condition exists.
- `--selftest` must pass before trusting launcher changes.
