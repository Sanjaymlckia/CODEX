param(
    [string]$ProjectPath = ".",
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-StringList {
    return New-Object System.Collections.Generic.List[string]
}

function Add-Warning {
    param(
        [System.Collections.Generic.List[string]]$Warnings,
        [string]$Message
    )
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $Warnings.Add($Message) | Out-Null
    }
}

function Invoke-GitRead {
    param(
        [string]$RepoRoot,
        [string[]]$GitArgs
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& git -C $RepoRoot @GitArgs 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }

    return [pscustomobject]@{
        code = $code
        output = @($output | ForEach-Object { [string]$_ })
        text = (@($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

function Get-FileHashSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    try {
        return [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    } catch {
        return ""
    }
}

function Get-CurrentTaskInfo {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $taskPath = Join-Path -Path $RepoRoot -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $taskPath)) {
        Add-Warning -Warnings $Warnings -Message "CURRENT_TASK.md not found."
        return [pscustomobject]@{
            path = $taskPath
            exists = $false
            last_write_utc = ""
            hash_sha256 = ""
            workspace_path = ""
            has_next_action = $false
            has_state_backup = $false
            state_backup_timestamp = ""
            state_backup_note = ""
            appears_current = $false
        }
    }

    $content = Get-Content -LiteralPath $taskPath -Encoding utf8
    $raw = $content -join "`n"
    $workspacePath = ""
    if ($raw -match '(?m)^\s*-\s*Workspace:\s*`?([^`\r\n]+)`?\s*$') {
        $workspacePath = $Matches[1].Trim()
    }

    $hasNextAction = ($raw -match '(?m)^##\s+Next Action\s*$')
    $hasStateBackup = ($raw -match '(?s)<!--\s*CODEXHUB_STATE_BACKUP_START\s*-->.*?<!--\s*CODEXHUB_STATE_BACKUP_END\s*-->')
    $stateBackupTimestamp = ""
    $stateBackupNote = ""
    if ($hasStateBackup) {
        $backupMatch = [regex]::Match($raw, '(?s)<!--\s*CODEXHUB_STATE_BACKUP_START\s*-->(.*?)<!--\s*CODEXHUB_STATE_BACKUP_END\s*-->')
        if ($backupMatch.Success) {
            $backupText = $backupMatch.Groups[1].Value
            if ($backupText -match '(?m)^\s*-\s*Last state backup timestamp:\s*(.+?)\s*$') {
                $stateBackupTimestamp = $Matches[1].Trim()
            }
            if ($backupText -match '(?m)^\s*-\s*Operator note:\s*(.+?)\s*$') {
                $stateBackupNote = $Matches[1].Trim()
            }
        }
    }
    $info = Get-Item -LiteralPath $taskPath
    return [pscustomobject]@{
        path = $taskPath
        exists = $true
        last_write_utc = $info.LastWriteTimeUtc.ToString("o")
        hash_sha256 = Get-FileHashSafe -Path $taskPath
        workspace_path = $workspacePath
        has_next_action = $hasNextAction
        has_state_backup = $hasStateBackup
        state_backup_timestamp = $stateBackupTimestamp
        state_backup_note = $stateBackupNote
        appears_current = $hasNextAction
    }
}

function Get-ReleaseTruthReference {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $path = Join-Path -Path $RepoRoot -ChildPath ".codexhub\release_truth\latest.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            path = $path
            exists = $false
            repo_root = ""
            branch = ""
            head = ""
            classification = ""
            timestamp_utc = ""
        }
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            path = $path
            exists = $true
            repo_root = if ($json.PSObject.Properties["repo_root"]) { [string]$json.repo_root } else { "" }
            branch = if ($json.PSObject.Properties["git"] -and $json.git.PSObject.Properties["branch"]) { [string]$json.git.branch } else { "" }
            head = if ($json.PSObject.Properties["git"] -and $json.git.PSObject.Properties["head"]) { [string]$json.git.head } else { "" }
            classification = if ($json.PSObject.Properties["classification"]) { [string]$json.classification } else { "" }
            timestamp_utc = if ($json.PSObject.Properties["timestamp_utc"]) { [string]$json.timestamp_utc } else { "" }
        }
    } catch {
        Add-Warning -Warnings $Warnings -Message "release_truth latest.json could not be parsed."
        return [pscustomobject]@{
            path = $path
            exists = $true
            repo_root = ""
            branch = ""
            head = ""
            classification = ""
            timestamp_utc = ""
        }
    }
}

