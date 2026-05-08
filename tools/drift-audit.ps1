param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$ProjectName = "",
    [string]$RegistryPath = "",
    [string]$MachineProfilePath = "",
    [int]$HandoffStaleHours = 24
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Level, [string]$Area, [string]$Reason)
    $script:results.Add([pscustomobject]@{ Level = $Level; Area = $Area; Reason = $Reason }) | Out-Null
}

function Test-TextContains {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool](Select-String -LiteralPath $Path -Pattern $Pattern -SimpleMatch -Quiet)
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Path $ProjectPath -Leaf
}

Write-Host "Drift audit: $ProjectName"
Write-Host "Path: $ProjectPath"
Write-Host ""

if (-not (Test-Path -LiteralPath $ProjectPath)) {
    Add-Result "FAIL" "Path Drift" "Project path does not exist."
} else {
    $required = @("CURRENT_TASK.md", "AGENTS.md", "KNOWN_GOOD_STATE.md")
    foreach ($fileName in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path -Path $ProjectPath -ChildPath $fileName))) {
            Add-Result "FAIL" "Governance Drift" "Missing $fileName."
        }
    }

    $ruleLogPath = Join-Path -Path $ProjectPath -ChildPath "RULELOG.md"
    if (-not (Test-Path -LiteralPath $ruleLogPath)) {
        Add-Result "WARN" "Governance Drift" "Missing RULELOG.md."
    } else {
        $ruleLogAge = (Get-Date) - (Get-Item -LiteralPath $ruleLogPath).LastWriteTime
        if ($ruleLogAge.TotalDays -gt 30) {
            Add-Result "WARN" "Governance Drift" "RULELOG.md has not changed in more than 30 days."
        }
    }

    $taskPath = Join-Path -Path $ProjectPath -ChildPath "CURRENT_TASK.md"
    if (Test-Path -LiteralPath $taskPath) {
        $taskAge = (Get-Date) - (Get-Item -LiteralPath $taskPath).LastWriteTime
        if ($taskAge.TotalHours -gt $HandoffStaleHours) {
            Add-Result "WARN" "Handoff Drift" "CURRENT_TASK.md older than $HandoffStaleHours hours."
        }
        if (-not (Test-TextContains -Path $taskPath -Pattern "Next Exact Step")) {
            Add-Result "FAIL" "Handoff Drift" "CURRENT_TASK.md is missing 'Next Exact Step'."
        }
        if (-not ((Test-TextContains -Path $taskPath -Pattern "Known Risks") -or (Test-TextContains -Path $taskPath -Pattern "Open Risks"))) {
            Add-Result "WARN" "Handoff Drift" "CURRENT_TASK.md does not list known/open risks."
        }
        foreach ($deprecatedPath in @("D:\CODEX_PROJECTS", "E:\CODEX_PROJECTS", "E:\Gdrive")) {
            if ((Test-TextContains -Path $taskPath -Pattern $deprecatedPath) -and $ProjectPath -notlike "$deprecatedPath*") {
                Add-Result "WARN" "Path Drift" "CURRENT_TASK.md references possible stale path $deprecatedPath."
            }
        }
    }

    $snapshotDir = Join-Path -Path $ProjectPath -ChildPath "SNAPSHOT"
    if (Test-Path -LiteralPath $snapshotDir) {
        $latestSnapshot = Get-ChildItem -LiteralPath $snapshotDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $latestSnapshot) {
            Add-Result "WARN" "Handoff Drift" "SNAPSHOT folder exists but contains no files."
        }
    } else {
        Add-Result "WARN" "Handoff Drift" "SNAPSHOT folder is missing."
    }

    if (Test-Path -LiteralPath (Join-Path -Path $ProjectPath -ChildPath ".git")) {
        $branch = (& git -C $ProjectPath rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $branch -eq "HEAD") {
            Add-Result "FAIL" "Repo Drift" "Repository is in detached HEAD."
        }

        $status = @(& git -C $ProjectPath status --porcelain 2>$null)
        if ($LASTEXITCODE -eq 0 -and $status.Count -gt 0) {
            Add-Result "WARN" "Repo Drift" "Repository has uncommitted changes ($($status.Count) entries)."
        }

        $remote = (& git -C $ProjectPath remote 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($remote -join ""))) {
            Add-Result "WARN" "Repo Drift" "No remote configured."
        }

        $upstream = (& git -C $ProjectPath rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
            Add-Result "WARN" "Repo Drift" "No upstream tracking branch configured."
        } else {
            $counts = (& git -C $ProjectPath rev-list --left-right --count "HEAD...@{u}" 2>$null)
            if ($LASTEXITCODE -eq 0 -and $counts -match '^\s*(\d+)\s+(\d+)\s*$') {
                if ([int]$Matches[2] -gt 0) {
                    Add-Result "WARN" "Repo Drift" "Branch is behind upstream by $($Matches[2]) commits."
                }
            }
        }
    } else {
        Add-Result "WARN" "Repo Drift" "Project is not a git repository."
    }

    $claspPath = Join-Path -Path $ProjectPath -ChildPath ".clasp.json"
    if (Test-Path -LiteralPath $claspPath) {
        Add-Result "PASS" "Runtime Drift" ".clasp.json present; Apps Script drift hooks applicable."
        try {
            $clasp = Get-Content -LiteralPath $claspPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $clasp.PSObject.Properties["scriptId"] -or [string]::IsNullOrWhiteSpace([string]$clasp.scriptId)) {
                Add-Result "FAIL" "Runtime Drift" ".clasp.json has no scriptId."
            } elseif (-not (Select-String -Path (Join-Path -Path $ProjectPath -ChildPath "*") -Pattern ([string]$clasp.scriptId) -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
                Add-Result "WARN" "Runtime Drift" ".clasp.json scriptId is not visible in root docs; confirm runtime authority manually."
            }
        } catch {
            Add-Result "FAIL" "Runtime Drift" ".clasp.json is not valid JSON."
        }
        if (-not (Select-String -Path (Join-Path -Path $ProjectPath -ChildPath "*") -Pattern "script.google.com/macros/s/" -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
            Add-Result "WARN" "Runtime Drift" "No canonical Apps Script URL pattern found in root docs."
        }
        if (-not (Select-String -Path (Join-Path -Path $ProjectPath -ChildPath "*") -Pattern "whoami" -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
            Add-Result "WARN" "Runtime Drift" "No whoami URL/check mention found in root docs."
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($RegistryPath) -and (Test-Path -LiteralPath $RegistryPath)) {
    try {
        $registryProjects = @(Get-Content -LiteralPath $RegistryPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop)
        foreach ($project in $registryProjects) {
            if ($null -ne $project.PSObject.Properties["path"] -and -not [string]::IsNullOrWhiteSpace([string]$project.path)) {
                if (-not (Test-Path -LiteralPath ([string]$project.path))) {
                    Add-Result "WARN" "Path Drift" "Registry path missing for $($project.name): $($project.path)"
                }
            }
        }
    } catch {
        Add-Result "FAIL" "Path Drift" "projects.json could not be parsed."
    }
}

if (-not [string]::IsNullOrWhiteSpace($MachineProfilePath) -and (Test-Path -LiteralPath $MachineProfilePath)) {
    try {
        $profile = Get-Content -LiteralPath $MachineProfilePath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        $machineName = $env:COMPUTERNAME
        if ($profile.PSObject.Properties["machines"] -and $profile.machines.PSObject.Properties[$machineName]) {
            $machine = $profile.machines.PSObject.Properties[$machineName].Value
            if ($machine.PSObject.Properties["project_path_overrides"]) {
                foreach ($override in $machine.project_path_overrides.PSObject.Properties) {
                    if (-not (Test-Path -LiteralPath ([string]$override.Value))) {
                        Add-Result "WARN" "Path Drift" "Machine override path missing for $($override.Name): $($override.Value)"
                    }
                }
            }
        }
    } catch {
        Add-Result "WARN" "Path Drift" "Machine profile could not be parsed."
    }
}

if ($results.Count -eq 0) {
    Add-Result "PASS" "All" "No drift findings."
}

$rank = @{ "PASS" = 0; "WARN" = 1; "FAIL" = 2 }
$overall = "PASS"
foreach ($result in $results) {
    if ($rank[$result.Level] -gt $rank[$overall]) {
        $overall = $result.Level
    }
}

foreach ($result in $results) {
    Write-Host ("[{0}] {1}: {2}" -f $result.Level, $result.Area, $result.Reason)
}

Write-Host ""
Write-Host ("Overall: {0}" -f $overall)
if ($overall -eq "FAIL") { exit 2 }
if ($overall -eq "WARN") { exit 1 }
exit 0
