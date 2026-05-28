param(
    [string]$ProjectName = "FODE_RUNTIME",
    [switch]$AuthorityOnly
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Error "PowerShell 7 is required. Install or launch pwsh before running CodexHub."
        exit 1
    }

    Write-Host "Windows PowerShell 5.1 detected. Re-launching CodexHub under PowerShell 7."
    $forwardArgs = @()
    if ($PSBoundParameters.ContainsKey("ProjectName")) { $forwardArgs += @("-ProjectName", $ProjectName) }
    if ($AuthorityOnly) { $forwardArgs += "-AuthorityOnly" }
    $forwardArgs += $args
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forwardArgs
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-HubRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Invoke-GitRead {
    param(
        [string]$Root,
        [string[]]$Arguments
    )

    try {
        $output = @(& git -C $Root @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) { return "" }
        return ($output -join "`n").Trim()
    } catch {
        return ""
    }
}

function Read-MatchingLines {
    param(
        [string]$Path,
        [string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $matches = Select-String -Path $Path -Pattern $Pattern -Encoding utf8 |
        Where-Object { $_.Line -notmatch '^\s*//' } |
        Select-Object -First 4
    if ($null -eq $matches) { return "" }
    return (($matches | ForEach-Object { $_.Line.Trim() }) -join " / ")
}

function Read-TaskSummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return "not present" }

    $lines = Get-Content -LiteralPath $Path -Encoding utf8
    $wanted = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^(##\s+(Current Objective|Current State|Next Action|Active Blockers|Latest Accepted Release)|Last resume:|Next exact step:)') {
            $wanted.Add($line.Trim()) | Out-Null
        }
        if ($wanted.Count -ge 8) { break }
    }

    if ($wanted.Count -eq 0) {
        return (($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 5) -join " / ")
    }

    return ($wanted -join " / ")
}

function Get-NearbyCurrentTasks {
    param(
        [string]$AuthorityRoot,
        [string]$ProjectPath
    )

    if (-not (Test-Path -LiteralPath $AuthorityRoot)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $AuthorityRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path -Path $_.FullName -ChildPath "CURRENT_TASK.md" } |
            Where-Object { (Test-Path -LiteralPath $_) -and ([string]$_ -ne (Join-Path -Path $ProjectPath -ChildPath "CURRENT_TASK.md")) }
    )
}

$hubRoot = Get-HubRoot
$registryPath = Join-Path -Path $hubRoot -ChildPath "projects\projects.json"
$config = Get-Content -LiteralPath $registryPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
$project = @($config.projects | Where-Object { [string]$_.name -eq $ProjectName } | Select-Object -First 1)
if ($project.Count -eq 0) {
    throw "Project not found in registry: $ProjectName"
}
$project = $project[0]

$registeredRoot = Join-Path -Path ([string]$config.authority_root) -ChildPath ([string]$project.folder)
$authorityTool = Join-Path -Path $hubRoot -ChildPath "tools\local_authority_check.ps1"
if (Test-Path -LiteralPath $authorityTool) {
    $callerProjectName = $ProjectName
    $callerAuthorityOnly = $AuthorityOnly
    . $authorityTool
    $ProjectName = $callerProjectName
    $AuthorityOnly = $callerAuthorityOnly
    $authority = Test-LocalAuthority -ProjectRoot $registeredRoot -ExpectedRemote ([string]$project.remote) -Mode "LO"
    if ($authority.status -notin @("LOCAL_AUTHORITY_OK", "LOCAL_AUTHORITY_DIRTY_RECORDED")) {
        Write-Host $authority.status
        Write-Host $authority.message
        Write-Host ("Remote proof: {0} - {1}" -f $authority.remote_proof.status, $authority.remote_proof.reason)
        throw "Refresh context stopped because local authority is not established."
    }
}
$taskPath = Join-Path -Path $registeredRoot -ChildPath "CURRENT_TASK.md"
$agentsPath = Join-Path -Path $registeredRoot -ChildPath "AGENTS.md"
$configPath = Join-Path -Path $registeredRoot -ChildPath "Config.js"
$isGit = Test-Path -LiteralPath (Join-Path -Path $registeredRoot -ChildPath ".git")
$actualGitRoot = if ($isGit) { Invoke-GitRead -Root $registeredRoot -Arguments @("rev-parse", "--show-toplevel") } else { "not a git repository" }
$status = if ($isGit) { Invoke-GitRead -Root $registeredRoot -Arguments @("status", "-sb") } else { "NO-GIT" }
$log = if ($isGit) { Invoke-GitRead -Root $registeredRoot -Arguments @("log", "--oneline", "-5") } else { "" }
$tag = if ($isGit) {
    $stagingTag = Invoke-GitRead -Root $registeredRoot -Arguments @("tag", "--list", "staging-*", "--sort=-creatordate")
    if (-not [string]::IsNullOrWhiteSpace($stagingTag)) {
        ($stagingTag -split "`n" | Select-Object -First 1).Trim()
    } else {
        Invoke-GitRead -Root $registeredRoot -Arguments @("describe", "--tags", "--abbrev=0")
    }
} else {
    ""
}