function Get-ResumeStateReference {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $candidates = @(
        (Join-Path -Path $RepoRoot -ChildPath ".codexhub\resume_state\state.json"),
        (Join-Path -Path $RepoRoot -ChildPath "state\CodexHub_resume_state.json"),
        (Join-Path -Path $RepoRoot -ChildPath "state\CODEXHUB_resume_state.json")
    )

    $path = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $path) {
        return [pscustomobject]@{
            path = ""
            exists = $false
            machine = ""
            repo_path = ""
            branch = ""
            head = ""
            current_task_hash = ""
        }
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            path = $path
            exists = $true
            machine = if ($json.PSObject.Properties["machine"]) { [string]$json.machine } elseif ($json.PSObject.Properties["machine_name"]) { [string]$json.machine_name } else { "" }
            repo_path = if ($json.PSObject.Properties["repo_path"]) { [string]$json.repo_path } elseif ($json.PSObject.Properties["project_path"]) { [string]$json.project_path } else { "" }
            branch = if ($json.PSObject.Properties["branch"]) { [string]$json.branch } elseif ($json.PSObject.Properties["git"] -and $json.git.PSObject.Properties["branch"]) { [string]$json.git.branch } else { "" }
            head = if ($json.PSObject.Properties["head"]) { [string]$json.head } elseif ($json.PSObject.Properties["git"] -and $json.git.PSObject.Properties["head"]) { [string]$json.git.head } else { "" }
            current_task_hash = if ($json.PSObject.Properties["current_task_hash"]) { [string]$json.current_task_hash } else { "" }
        }
    } catch {
        Add-Warning -Warnings $Warnings -Message "local resume state file could not be parsed."
        return [pscustomobject]@{
            path = $path
            exists = $true
            machine = ""
            repo_path = ""
            branch = ""
            head = ""
            current_task_hash = ""
        }
    }
}

