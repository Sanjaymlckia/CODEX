# Release Truth Check

Command:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release_truth_check.ps1
```

Behavior:

- Read-only inspection of the current git repo root.
- Reports git branch, HEAD, `git status -sb`, local/remote staging tags, `Config.js` version fields, `CURRENT_TASK.md` release baseline, optional live `whoami`, warnings, and final classification.
- Writes JSON output to `.codexhub\release_truth\latest.json`.
- Missing config, tags, task baseline, or live URLs become warnings instead of crashes.

Classification values:

- `CLEAN_MATCH`
- `LOCAL_DIRTY`
- `VERSION_MISMATCH`
- `TAG_MISMATCH`
- `LIVE_MISMATCH`
- `INSUFFICIENT_DATA`