$dirtyFiles = if ($isGit) { Invoke-GitRead -Root $registeredRoot -Arguments @("status", "--porcelain") } else { "" }
$rootMatches = if ($isGit -and -not [string]::IsNullOrWhiteSpace($actualGitRoot)) {
    ([System.IO.Path]::GetFullPath($actualGitRoot).TrimEnd('\') -eq [System.IO.Path]::GetFullPath($registeredRoot).TrimEnd('\'))
} else {
    (Test-Path -LiteralPath $registeredRoot)
}

$oldPathWarnings = New-Object System.Collections.Generic.List[string]
foreach ($path in @($taskPath, $agentsPath, $configPath)) {
    if (Test-Path -LiteralPath $path) {
        # Detect stale legacy FODE/Codex roots only. The active authority root is E:\Gdrive\01_SANJAY\Codex_Sync.
        $matches = Select-String -Path $path -Pattern 'E:\\Gdrive\\01 SANJAY\\Codex_Sync|C:\\FODE_Runtime_1wog|D:\\CODEX_PROJECTS\\FODE_Runtime' -Encoding utf8 -ErrorAction SilentlyContinue
        foreach ($match in @($matches)) {
            $oldPathWarnings.Add(("{0}:{1}" -f $path, $match.LineNumber)) | Out-Null
        }
    }
}

$nearbyTasks = Get-NearbyCurrentTasks -AuthorityRoot ([string]$config.authority_root) -ProjectPath $registeredRoot
$versionLine = Read-MatchingLines -Path $configPath -Pattern 'VERSION|DEPLOY_VERSION_NUMBER'
$warnings = New-Object System.Collections.Generic.List[string]
if (-not $rootMatches) { $warnings.Add("actual git root does not match registered root; block mutation unless explicitly overridden") | Out-Null }
if ($oldPathWarnings.Count -gt 0) { $warnings.Add(("old path references detected: {0}" -f ($oldPathWarnings -join ", "))) | Out-Null }
if ($nearbyTasks.Count -gt 0) { $warnings.Add(("nearby CURRENT_TASK.md files exist under authority root: {0}" -f ($nearbyTasks.Count))) | Out-Null }
if ($AuthorityOnly) { $warnings.Add("authority-only check; no release whoami was queried") | Out-Null }

Write-Host "Project: $($project.display_name) [$($project.name)]"
Write-Host "Registered root: $registeredRoot"
Write-Host "Actual git root: $actualGitRoot"
Write-Host "Root matches registry: $rootMatches"
Write-Host "Git state:"
Write-Host $status
Write-Host "Latest release/tag: $tag"
if (-not [string]::IsNullOrWhiteSpace($versionLine)) {
    Write-Host "Runtime version: $versionLine"
}
Write-Host "Authoritative CURRENT_TASK.md: $taskPath"
Write-Host ("AGENTS.md: {0}" -f ($(if (Test-Path -LiteralPath $agentsPath) { $agentsPath } else { "not present" })))
Write-Host "Dirty files:"
if ([string]::IsNullOrWhiteSpace($dirtyFiles)) { Write-Host "none" } else { Write-Host $dirtyFiles }
Write-Host "Recent commits:"
if ([string]::IsNullOrWhiteSpace($log)) { Write-Host "unavailable" } else { Write-Host $log }
Write-Host "Current task:"
Write-Host (Read-TaskSummary -Path $taskPath)
Write-Host "Warnings:"
if ($warnings.Count -eq 0) { Write-Host "none" } else { foreach ($warning in $warnings) { Write-Host ("- {0}" -f $warning) } }
Write-Host "Next safe step: read-only refresh is complete; edit only after confirming the registered root and current task."