function Get-PathConsistency {
    param(
        [string]$RepoRoot,
        [object]$CurrentTaskInfo
    )

    $normalizedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $taskWorkspacePath = ""
    $taskMatches = $true

    if ($CurrentTaskInfo.exists -and -not [string]::IsNullOrWhiteSpace($CurrentTaskInfo.workspace_path)) {
        try {
            $taskWorkspacePath = [System.IO.Path]::GetFullPath($CurrentTaskInfo.workspace_path).TrimEnd('\')
            $taskMatches = ($taskWorkspacePath -ieq $normalizedRepoRoot)
        } catch {
            $taskWorkspacePath = $CurrentTaskInfo.workspace_path
            $taskMatches = $false
        }
    }

    $appearsUnderAuthorityRoot = $normalizedRepoRoot.StartsWith("E:\Gdrive\01_SANJAY\Codex_Sync", [System.StringComparison]::OrdinalIgnoreCase)

    [pscustomobject]@{
        repo_root = $normalizedRepoRoot
        current_task_workspace = $taskWorkspacePath
        current_task_matches_repo = $taskMatches
        under_authority_root = $appearsUnderAuthorityRoot
    }
}

function Get-ClassificationResult {
    param(
        [object]$GitInfo,
        [object]$CurrentTaskInfo,
        [object]$ReleaseTruthReference,
        [object]$ResumeStateReference,
        [object]$PathConsistency
    )

    if (-not $CurrentTaskInfo.exists) {
        return [pscustomobject]@{
            classification = "TASK_FILE_MISSING"
            confidence = "high"
            recommended_action = "Rebuild local context from repo files before resuming work."
            task_state = "missing"
        }
    }

    if (-not $PathConsistency.under_authority_root -or -not $PathConsistency.current_task_matches_repo) {
        return [pscustomobject]@{
            classification = "PATH_DRIFT"
            confidence = "high"
            recommended_action = "Stop and confirm the intended repo path before continuing."
            task_state = "drift"
        }
    }

    if ($ResumeStateReference.exists -and -not [string]::IsNullOrWhiteSpace($ResumeStateReference.machine) -and $ResumeStateReference.machine -ne $env:COMPUTERNAME) {
        return [pscustomobject]@{
            classification = "MACHINE_DRIFT"
            confidence = "high"
            recommended_action = "Reconfirm local state on this machine before resuming."
            task_state = "drift"
        }
    }

    $releaseConflict = $false
    if ($ReleaseTruthReference.exists) {
        if (-not [string]::IsNullOrWhiteSpace($ReleaseTruthReference.repo_root) -and $ReleaseTruthReference.repo_root -ne $PathConsistency.repo_root) {
            $releaseConflict = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($ReleaseTruthReference.head) -and -not [string]::IsNullOrWhiteSpace($GitInfo.head) -and $ReleaseTruthReference.head -ne $GitInfo.head) {
            $releaseConflict = $true
        }
    }

    $resumeConflict = $false
    if ($ResumeStateReference.exists) {
        if (-not [string]::IsNullOrWhiteSpace($ResumeStateReference.repo_path) -and $ResumeStateReference.repo_path -ne $PathConsistency.repo_root) {
            $resumeConflict = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($ResumeStateReference.head) -and -not [string]::IsNullOrWhiteSpace($GitInfo.head) -and $ResumeStateReference.head -ne $GitInfo.head) {
            $resumeConflict = $true
        }
    }

    if ($releaseConflict -and $resumeConflict) {
        return [pscustomobject]@{
            classification = "TRUST_RESET_REQUIRED"
            confidence = "medium"
            recommended_action = "Ignore prior session artifacts and reconstruct state from current repo files."
            task_state = "conflict"
        }
    }

    if ($ResumeStateReference.exists -and -not [string]::IsNullOrWhiteSpace($ResumeStateReference.current_task_hash) -and $ResumeStateReference.current_task_hash -ne $CurrentTaskInfo.hash_sha256) {
        return [pscustomobject]@{
            classification = "TASK_DRIFT"
            confidence = "medium"
            recommended_action = "Review CURRENT_TASK.md and refresh the local handoff context before resuming."
            task_state = "drift"
        }
    }

    if (-not $GitInfo.read_ok) {
        return [pscustomobject]@{
            classification = "INSUFFICIENT_DATA"
            confidence = "low"
            recommended_action = "Resolve local git read issues before trusting resume state."
            task_state = "unknown"
        }
    }

    if ($GitInfo.dirty) {
        $taskRecorded = $CurrentTaskInfo.appears_current -and (
            ($GitInfo.status_sb -match '(?m)^\s*[ MARCUD?!]{1,2}\s+CURRENT_TASK\.md\s*$') -or
            $CurrentTaskInfo.has_state_backup -or
            $ReleaseTruthReference.exists -or
            $ResumeStateReference.exists
        )

        if ($taskRecorded) {
            return [pscustomobject]@{
                classification = "DIRTY_BUT_RECORDED"
                confidence = "medium"
                recommended_action = "Continue carefully; local changes exist but task context is present."
                task_state = "current"
            }
        }

        return [pscustomobject]@{
            classification = "DIRTY_UNRECORDED"
            confidence = "medium"
            recommended_action = "Pause and update CURRENT_TASK.md or local handoff notes before continuing."
            task_state = "stale"
        }
    }

    return [pscustomobject]@{
        classification = "SAFE_RESUME"
        confidence = "high"
        recommended_action = "Safe to continue in the current local repo state."
        task_state = "current"
    }
}

$repoRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path -Path $repoRoot -ChildPath ".git"))) {
    throw "Run this script from a git repo root or pass -ProjectPath to a git repo root."
}

$warnings = New-StringList
$machine = $env:COMPUTERNAME
$gitBranch = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")
$gitHead = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("rev-parse", "HEAD")
$gitStatus = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("status", "-sb")
$gitPorcelain = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("status", "--porcelain")

