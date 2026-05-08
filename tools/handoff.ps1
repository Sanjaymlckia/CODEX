param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$ProjectName = "",
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$OperatorNote = $null,
    [switch]$ExitCodexHub,
    [switch]$SkipPause
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-OneLine {
    param([string]$Prompt)
    Write-Host -NoNewline ("{0}: " -f $Prompt)
    return [Console]::ReadLine()
}

function ConvertTo-SafeName {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "PROJECT" }
    return $safe
}

function Get-StatusColor {
    param([string]$Severity)
    switch ($Severity) {
        "GREEN" { return "Green" }
        "RED" { return "Red" }
        default { return "Yellow" }
    }
}

if (-not (Test-Path -LiteralPath $ProjectPath)) {
    throw "Project path not found: $ProjectPath"
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Path $ProjectPath -Leaf
}

Write-Host "Project files will NOT be modified." -ForegroundColor Yellow

$toolRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$hubRoot = Split-Path -Path $toolRoot -Parent
$expectedStateRoot = Join-Path -Path $hubRoot -ChildPath "state"
$expectedStateFullPath = [System.IO.Path]::GetFullPath($expectedStateRoot).TrimEnd('\')
$requestedStateFullPath = [System.IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
if (-not [string]::Equals($requestedStateFullPath, $expectedStateFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Auto-Handoff may write only to CodexHub state: $expectedStateFullPath"
}
$StateRoot = $expectedStateFullPath

$script:CODEXHUB_PROJECT_STATUS_IMPORT_ONLY = $true
. (Join-Path -Path $toolRoot -ChildPath "project-status.ps1") -ProjectPath $ProjectPath -ProjectName $ProjectName -StateRoot $StateRoot
Remove-Variable -Name CODEXHUB_PROJECT_STATUS_IMPORT_ONLY -Scope Script -ErrorAction SilentlyContinue

if ($null -eq $OperatorNote) {
    $operatorNote = Read-OneLine "Add one optional operator note? Leave blank to skip"
} else {
    $operatorNote = $OperatorNote
}
$status = New-ProjectStatus -Root $ProjectPath -Name $ProjectName
$safeProjectName = ConvertTo-SafeName -Value $ProjectName
if (-not (Test-Path -LiteralPath $StateRoot)) {
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
}

$handoffRoot = Join-Path -Path $StateRoot -ChildPath "handoffs"
if (-not (Test-Path -LiteralPath $handoffRoot)) {
    New-Item -ItemType Directory -Path $handoffRoot -Force | Out-Null
}

$handoffPath = Join-Path -Path $handoffRoot -ChildPath ("{0}_{1}_handoff.md" -f $status.timestamp_file, $safeProjectName)
$snapshotPath = Join-Path -Path $StateRoot -ChildPath ("{0}_snapshot.json" -f $safeProjectName)

ConvertTo-ProjectStatusMarkdown -Status $status -OperatorNote $operatorNote |
    Set-Content -LiteralPath $handoffPath -Encoding utf8

[pscustomobject]@{
    project = $status.project_name
    path = $status.project_path
    created_at = $status.timestamp
    machine = $status.machine_name
    user = $status.current_user
    severity = $status.severity
    git_branch = $status.git.branch
    git_status_sb = $status.git.status_sb
    git_dirty_state = $status.git.dirty_state
    ahead_behind = $status.git.ahead_behind
    latest_commit = $status.git.latest_commit
    current_objective = $status.governance.current_objective
    current_issue = $status.governance.current_issue
    next_exact_step = $status.governance.next_exact_step
    risks_blockers = $status.governance.risks_blockers
    agents_present = $status.governance.agents_present
    known_good_state_present = $status.governance.known_good_state_present
    apps_script_applicable = $status.apps_script.applicable
    apps_script_script_id = $status.apps_script.script_id
    apps_script_version = if ($null -ne $status.apps_script.config) { $status.apps_script.config.version } else { "" }
    apps_script_deploy_version_number = if ($null -ne $status.apps_script.config) { $status.apps_script.config.deploy_version_number } else { "" }
    apps_script_canonical_url_pattern_check = $status.apps_script.canonical_url_pattern_check
    apps_script_warnings = $status.apps_script.warnings
    handoff_path = $handoffPath
    operator_note = $operatorNote
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $snapshotPath -Encoding utf8

Write-Host ""
Write-Host ("Status: {0}" -f $status.severity) -ForegroundColor (Get-StatusColor -Severity $status.severity)
Write-Host ("Project path: {0}" -f $status.project_path)
Write-Host ("Git state: {0}; {1}" -f $status.git.dirty_state, $status.git.ahead_behind)
Write-Host ("Latest commit: {0}" -f $status.git.latest_commit)
Write-Host ("Next exact step: {0}" -f $(if ($status.governance.next_exact_step) { $status.governance.next_exact_step } else { "Not detected." }))
Write-Host ("Handoff file: {0}" -f $handoffPath) -ForegroundColor Cyan
Write-Host ("State mirror: {0}" -f $snapshotPath) -ForegroundColor DarkCyan
Write-Host ""

if ($ExitCodexHub) {
    exit 10
}

if (-not $SkipPause) {
    $exitAnswer = Read-OneLine "Exit CodexHub now? Y/N"
    if ($exitAnswer -match '^[Yy]$') {
        exit 10
    }
    [void](Read-OneLine "Press Enter to return to menu...")
}
exit 0
