# Resume State Check

Command:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\resume_state_check.ps1
```

Behavior:

- LO-only, fully local, offline resume safety check.
- Reads repo path, machine name, local git branch/HEAD/status, `CURRENT_TASK.md` presence and timestamp/hash, optional local `release_truth` JSON, optional local resume state JSON, and basic path consistency.
- Writes JSON output to `.codexhub\resume_state\latest.json`.
- Does not call network, clasp, Apps Script, runtime, or browser surfaces.

Classifications:

- `SAFE_RESUME`
- `DIRTY_BUT_RECORDED`
- `DIRTY_UNRECORDED`
- `TASK_FILE_MISSING`
- `TASK_DRIFT`
- `PATH_DRIFT`
- `MACHINE_DRIFT`
- `TRUST_RESET_REQUIRED`
- `INSUFFICIENT_DATA`

Console style:

```text
Resume: SAFE_RESUME | Git: clean | Task: current | Mode: LO
```