$gitReadOk = ($gitBranch.code -eq 0 -and $gitHead.code -eq 0 -and $gitStatus.code -eq 0)
if (-not $gitReadOk) {
    Add-Warning -Warnings $warnings -Message "One or more local git reads failed."
}

$gitInfo = [pscustomobject]@{
    branch = $gitBranch.text
    head = $gitHead.text
    status_sb = $gitStatus.text
    dirty = ($gitPorcelain.code -eq 0 -and $gitPorcelain.output.Count -gt 0)
    read_ok = $gitReadOk
}

$currentTaskInfo = Get-CurrentTaskInfo -RepoRoot $repoRoot -Warnings $warnings
$releaseTruthReference = Get-ReleaseTruthReference -RepoRoot $repoRoot -Warnings $warnings
$resumeStateReference = Get-ResumeStateReference -RepoRoot $repoRoot -Warnings $warnings
$pathConsistency = Get-PathConsistency -RepoRoot $repoRoot -CurrentTaskInfo $currentTaskInfo
$result = Get-ClassificationResult -GitInfo $gitInfo -CurrentTaskInfo $currentTaskInfo -ReleaseTruthReference $releaseTruthReference -ResumeStateReference $resumeStateReference -PathConsistency $pathConsistency
$warningsArray = @($warnings | ForEach-Object { $_ })

$report = New-Object psobject
$report | Add-Member -NotePropertyName "machine" -NotePropertyValue $machine
$report | Add-Member -NotePropertyName "repo_path" -NotePropertyValue $pathConsistency.repo_root
$report | Add-Member -NotePropertyName "branch" -NotePropertyValue $gitInfo.branch
$report | Add-Member -NotePropertyName "head" -NotePropertyValue $gitInfo.head
$report | Add-Member -NotePropertyName "git_status" -NotePropertyValue $gitInfo.status_sb
$report | Add-Member -NotePropertyName "current_task" -NotePropertyValue $currentTaskInfo
$report | Add-Member -NotePropertyName "release_truth_reference" -NotePropertyValue $releaseTruthReference
$report | Add-Member -NotePropertyName "resume_state_reference" -NotePropertyValue $resumeStateReference
$report | Add-Member -NotePropertyName "warnings" -NotePropertyValue $warningsArray
$report | Add-Member -NotePropertyName "classification" -NotePropertyValue $result.classification
$report | Add-Member -NotePropertyName "confidence" -NotePropertyValue $result.confidence
$report | Add-Member -NotePropertyName "recommended_action" -NotePropertyValue $result.recommended_action

$reportDir = Join-Path -Path $repoRoot -ChildPath ".codexhub\resume_state"
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}
$reportPath = Join-Path -Path $reportDir -ChildPath "latest.json"
$json = $report | ConvertTo-Json -Depth 10
$json | Set-Content -LiteralPath $reportPath -Encoding utf8

if ($AsJson) {
    $json
    exit 0
}

$gitState = if ($gitInfo.dirty) { "dirty" } else { "clean" }
Write-Host ("Resume: {0} | Git: {1} | Task: {2} | Mode: LO" -f $result.classification, $gitState, $result.task_state)
Write-Host ("Repo: {0}" -f $pathConsistency.repo_root)
Write-Host ("Branch: {0} | HEAD: {1}" -f $(if ($gitInfo.branch) { $gitInfo.branch } else { "unknown" }), $(if ($gitInfo.head) { $gitInfo.head } else { "unknown" }))
Write-Host ("Confidence: {0} | Action: {1}" -f $result.confidence, $result.recommended_action)
if ($currentTaskInfo.has_state_backup) {
    Write-Host ("State backup: RECOGNIZED | Timestamp: {0} | Note: {1}" -f $(if ($currentTaskInfo.state_backup_timestamp) { $currentTaskInfo.state_backup_timestamp } else { "not recorded" }), $(if ($currentTaskInfo.state_backup_note) { $currentTaskInfo.state_backup_note } else { "not recorded" }))
}
if ($warnings.Count -gt 0) {
    Write-Host ("Warnings: {0}" -f ($warningsArray -join " | "))
}
Write-Host ("JSON: {0}" -f $reportPath)

