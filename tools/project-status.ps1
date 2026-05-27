param(
    [string]$ProjectPath = "",
    [string]$ProjectName = "",
    [string]$StateRoot = "",
    [ValidateSet("authoritative", "full")]
    [string]$CurrentTaskReadMode = "authoritative",
    [switch]$AsJson,
    [switch]$SaveStateBackup,
    [string]$OperatorNote = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function ConvertTo-SafeName {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "PROJECT" }
    return $safe
}

function Get-FilePresence {
    param([string]$Root, [string]$FileName)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    return (Test-Path -LiteralPath (Join-Path -Path $Root -ChildPath $FileName))
}

function Get-GitInfo {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath (Join-Path -Path $Root -ChildPath ".git"))) {
        return [pscustomobject]@{
            is_repo = $false
            branch = "no git"
            status_sb = "Not a git repository."
            latest_commit = ""
            latest_commit_hash = ""
            latest_commit_message = ""
            latest_staging_tag = ""
            changed_files = @()
            upstream = ""
            ahead = $null
            behind = $null
            ahead_behind = "unavailable"
            dirty = $false
            dirty_state = "NO-GIT"
        }
    }

    function Invoke-GitRead {
        param([string[]]$GitArgs)
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = @(& git -C $Root @GitArgs 2>&1)
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        return [pscustomobject]@{
            code = $code
            output = @($output | ForEach-Object { [string]$_ })
        }
    }

    $branchResult = Invoke-GitRead -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")
    $branch = ($branchResult.output -join "`n").Trim()
    if ($branchResult.code -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        $gitError = "git command failed; possible safe.directory or permission issue"
        return [pscustomobject]@{
            is_repo = $true
            branch = "unknown"
            status_sb = $gitError
            latest_commit = ""
            latest_commit_hash = ""
            latest_commit_message = ""
            latest_staging_tag = ""
            changed_files = @()
            upstream = ""
            ahead = $null
            behind = $null
            ahead_behind = "unavailable"
            dirty = $false
            dirty_state = "UNKNOWN"
        }
    }

    $statusResult = Invoke-GitRead -GitArgs @("status", "-sb")
    $statusSb = if ($statusResult.code -eq 0) { $statusResult.output -join "`n" } else { "git status failed." }

    $porcelainResult = Invoke-GitRead -GitArgs @("status", "--porcelain")
    $dirty = ($porcelainResult.code -eq 0 -and $porcelainResult.output.Count -gt 0)

    $commitHashResult = Invoke-GitRead -GitArgs @("rev-parse", "--short", "HEAD")
    $commitHash = if ($commitHashResult.code -eq 0) { ($commitHashResult.output -join "`n").Trim() } else { "" }
    $commitMessageResult = Invoke-GitRead -GitArgs @("log", "-1", "--pretty=%s")
    $commitMessage = if ($commitMessageResult.code -eq 0) { ($commitMessageResult.output -join "`n").Trim() } else { "" }
    $changedFiles = if ($porcelainResult.code -eq 0) {
        @($porcelainResult.output | ForEach-Object {
            if ($_.Length -gt 3) { $_.Substring(3).Trim() } else { $_.Trim() }
        })
    } else {
        @("Unable to read changed files.")
    }
    $tagResult = Invoke-GitRead -GitArgs @("tag", "--list", "--sort=-creatordate")
    $latestStagingTag = if ($tagResult.code -eq 0) {
        [string](@($tagResult.output | Where-Object { $_ -match '(?i)staging' } | Select-Object -First 1) -join "")
    } else {
        ""
    }

    $upstreamResult = Invoke-GitRead -GitArgs @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    $upstream = ($upstreamResult.output -join "`n").Trim()
    $ahead = $null
    $behind = $null
    $aheadBehind = "unavailable"
    if ($upstreamResult.code -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstream)) {
        $countsResult = Invoke-GitRead -GitArgs @("rev-list", "--left-right", "--count", "HEAD...@{u}")
        $counts = ($countsResult.output -join "`n").Trim()
        if ($countsResult.code -eq 0 -and $counts -match '^\s*(\d+)\s+(\d+)\s*$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
            $aheadBehind = "ahead $ahead, behind $behind"
        }
    } else {
        $upstream = ""
    }

    return [pscustomobject]@{
        is_repo = $true
        branch = [string]$branch
        status_sb = $statusSb
        latest_commit = ("{0} {1}" -f $commitHash, $commitMessage).Trim()
        latest_commit_hash = [string]$commitHash
        latest_commit_message = [string]$commitMessage
        latest_staging_tag = $latestStagingTag
        changed_files = @($changedFiles)
        upstream = [string]$upstream
        ahead = $ahead
        behind = $behind
        ahead_behind = $aheadBehind
        dirty = $dirty
        dirty_state = if ($dirty) { "DIRTY" } else { "CLEAN" }
    }
}

