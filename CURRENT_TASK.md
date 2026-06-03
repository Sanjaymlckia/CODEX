# CURRENT TASK

<!-- CODEXHUB_STATE_BACKUP_START -->
## CodexHub State Backup

- Last state backup timestamp: 2026-05-28 19:27:01
- Project path: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- Repository state: DIRTY
- Current branch: `main`
- Latest commit: `639cb2c tooling: show runtime shell proof in launcher`
- Latest matching staging tag: `Not found.`
- Config version / deploy number: Not applicable.
- Current release track: Not detected.
- Current blocker: None detected.
- Next exact action: Run final verification: `git status -sb`, `git diff --check`, then commit and push if all checks pass.
- Operator note: [add operator note]

### Git Status
```text
## main...origin/main
?? state/FODE_RUNTIME_last_profile.txt
?? state/FODE_RUNTIME_last_project_root.txt
?? state/pre_codex_reinstall_resume_state_check.diff
```

### Changed Files
- `state/FODE_RUNTIME_last_profile.txt`
- `state/FODE_RUNTIME_last_project_root.txt`
- `state/pre_codex_reinstall_resume_state_check.diff`
<!-- CODEXHUB_STATE_BACKUP_END -->

## Current Objective

Track L CodexHub tooling maintenance only: enforce PowerShell 7, register CodexHub as a first-class project, add local authority before remote proof, classify sandbox startup failures separately, block temp repo/remote proof/outside-memory fallback in LIGHT/LO/MED, and record tooling readiness.

## Investigation Result

- Workspace: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- PowerShell: `7.6.2`
- Shell path: `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.2.0_x64__8wekyb3d8bbwe`
- `pwsh`: `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.2.0_x64__8wekyb3d8bbwe\pwsh.exe`
- Origin: `https://github.com/Sanjaymlckia/CODEX.git`
- Codex shell sanity: `Get-Location`, `$PSVersionTable.PSVersion.ToString()`, and `git status -sb` all worked inside Codex.
- Sandbox stability: no `CreateProcessAsUserW failed: 1312` or `windows sandbox: spawn setup refresh` occurred during this CIS.
- MCP/node_repl status: prior warning was not reproduced after `.codex` reset; treated as `MCP_WARNING_NON_BLOCKING` while shell/git commands work.

## Current Dirty-State Handling

Pre-existing dirty state was inspected before editing and not cleaned, reset, or deleted.

```text
## main...origin/main
 M tools/resume_state_check.ps1
?? state/FODE_RUNTIME_last_profile.txt
?? state/FODE_RUNTIME_last_project_root.txt
?? state/pre_codex_reinstall_resume_state_check.diff
```

Interpretation: `tools/resume_state_check.ps1` already contained a state-backup freshness change. The untracked state files record FODE Runtime launch/profile context and a saved pre-reset diff. The new local authority gate recognizes the repo as `LOCAL_AUTHORITY_DIRTY_RECORDED` because `CURRENT_TASK.md` records the dirty state.

## Files Changed

- `RUN.ps1`
- `projects/projects.json`
- `CURRENT_TASK.md`
- `tools/local_authority_check.ps1`
- `tools/project-status.ps1`
- `tools/refresh-context.ps1`
- `tools/release_truth_check.ps1`
- `tools/resume_state_check.ps1`

No FODE Runtime files were modified.

## PS7 Guard Result

- `RUN.ps1` now blocks Windows PowerShell 5.1 from continuing silently.
- If `pwsh` is available, it prints `Windows PowerShell 5.1 detected. Re-launching CodexHub under PowerShell 7.` and re-execs under PowerShell 7.
- If `pwsh` is missing, it stops with `PowerShell 7 is required. Install or launch pwsh before running CodexHub.`
- `release_truth_check.ps1`, `resume_state_check.ps1`, `project-status.ps1`, and `refresh-context.ps1` have the same PS7 guard.

## CodexHub Registration Result

`projects/projects.json` now includes:

- Name: `CodexHub Tooling`
- Path: `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`
- Status: `active`
- Purpose: local CodexHub launcher, governance, tooling, and release-discipline maintenance.
- Remote: `https://github.com/Sanjaymlckia/CODEX.git`

`RUN.ps1` menu shows `CodexHub Tooling` as project 1 without selecting FODE Runtime, Sandbox Lab, or another unrelated project.

## Local Authority Results

| Target | Mode | Status | Remote proof | Temp repo | Outside memory | Notes |
|---|---:|---|---|---|---|---|
| CodexHub | LO | `LOCAL_AUTHORITY_DIRTY_RECORDED` | `REMOTE_PROOF_BLOCKED` | `REMOTE_PROOF_BLOCKED` | `REMOTE_PROOF_BLOCKED` | Dirty state recorded in `CURRENT_TASK.md`. |
| FODE Runtime | LO | `LOCAL_AUTHORITY_OK` | `REMOTE_PROOF_BLOCKED` | `REMOTE_PROOF_BLOCKED` | `REMOTE_PROOF_BLOCKED` | Read-only validation only; git status remained clean. |

## Sandbox Classification Result

Input containing `CreateProcessAsUserW failed: 1312` and `windows sandbox: spawn setup refresh` returns:

```text
SANDBOX_STARTUP_FAILURE: Windows sandbox runner could not create process/session. This is environment startup failure, not project authority failure. No temp repo, no outside-memory search, and no remote proof was created.
```

## LO/MED Block Results

- `Test-LocalAuthority -Mode LO` blocks remote proof, temp repo, and outside-memory fallback when local authority is sufficient or dirty-recorded.
- `release_truth_check.ps1 -Mode LO` stayed local: no temp repo, no clone, no outside-memory search, and remote tag lookup was skipped.
- No temp repo, remote proof clone, or outside-memory search was created in this CIS.

