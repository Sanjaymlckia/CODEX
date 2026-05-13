# CODEX Hub

Portable launcher and operating notes for the CODEX hub.

The hub is designed to work on machines where the hub and project roots may use different drive letters. Do not create parallel active READMEs for machine variants; keep this file portable and use git history for rollback.

## Launch

Run from the hub root on the current machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1
```

Operational mode defaults to `LIGHT`. For a broader audit session:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN.ps1 -OperationalMode FULL_AUDIT
```

You can also set `CODEXHUB_OPERATIONAL_MODE=FULL_AUDIT` in the current shell.

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
- `templates\project_scaffold\` - default governance files for new projects
- `templates\*.template.md` - automation-ready governance templates for the New Project flow
- `tools\drift-audit.ps1` - read-only project drift audit
- `tools\handoff.ps1` - operator-driven shutdown handoff writer
- `.codex\` - visible rule inventory and status files
- `state\machine_profile.json` - machine-aware preferred project root and optional local project path overrides
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

Project open uses hybrid resume by default:

1. The launcher reads the per-project resume state file when present.
2. It validates repo path, git state, `CURRENT_TASK.md`, and machine name.
3. If validation is `CLEAN`, it offers the native `codex resume <SESSION_ID>` path.
4. If validation is `WARNING` or `BLOCKED`, it falls back to fresh reconstruction from `CURRENT_TASK.md`.
5. Operators can choose `A` auto, `R` resume, or `F` fresh reconstruction at launch time.

The launcher prints the active root and resolved project path before launching. If Codex Desktop does not open the requested workspace automatically, use the printed path.

## Operational Modes

- `LIGHT` is the default operational mode.
- `LIGHT` reads `CURRENT_TASK.md`, `AGENTS.md`, changed files, and explicitly requested files only.
- `LIGHT` avoids repo-wide scans, recursive searches, historical release scans, repeated governance recap, repeated runtime-truth recap, and verbose summaries.
- `LIGHT` startup surfaces mode, token discipline state, resolved roots, project path, `CURRENT_TASK` path, and git status.
- `FULL_AUDIT` is opt-in and allows broad audits, repo history scans, historical governance parsing, drift analysis, and wider release inspection when explicitly needed.
- Operational mode changes Codex startup discipline only. It does not relax runtime, deployment, or release safety gates.

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

New projects should start from `templates\project_scaffold\` so `CURRENT_TASK.md`, `AGENTS.md`, `README.md`, `RELEASE_LOG.md`, `DECISIONS.md`, `DRIFT_CHECK.md`, and `SHUTDOWN_CHECKLIST.md` exist from the first session.

The `N` launcher flow uses root-level `templates\*.template.md` files and asks before git initialization, README creation, registry registration, or overwriting any existing governance file.

Project health is intentionally simple:

- `GREEN` means the path exists, `CURRENT_TASK.md` exists, optional guardrail docs are present, repo state is clean, and handoff is fresh.
- `AMBER` means the path is usable but has stale handoff state, a dirty repo, or missing optional guardrail docs.
- `RED` means the path is invalid, `CURRENT_TASK.md` is missing, or git is detached.