function Get-CurrentTaskInfo {
    param(
        [string]$Root,
        [ValidateSet("authoritative", "full")]
        [string]$ReadMode = "authoritative"
    )

    $taskPath = Join-Path -Path $Root -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $taskPath)) {
        return [pscustomobject]@{
            path = $taskPath
            exists = $false
            first_60_lines = @()
            current_runtime = ""
            latest_accepted_release = ""
            current_objective = ""
            current_issue = ""
            next_exact_step = ""
            current_release_track = ""
            risks_blockers = @()
        }
    }

    $lines = @(Get-Content -LiteralPath $taskPath -Encoding utf8)

    function Read-Section {
        param([string[]]$SourceLines, [string]$Heading)
        $start = -1
        for ($i = 0; $i -lt $SourceLines.Count; $i++) {
            if ($SourceLines[$i] -match ("^\s*#{1,6}\s*" + [regex]::Escape($Heading) + "\s*$")) {
                $start = $i + 1
                break
            }
        }
        if ($start -lt 0) { return "" }
        $collected = New-Object System.Collections.Generic.List[string]
        for ($i = $start; $i -lt $SourceLines.Count; $i++) {
            if ($SourceLines[$i] -match '^\s*#{1,6}\s+\S') { break }
            if (-not [string]::IsNullOrWhiteSpace($SourceLines[$i])) {
                $collected.Add($SourceLines[$i].Trim()) | Out-Null
            }
        }
        return ($collected -join "`n").Trim()
    }

    function Read-PreferredSection {
        param([string[]]$SourceLines, [string[]]$Headings)
        foreach ($heading in $Headings) {
            $value = Read-Section -SourceLines $SourceLines -Heading $heading
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
        return ""
    }

    $riskLines = @(
        (Read-PreferredSection -SourceLines $lines -Headings @("Active Blockers", "Known Risks", "Risks / Blockers", "Open Risks")) -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [string]$_.Trim() }
    )

    if ($riskLines.Count -eq 0 -and $ReadMode -eq "full") {
        $riskLines = @($lines |
            Where-Object { [string]$_ -match '(?i)risk|blocker|caution|warning|manual required|pending|blocked' } |
            Select-Object -First 20 |
            ForEach-Object { [string]$_ })
    }

    $first60 = if ($ReadMode -eq "full") { @($lines | Select-Object -First 60) } else { @() }

    return [pscustomobject]@{
        path = $taskPath
        exists = $true
        first_60_lines = $first60
        current_runtime = Read-PreferredSection -SourceLines $lines -Headings @("Current Runtime", "Runtime", "Current State")
        latest_accepted_release = Read-PreferredSection -SourceLines $lines -Headings @("Latest Accepted Release", "Accepted Release", "Last Accepted Release")
        current_objective = Read-PreferredSection -SourceLines $lines -Headings @("Current Objective", "Objective")
        current_issue = Read-PreferredSection -SourceLines $lines -Headings @("Current Issue", "Problem")
        next_exact_step = Read-PreferredSection -SourceLines $lines -Headings @("Next Action", "Next Exact Step")
        current_release_track = Read-PreferredSection -SourceLines $lines -Headings @("Current Release Track", "Release Track")
        risks_blockers = $riskLines
    }
}