## Tools Audit

| Tool file | Purpose | Reads project registry? | Uses temp repo? | Uses remote proof? | Touches outside repo? | Requires PS7 guard? | Needs change now? | Notes |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `tools/audit-project-resolver.ps1` | Audit/preview project resolver normalization. | Yes | No | No | Writes state preview only | Follow-up | No | Legacy roots are discovery-only and must not override authority root. |
| `tools/drift-audit.ps1` | Detect path/runtime drift. | No direct registry read found | No | No | Reads project files only | Follow-up | No | Contains stale-path detection for old roots. |
| `tools/handoff.ps1` | Create local handoff snapshots. | No | No | No | Writes configured state/handoff path | Follow-up | No | Local writer; no remote behavior found. |
| `tools/path-doctor.ps1` | Diagnose registry/path issues. | Yes | No | No | Reads registry/files only | Follow-up | No | Diagnostic only. |
| `tools/project-status.ps1` | Project status and optional state-backup writer. | No | No | No | Reads selected project; may update selected `CURRENT_TASK.md` on explicit backup | Yes | Yes | Added PS7 guard and local authority gate. |
| `tools/refresh-context.ps1` | Read-only project truth refresh from registry root. | Yes | No | No | Reads registered project and nearby tasks under authority root | Yes | Yes | Added PS7 guard and local authority gate. |
| `tools/release_truth_check.ps1` | Release truth check with LO/MED/HI levels. | No | No | MED can query remote tags; HI can call live URLs | Writes `.codexhub/release_truth/latest.json` | Yes | Yes | Added PS7 guard and local authority gate before checks. LO remains local. |
| `tools/resume_state_check.ps1` | Resume-state classification and report. | No | No | No | Writes `.codexhub/resume_state/latest.json` | Yes | Yes | Preserved pre-existing freshness change; added PS7 guard and local authority gate. |

## External Tool Readiness

| Tool | Found? | Version | Path | Required for | Status | Notes |
|---|---:|---|---|---|---|---|
| `pwsh` | Yes | `PowerShell 7.6.2` | `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.2.0_x64__8wekyb3d8bbwe\pwsh.exe` | Launcher/scripts | OK | Required. |
| `git` | Yes | `2.53.0.windows.1` | `C:\Program Files\Git\cmd\git.exe` | Authority/status | OK | Required. |
| `rg` | Yes | `15.1.0` | Codex vendored `rg.exe`; WinGet `rg.exe` also present | Audits/search | OK | Required for audit commands. |
| `jq` | Yes | `1.8.1` | WinGet `jq.exe` | JSON inspection | OK | Optional. |
| `node` | Yes | `v25.9.0` | `C:\Program Files\nodejs\node.exe` | npm tooling | OK | Required for npm-installed tools. |
| `npm` | Yes | `11.12.1` | `C:\Program Files\nodejs\npm.cmd` and user npm shim | Tool wrappers | OK | Required for `clasp`/`codex` installs. |
| `clasp` | Yes | `3.3.0` | `C:\Users\sanja\AppData\Roaming\npm\clasp.cmd` | Apps Script workflows | OK | No push/version/deploy run. |
| `codex` | Yes | `codex-cli 0.134.0` | `C:\Users\sanja\AppData\Roaming\npm\codex.cmd` | Codex CLI launch | OK | Required for launcher workflow. |
| `magick` | Yes | `ImageMagick 7.1.2-22` | `C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe` | Optional media tooling | OK | Optional. |

## Acceptance Results

| Check | Result | Evidence |
|---|---|---|
| PowerShell 7 guard from Windows PowerShell 5.1 | PASS | `powershell.exe -File .\RUN.ps1 -SelfTest` printed re-launch message and `SELFTEST PASS`. |
| CodexHub registration | PASS | `RUN.ps1` menu lists `1. CodexHub Tooling` with path `E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub`. |
| CodexHub local authority | PASS | `LOCAL_AUTHORITY_DIRTY_RECORDED`. |
| FODE read-only local authority | PASS | `LOCAL_AUTHORITY_OK`; FODE `git status -sb` remained `## main...origin/main`. |
| LO mode blocks remote proof on dirty-recorded repo | PASS | CodexHub LO result has `REMOTE_PROOF_BLOCKED` and temp/outside-memory blocked. |
| 1312/spawn setup refresh classification | PASS | Returns `SANDBOX_STARTUP_FAILURE` with required message. |
| `release_truth_check.ps1 -Mode LO` remains local/light | PASS | Remote tag lookup skipped; no temp repo, clone, or outside-memory search. |
| Stale path scan | PASS with historical/documentation notes | Matches are legacy docs, stale-path detection, or explicit block messages; no active authority uses old root. |
| Codex shell sanity | PASS | `Get-Location`, PS version, and `git status -sb` worked. |
| Tools audit table present | PASS | See `Tools Audit`. |
| External tool readiness table present | PASS | See `External Tool Readiness`. |

## Follow-Ups

- Consider adding PS7 guard to lower-risk diagnostic scripts (`audit-project-resolver.ps1`, `drift-audit.ps1`, `handoff.ps1`, `path-doctor.ps1`) in a later cleanup.
- Consider replacing discovery-only legacy root references in `audit-project-resolver.ps1` with explicit historical fixtures if that script is still used.
- Consider adding a noninteractive menu test harness so `RUN.ps1` menu output can be checked without relying on piped input.

## Next Exact Step

Run final verification: `git status -sb`, `git diff --check`, then commit and push if all checks pass.
