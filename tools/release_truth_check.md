# Release Truth Check

Command:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release_truth_check.ps1 -Mode LO
```

Behavior:

- Read-only inspection of the current git repo root.
- Default mode is `LO`.
- Writes JSON output to `.codexhub\release_truth\latest.json`.
- Missing config, tags, task baseline, clasp metadata, or live URLs become warnings or skipped checks instead of crashes.

Modes:

- `LO`: fully local only. Reads git branch/HEAD/status, local staging tags, `Config.js` version fields, and `CURRENT_TASK.md` baseline. No remote git lookups, no clasp inventory, and no live URL calls.
- `MED`: adds remote staging tag lookup and local `.clasp.json` inventory when present. Still skips live `whoami`.
- `HI`: includes `MED` checks plus live `whoami` calls when Admin/Student URLs are configured.

Outputs:

- `mode`
- `git`
- `config`
- `tags`
- `clasp`
- `current_task`
- `live`
- `skipped_checks`
- `warnings`
- `classification`
- `next_recommended_mode`

Examples:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release_truth_check.ps1 -Mode LO
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release_truth_check.ps1 -Mode MED
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release_truth_check.ps1 -Mode HI
```

Classification values:

- `CLEAN_MATCH`
- `LOCAL_DIRTY`
- `VERSION_MISMATCH`
- `TAG_MISMATCH`
- `LIVE_MISMATCH`
- `INSUFFICIENT_DATA`