function Get-ConfigVersionInfo {
    param([string]$Root)

    $configPath = Join-Path -Path $Root -ChildPath "Config.js"
    $version = ""
    $deployVersion = ""
    if (Test-Path -LiteralPath $configPath) {
        $text = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
        if ($text -match "(?m)\bVERSION\b\s*[:=]\s*['""]([^'""]+)['""]") { $version = $Matches[1] }
        if ($text -match "(?m)\bDEPLOY_VERSION_NUMBER\b\s*[:=]\s*([0-9]+)") { $deployVersion = $Matches[1] }
    }

    return [pscustomobject]@{
        path = $configPath
        exists = (Test-Path -LiteralPath $configPath)
        version = $version
        deploy_version_number = $deployVersion
    }
}

function Get-AppsScriptInfo {
    param([string]$Root, [object]$GitInfo)

    $claspPath = Join-Path -Path $Root -ChildPath ".clasp.json"
    $scriptId = ""
    $claspExists = Test-Path -LiteralPath $claspPath
    if ($claspExists) {
        try {
            $clasp = Get-Content -LiteralPath $claspPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
            if ($clasp.PSObject.Properties["scriptId"]) { $scriptId = [string]$clasp.scriptId }
        } catch {
            $scriptId = "INVALID_JSON"
        }
    }

    $config = Get-ConfigVersionInfo -Root $Root
    $files = @("CURRENT_TASK.md", "LIVE_URLS.md", "Config.js", "Admin.js", "AdminUI.html", "Code.js") |
        ForEach-Object { Join-Path -Path $Root -ChildPath $_ } |
        Where-Object { Test-Path -LiteralPath $_ }
    $joinedText = ""
    foreach ($file in $files) {
        $joinedText += "`n" + (Get-Content -LiteralPath $file -Raw -Encoding utf8)
    }

    $canonicalMatches = [regex]::Matches($joinedText, "https://script\.google\.com/macros/s/[^/\s`"']+/exec").Count
    $workspaceDomainMatches = [regex]::Matches($joinedText, "https://script\.google\.com/a/[^/\s`"']+/macros/s/").Count
    $canonicalStatus = if ($workspaceDomainMatches -gt 0) {
        "WARN: workspace-domain Apps Script URL found"
    } elseif ($canonicalMatches -gt 0) {
        "PASS: canonical /macros/s/<DEPLOYMENT_ID>/exec URL pattern found"
    } else {
        "WARN: no canonical Apps Script deployment URL found in checked root files"
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($GitInfo.dirty) { $warnings.Add("git state is dirty") | Out-Null }
    if ($GitInfo.dirty_state -eq "UNKNOWN") { $warnings.Add("git state could not be read") | Out-Null }
    if ($null -ne $GitInfo.ahead -and $GitInfo.ahead -gt 0) { $warnings.Add("repo is ahead and not pushed") | Out-Null }
    if ($workspaceDomainMatches -gt 0) { $warnings.Add("workspace-domain Apps Script URL present") | Out-Null }

    return [pscustomobject]@{
        applicable = $claspExists -or $config.exists
        clasp_path = $claspPath
        clasp_exists = $claspExists
        script_id = $scriptId
        config = $config
        canonical_url_pattern_check = $canonicalStatus
        warnings = @($warnings)
    }
}

function New-ProjectStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Name = ""
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = Split-Path -Path $Root -Leaf }
    $exists = Test-Path -LiteralPath $Root
    $git = if ($exists) { Get-GitInfo -Root $Root } else { [pscustomobject]@{ is_repo = $false; branch = "missing"; status_sb = "Project path not found."; latest_commit = ""; latest_commit_hash = ""; latest_commit_message = ""; latest_staging_tag = ""; changed_files = @(); upstream = ""; ahead = $null; behind = $null; ahead_behind = "unavailable"; dirty = $false; dirty_state = "MISSING" } }
    $task = if ($exists) { Get-CurrentTaskInfo -Root $Root -ReadMode $CurrentTaskReadMode } else { [pscustomobject]@{ path = (Join-Path -Path $Root -ChildPath "CURRENT_TASK.md"); exists = $false; first_60_lines = @(); current_runtime = ""; latest_accepted_release = ""; current_objective = ""; current_issue = ""; next_exact_step = ""; current_release_track = ""; risks_blockers = @() } }
    $apps = if ($exists) { Get-AppsScriptInfo -Root $Root -GitInfo $git } else { [pscustomobject]@{ applicable = $false; clasp_path = ""; clasp_exists = $false; script_id = ""; config = $null; canonical_url_pattern_check = "not checked"; warnings = @() } }

    $agentsPresent = if ($exists) { Get-FilePresence -Root $Root -FileName "AGENTS.md" } else { $false }
    $knownGoodPresent = if ($exists) { Get-FilePresence -Root $Root -FileName "KNOWN_GOOD_STATE.md" } else { $false }

    $severity = "GREEN"
    if (-not $exists -or ($git.branch -eq "HEAD")) {
        $severity = "RED"
    } elseif ($git.dirty -or $git.dirty_state -eq "UNKNOWN" -or ($null -ne $git.ahead -and $git.ahead -gt 0) -or ($null -ne $git.behind -and $git.behind -gt 0) -or -not $task.exists -or -not $agentsPresent -or -not $knownGoodPresent -or ($apps.warnings.Count -gt 0)) {
        $severity = "AMBER"
    }

    return [pscustomobject]@{
        project_name = $Name
        project_path = $Root
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        timestamp_file = (Get-Date).ToString("yyyyMMdd_HHmmss")
        machine_name = $env:COMPUTERNAME
        current_user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        severity = $severity
        git = $git
        governance = [pscustomobject]@{
            current_task = $task
            current_runtime = $task.current_runtime
            latest_accepted_release = $task.latest_accepted_release
            current_objective = $task.current_objective
            current_issue = $task.current_issue
            next_exact_step = $task.next_exact_step
            current_release_track = $task.current_release_track
            risks_blockers = $task.risks_blockers
            agents_present = $agentsPresent
            known_good_state_present = $knownGoodPresent
        }
        apps_script = $apps
    }
}

function ConvertTo-ProjectStatusMarkdown {
    param(
        [Parameter(Mandatory = $true)][object]$Status,
        [string]$OperatorNote = ""
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# CodexHub Auto-Handoff") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add(("Status: {0}" -f $Status.severity)) | Out-Null
    $lines.Add(("Project: {0}" -f $Status.project_name)) | Out-Null
    $lines.Add(("Path: {0}" -f $Status.project_path)) | Out-Null
    $lines.Add(("Created: {0}" -f $Status.timestamp)) | Out-Null
    $lines.Add(("Machine: {0}" -f $Status.machine_name)) | Out-Null
    $lines.Add(("User: {0}" -f $Status.current_user)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($OperatorNote)) {
        $lines.Add(("Operator note: {0}" -f $OperatorNote.Trim())) | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("## Git") | Out-Null
    $lines.Add(("- Branch: {0}" -f $Status.git.branch)) | Out-Null
    $lines.Add(("- Dirty state: {0}" -f $Status.git.dirty_state)) | Out-Null
    $lines.Add(("- Ahead/behind: {0}" -f $Status.git.ahead_behind)) | Out-Null
    $lines.Add(("- Latest commit: {0}" -f $Status.git.latest_commit)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("```text") | Out-Null
    $lines.Add($Status.git.status_sb) | Out-Null
    $lines.Add('```') | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("## Governance") | Out-Null
    $lines.Add(("- AGENTS.md present: {0}" -f $Status.governance.agents_present)) | Out-Null
    $lines.Add(("- KNOWN_GOOD_STATE.md present: {0}" -f $Status.governance.known_good_state_present)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Current Objective") | Out-Null
    $lines.Add($(if ($Status.governance.current_objective) { $Status.governance.current_objective } else { "Not detected." })) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Current Runtime") | Out-Null
    $lines.Add($(if ($Status.governance.current_runtime) { $Status.governance.current_runtime } else { "Not detected." })) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Current Issue") | Out-Null
    $lines.Add($(if ($Status.governance.current_issue) { $Status.governance.current_issue } else { "Not detected." })) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Next Exact Step") | Out-Null
    $lines.Add($(if ($Status.governance.next_exact_step) { $Status.governance.next_exact_step } else { "Not detected." })) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Latest Accepted Release") | Out-Null
    $lines.Add($(if ($Status.governance.latest_accepted_release) { $Status.governance.latest_accepted_release } else { "Not detected." })) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("### Risks / Blockers") | Out-Null
    if ($Status.governance.risks_blockers.Count -gt 0) {
        foreach ($risk in $Status.governance.risks_blockers) { $lines.Add($risk) | Out-Null }
    } else {
        $lines.Add("None detected.") | Out-Null
    }
    if ($Status.governance.current_task.first_60_lines.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### First 60 Lines Of CURRENT_TASK.md") | Out-Null
        $lines.Add("```md") | Out-Null
        foreach ($line in $Status.governance.current_task.first_60_lines) { $lines.Add($line) | Out-Null }
        $lines.Add('```') | Out-Null
    }

    if ($Status.apps_script.applicable) {
        $lines.Add("") | Out-Null
        $lines.Add("## Apps Script") | Out-Null
        $lines.Add(("- .clasp.json scriptId: {0}" -f $Status.apps_script.script_id)) | Out-Null
        $lines.Add(("- Config.js VERSION: {0}" -f $Status.apps_script.config.version)) | Out-Null
        $lines.Add(("- Config.js DEPLOY_VERSION_NUMBER: {0}" -f $Status.apps_script.config.deploy_version_number)) | Out-Null
        $lines.Add(("- Canonical URL check: {0}" -f $Status.apps_script.canonical_url_pattern_check)) | Out-Null
        if ($Status.apps_script.warnings.Count -gt 0) {
            $lines.Add("") | Out-Null
            $lines.Add("### Warnings") | Out-Null
            foreach ($warning in $Status.apps_script.warnings) { $lines.Add(("- {0}" -f $warning)) | Out-Null }
        }
    }

    return ($lines -join "`n")
}

function Format-BackupValue {
    param([string]$Value, [string]$Fallback = "Not detected.")
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    return $Value.Trim()
}

function ConvertTo-StateBackupBlock {
    param(
        [Parameter(Mandatory = $true)][object]$Status,
        [string]$OperatorNote = ""
    )

    $changedFiles = if ($Status.git.changed_files.Count -gt 0) {
        ($Status.git.changed_files | ForEach-Object { "- ``{0}``" -f $_ }) -join "`n"
    } else {
        "- None."
    }
    $configVersion = "Not applicable."
    if ($Status.apps_script.config -and $Status.apps_script.config.exists) {
        $version = Format-BackupValue -Value $Status.apps_script.config.version
        $deploy = Format-BackupValue -Value $Status.apps_script.config.deploy_version_number
        $configVersion = "VERSION: $version; DEPLOY_VERSION_NUMBER: $deploy"
    }
    $blocker = if ($Status.governance.risks_blockers.Count -gt 0) {
        $Status.governance.risks_blockers[0]
    } else {
        Format-BackupValue -Value $Status.governance.current_issue -Fallback "None detected."
    }
    $note = Format-BackupValue -Value $OperatorNote -Fallback "[add operator note]"

    return @(
        "<!-- CODEXHUB_STATE_BACKUP_START -->",
        "## CodexHub State Backup",
        "",
        ("- Last state backup timestamp: {0}" -f $Status.timestamp),
        ("- Project path: ``{0}``" -f $Status.project_path),
        ("- Repository state: {0}" -f $Status.git.dirty_state),
        ("- Current branch: ``{0}``" -f (Format-BackupValue -Value $Status.git.branch)),
        ("- Latest commit: ``{0}``" -f (Format-BackupValue -Value $Status.git.latest_commit)),
        ("- Latest matching staging tag: ``{0}``" -f (Format-BackupValue -Value $Status.git.latest_staging_tag -Fallback "Not found.")),
        ("- Config version / deploy number: {0}" -f $configVersion),
        ("- Current release track: {0}" -f (Format-BackupValue -Value $Status.governance.current_release_track)),
        ("- Current blocker: {0}" -f $blocker),
        ("- Next exact action: {0}" -f (Format-BackupValue -Value $Status.governance.next_exact_step)),
        ("- Operator note: {0}" -f $note),
        "",
        "### Git Status",
        '```text',
        $Status.git.status_sb,
        '```',
        "",
        "### Changed Files",
        $changedFiles,
        "<!-- CODEXHUB_STATE_BACKUP_END -->"
    ) -join "`n"
}

function Save-ProjectStateBackup {
    param(
        [Parameter(Mandatory = $true)][object]$Status,
        [string]$OperatorNote = ""
    )

    if (-not $Status.governance.current_task.exists) {
        throw "CURRENT_TASK.md is missing. State backup will not create it without operator approval."
    }

    $taskPath = $Status.governance.current_task.path
    $existing = Get-Content -LiteralPath $taskPath -Raw -Encoding utf8
    $block = ConvertTo-StateBackupBlock -Status $Status -OperatorNote $OperatorNote
    $pattern = '(?s)<!-- CODEXHUB_STATE_BACKUP_START -->.*?<!-- CODEXHUB_STATE_BACKUP_END -->'

    if ($existing -match $pattern) {
        $updated = [regex]::Replace($existing, $pattern, $block, 1)
    } elseif ($existing -match '^(# [^\r\n]+)(\r?\n)') {
        $updated = $existing -replace '^(# [^\r\n]+)(\r?\n)', ("`$1`$2`$2" + $block + "`$2")
    } else {
        $updated = $block + "`n`n" + $existing
    }

    Set-Content -LiteralPath $taskPath -Value $updated -Encoding utf8 -NoNewline
    Write-Host ("State backup updated: {0}" -f $taskPath)
    Write-Host "Only the CODEXHUB_STATE_BACKUP marker block was created or replaced."
}

function Invoke-ProjectStatusCommand {
    param(
        [string]$ProjectPath,
        [string]$ProjectName,
        [string]$StateRoot,
        [switch]$AsJson,
        [switch]$SaveStateBackup,
        [string]$OperatorNote = ""
    )

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { throw "ProjectPath is required." }
    $status = New-ProjectStatus -Root $ProjectPath -Name $ProjectName
    if ($SaveStateBackup) {
        Save-ProjectStateBackup -Status $status -OperatorNote $OperatorNote
        return
    }
    if ($AsJson) {
        $status | ConvertTo-Json -Depth 10
        return
    }

    Write-Host ("Status: {0}" -f $status.severity)
    Write-Host ("Project path: {0}" -f $status.project_path)
    Write-Host ("Git state: {0}; {1}" -f $status.git.dirty_state, $status.git.ahead_behind)
    Write-Host ("Latest commit: {0}" -f $status.git.latest_commit)
    Write-Host ("Current objective: {0}" -f $(if ($status.governance.current_objective) { $status.governance.current_objective } else { "Not detected." }))
    Write-Host ("Next exact step: {0}" -f $(if ($status.governance.next_exact_step) { $status.governance.next_exact_step } else { "Not detected." }))
}

$importOnly = $false
$importFlag = Get-Variable -Name CODEXHUB_PROJECT_STATUS_IMPORT_ONLY -Scope Script -ErrorAction SilentlyContinue
if ($null -ne $importFlag -and [bool]$importFlag.Value) {
    $importOnly = $true
}

if (-not $importOnly) {
    Invoke-ProjectStatusCommand -ProjectPath $ProjectPath -ProjectName $ProjectName -StateRoot $StateRoot -AsJson:$AsJson -SaveStateBackup:$SaveStateBackup -OperatorNote $OperatorNote
}
