param(
    [ValidateSet("LIGHT", "FULL_AUDIT")]
    [string]$OperationalMode = "LIGHT",
    [switch]$SelfTest
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Error "PowerShell 7 is required. Install or launch pwsh before running CodexHub."
        exit 1
    }

    Write-Host "Windows PowerShell 5.1 detected. Re-launching CodexHub under PowerShell 7."
    $forwardArgs = @()
    if ($PSBoundParameters.ContainsKey("OperationalMode")) { $forwardArgs += @("-OperationalMode", $OperationalMode) }
    if ($SelfTest) { $forwardArgs += "-SelfTest" }
    $forwardArgs += $args
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forwardArgs
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-HubRoot {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw "PSScriptRoot is unavailable."
    }

    return $PSScriptRoot
}

function Get-RegistryPath {
    return Join-Path -Path (Get-HubRoot) -ChildPath "projects\projects.json"
}

function Get-LocalAuthorityToolPath {
    return Join-Path -Path (Get-HubRoot) -ChildPath "tools\local_authority_check.ps1"
}

function Get-StateRoot {
    return Join-Path -Path (Get-HubRoot) -ChildPath "state"
}

function Get-LastProjectPath {
    return Join-Path -Path (Get-StateRoot) -ChildPath "last_project.txt"
}

function Get-ResumeStatePath {
    param([string]$ProjectName)

    return Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_resume_state.json" -f $ProjectName)
}

function Get-ProjectStatePath {
    param(
        [string]$ProjectName,
        [string]$Suffix
    )

    return Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_{1}" -f $ProjectName, $Suffix)
}


function Get-LocalMachineConfigPath {
    return Join-Path -Path (Get-HubRoot) -ChildPath "state\local\machine.local.json"
}

function Resolve-AuthorityRoot {
    param(
        [object]$Config
    )

    $localPath = Get-LocalMachineConfigPath
    if (Test-Path -LiteralPath $localPath) {
        try {
            $localRaw = Get-Content -LiteralPath $localPath -Raw -Encoding utf8
            $localConfig = $localRaw | ConvertFrom-Json -ErrorAction Stop
            $localRoot = [string]$localConfig.authority_root

            if (-not [string]::IsNullOrWhiteSpace($localRoot) -and (Test-Path -LiteralPath $localRoot)) {
                return $localRoot
            }
        } catch {
            # An invalid local override does not suppress portable fallbacks.
        }
    }

    $registryRoot = [string]$Config.authority_root
    if (-not [string]::IsNullOrWhiteSpace($registryRoot) -and (Test-Path -LiteralPath $registryRoot)) {
        return $registryRoot
    }

    $derivedRoot = Split-Path -Parent (Get-HubRoot)
    if (-not [string]::IsNullOrWhiteSpace($derivedRoot) -and (Test-Path -LiteralPath $derivedRoot)) {
        return $derivedRoot
    }

    throw "Unable to resolve a valid CodexHub authority root from local override, project registry, or the CodexHub parent folder."
}
function Read-Registry {
    $path = Get-RegistryPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Registry not found: $path"
    }

    $raw = Get-Content -LiteralPath $path -Raw -Encoding utf8
    $config = $raw | ConvertFrom-Json -ErrorAction Stop

    if ($null -eq $config.projects) {
        throw "Registry projects array is required."
    }
    $config.authority_root = Resolve-AuthorityRoot -Config $config

    return $config
}

function Get-ProjectPath {
    param(
        [string]$AuthorityRoot,
        [object]$Project
    )

    return Join-Path -Path $AuthorityRoot -ChildPath ([string]$Project.folder)
}

function Get-ProjectLabel {
    param([object]$Project)

    if (-not [string]::IsNullOrWhiteSpace([string]$Project.display_name)) {
        return [string]$Project.display_name
    }

    return [string]$Project.name
}

function Test-ProjectLocalAuthority {
    param(
        [object]$Project,
        [string]$ProjectPath,
        [string]$Mode = "LO"
    )

    $toolPath = Get-LocalAuthorityToolPath
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Local authority gate is missing: $toolPath"
    }

    . $toolPath
    $result = Test-LocalAuthority -ProjectRoot $ProjectPath -ExpectedRemote ([string]$Project.remote) -Mode $Mode
    Write-Host ("Local authority: {0}" -f $result.status) -ForegroundColor Cyan
    Write-Host $result.message -ForegroundColor DarkGray
    Write-Host ("Remote proof: {0}; temp repo: {1}; outside memory: {2}" -f $result.remote_proof.status, $result.temp_repo_status, $result.outside_memory_status) -ForegroundColor DarkGray

    if ($result.status -in @("LOCAL_AUTHORITY_OK", "LOCAL_AUTHORITY_DIRTY_RECORDED")) {
        return $true
    }

    Write-Host "Project launch stopped by local authority gate." -ForegroundColor Yellow
    return $false
}

function Get-CurrentTaskPreviewLines {
    param([string]$ProjectPath)

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        return @()
    }

    $taskPath = Join-Path -Path $ProjectPath -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $taskPath)) {
        return @()
    }

    try {
        $matches = Select-String -Path $taskPath -Pattern '^(Last resume:|Next exact step:)' -Encoding utf8
        return @($matches | ForEach-Object { $_.Line.Trim() })
    } catch {
        return @()
    }
}

function Get-LastProjectName {
    $path = Get-LastProjectPath
    if (-not (Test-Path -LiteralPath $path)) {
        return ""
    }

    return (Get-Content -LiteralPath $path -Raw -Encoding utf8).Trim()
}

function Set-LastProjectName {
    param([string]$Name)

    $path = Get-LastProjectPath
    $parent = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    Set-Content -LiteralPath $path -Value $Name -Encoding utf8
}

function Read-Selection {
    param([string]$Prompt)

    Write-Host -NoNewline ("{0}: " -f $Prompt)
    return [Console]::ReadLine()
}

function Invoke-LocalCheck {
    param(
        [string]$Label,
        [string[]]$Arguments
    )

    $hubRoot = Get-HubRoot
    Write-Host ""
    Write-Host ("Running: {0}" -f $Label) -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass @Arguments
    Write-Host ""
    [void](Read-Selection -Prompt "Press Enter to return to menu")
}

function Set-ProjectLaunchState {
    param(
        [string]$ProjectName,
        [string]$ProjectPath,
        [string]$Profile,
        [string]$ResumeCommand
    )

    $stateRoot = Get-StateRoot
    if (-not (Test-Path -LiteralPath $stateRoot)) {
        New-Item -ItemType Directory -Path $stateRoot | Out-Null
    }

    Set-Content -LiteralPath (Get-ProjectStatePath -ProjectName $ProjectName -Suffix "last_profile.txt") -Value $Profile -Encoding utf8
    Set-Content -LiteralPath (Get-ProjectStatePath -ProjectName $ProjectName -Suffix "last_project_root.txt") -Value $ProjectPath -Encoding utf8
    if (-not [string]::IsNullOrWhiteSpace($ResumeCommand)) {
        Set-Content -LiteralPath (Get-ProjectStatePath -ProjectName $ProjectName -Suffix "last_resume_command.txt") -Value $ResumeCommand -Encoding utf8
    }
}

function Get-GitValue {
    param(
        [string]$ProjectPath,
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath (Join-Path -Path $ProjectPath -ChildPath ".git"))) {
        return ""
    }

    try {
        $output = @(& git -C $ProjectPath @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) { return "" }
        return ($output -join "`n").Trim()
    } catch {
        return ""
    }
}

function Get-LastResumeCommand {
    param(
        [string]$ProjectName,
        [string]$ProjectPath
    )

    $statePath = Get-ProjectStatePath -ProjectName $ProjectName -Suffix "last_resume_command.txt"
    if (Test-Path -LiteralPath $statePath) {
        $value = (Get-Content -LiteralPath $statePath -Raw -Encoding utf8).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    $resumeState = Get-ResumeStatePath -ProjectName $ProjectName
    if (Test-Path -LiteralPath $resumeState) {
        try {
            $state = Get-Content -LiteralPath $resumeState -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $state.PSObject.Properties["resume_command"] -and -not [string]::IsNullOrWhiteSpace([string]$state.resume_command)) {
                return [string]$state.resume_command
            }
            if ($null -ne $state.PSObject.Properties["thread_id"] -and -not [string]::IsNullOrWhiteSpace([string]$state.thread_id)) {
                return "codex resume " + [string]$state.thread_id
            }
        } catch {
            return ""
        }
    }

    return ""
}

function Update-SessionContext {
    param(
        [object]$Config,
        [object]$Project,
        [string]$Profile
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    $contextRoot = Join-Path -Path $projectPath -ChildPath ".codexhub"
    if (-not (Test-Path -LiteralPath $contextRoot)) {
        New-Item -ItemType Directory -Path $contextRoot | Out-Null
    }

    $taskPath = Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
    $agentsPath = Join-Path -Path $projectPath -ChildPath "AGENTS.md"
    $commit = Get-GitValue -ProjectPath $projectPath -Arguments @("log", "-1", "--pretty=%h %s")
    $tag = Get-GitValue -ProjectPath $projectPath -Arguments @("describe", "--tags", "--abbrev=0")
    $resumeCommand = Get-LastResumeCommand -ProjectName ([string]$Project.name) -ProjectPath $projectPath

    $lines = @(
        "# CodexHub Session Context",
        "",
        "Context support only. The project CURRENT_TASK.md and AGENTS.md remain authoritative.",
        "",
        ("Project key: {0}" -f [string]$Project.name),
        ("Registered root: {0}" -f $projectPath),
        ("Authoritative CURRENT_TASK.md: {0}" -f $taskPath),
        ("Authoritative AGENTS.md: {0}" -f ($(if (Test-Path -LiteralPath $agentsPath) { $agentsPath } else { "not present" }))),
        ("Latest known commit/tag: {0}" -f ($(if ([string]::IsNullOrWhiteSpace($tag)) { $commit } else { "$commit / $tag" }))),
        "Last known runtime/version: refresh context for current release truth",
        ("Last resume command: {0}" -f ($(if ([string]::IsNullOrWhiteSpace($resumeCommand)) { "not recorded" } else { $resumeCommand }))),
        ("Selected launch profile: {0}" -f $Profile),
        "",
        "Do not update CodexHub CURRENT_TASK.md for project work. Read and write the project CURRENT_TASK.md and AGENTS.md in the registered root."
    )

    $contextPath = Join-Path -Path $contextRoot -ChildPath "SESSION_CONTEXT.md"
    Set-Content -LiteralPath $contextPath -Value $lines -Encoding utf8
    return $contextPath
}

function Start-CodexHandoff {
    param(
        [string]$ProjectPath,
        [string]$Profile = "default",
        [string]$ResumeCommand = ""
    )

    $literal = "'" + $ProjectPath.Replace("'", "''") + "'"
    $codexCommand = "codex"
    if (-not [string]::IsNullOrWhiteSpace($ResumeCommand)) {
        $codexCommand = $ResumeCommand
    }

    $pwsh = Get-Command pwsh -ErrorAction Stop
    Start-Process $pwsh.Source -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command",
        "Set-Location -LiteralPath $literal; Write-Host 'CodexHub profile: $Profile'; $codexCommand"
    ) | Out-Null
}

function Show-Header {
    param([object]$Config)

    $activeCount = @($Config.projects | Where-Object { [string]$_.status -eq "active" }).Count
    $placeholderCount = @($Config.projects | Where-Object { [string]$_.status -eq "placeholder" }).Count

    try {
        Clear-Host
    } catch {
        Write-Host ""
    }
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host "             CODEXHUB LITE" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host (" MODE: {0}" -f $OperationalMode.ToUpperInvariant()) -ForegroundColor Cyan
    Write-Host (" AUTH ROOT: {0}" -f [string]$Config.authority_root) -ForegroundColor Cyan
    Write-Host (" Active: {0}   Placeholder: {1}" -f $activeCount, $placeholderCount) -ForegroundColor Gray

    $last = Get-LastProjectName
    if (-not [string]::IsNullOrWhiteSpace($last)) {
        Write-Host (" Last: {0}" -f $last) -ForegroundColor DarkGray
    }

    Write-Host ""
}

function Show-Projects {
    param([object]$Config)

    Write-Host "Projects:" -ForegroundColor Cyan

    for ($i = 0; $i -lt $Config.projects.Count; $i++) {
        $project = $Config.projects[$i]
        $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $project
        $exists = Test-Path -LiteralPath $projectPath
        $label = Get-ProjectLabel -Project $project
        $status = [string]$project.status
        $remoteState = if ([string]::IsNullOrWhiteSpace([string]$project.remote)) { "remote unknown" } else { "remote set" }

        Write-Host ("{0,2}. {1}" -f ($i + 1), $label) -ForegroundColor White
        Write-Host ("    status: {0}; folder: {1}; exists: {2}; {3}" -f $status, [string]$project.folder, $exists, $remoteState) -ForegroundColor DarkGray
        Write-Host ("    path: {0}" -f $projectPath) -ForegroundColor DarkGray
        foreach ($line in (Get-CurrentTaskPreviewLines -ProjectPath $projectPath)) {
            Write-Host ("    {0}" -f $line) -ForegroundColor DarkCyan
        }
    }

    Write-Host ""
    Write-Host "Checks:" -ForegroundColor Cyan
    Write-Host " R. Resume state check" -ForegroundColor White
    Write-Host " A. Advanced checks" -ForegroundColor White
    Write-Host ""
    Write-Host "0. Exit" -ForegroundColor Cyan
    Write-Host ""
}

function Show-AdvancedChecks {
    Write-Host ""
    Write-Host "Advanced checks:" -ForegroundColor Cyan
    Write-Host " 1. Release truth LO" -ForegroundColor White
    Write-Host " 2. Release truth MED" -ForegroundColor White
    Write-Host " 3. Release truth HI" -ForegroundColor White
    Write-Host " 4. Drift audit" -ForegroundColor White
    Write-Host " 0. Back" -ForegroundColor Cyan
    Write-Host ""
}

function Open-AdvancedChecks {
    while ($true) {
        Show-AdvancedChecks
        $selection = Read-Selection -Prompt "Select advanced check"
        switch ($selection) {
            "0" { return }
            "1" { Invoke-LocalCheck -Label "Release truth check - LO" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "LO"); return }
            "2" { Invoke-LocalCheck -Label "Release truth check - MED" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "MED"); return }
            "3" { Invoke-LocalCheck -Label "Release truth check - HI" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "HI"); return }
            "4" { Invoke-LocalCheck -Label "Drift audit" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\drift-audit.ps1")); return }
            default {
                Write-Host "Invalid selection." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Open-Project {
    param(
        [object]$Config,
        [object]$Project
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    $hasRemote = -not [string]::IsNullOrWhiteSpace([string]$Project.remote)

    if (Test-Path -LiteralPath $projectPath) {
        if (-not (Test-ProjectLocalAuthority -Project $Project -ProjectPath $projectPath -Mode "LO")) {
            return $false
        }
        Set-LastProjectName -Name ([string]$Project.name)
        Write-Host ("Launching Codex in: {0}" -f $projectPath) -ForegroundColor Cyan
        Start-CodexHandoff -ProjectPath $projectPath
        return $true
    }

    Write-Host ""
    Write-Host ("Project folder missing: {0}" -f $projectPath) -ForegroundColor Yellow
    if ($hasRemote) {
        Write-Host ("Remote available for future restore: {0}" -f [string]$Project.remote) -ForegroundColor Yellow
        Write-Host "Clone is not performed in this CIS." -ForegroundColor Yellow
    } else {
        Write-Host "No remote is recorded for this project yet." -ForegroundColor Yellow
    }

    return $false
}

function Show-ProjectMenu {
    param(
        [object]$Config,
        [object]$Project
    )

    $label = Get-ProjectLabel -Project $Project
    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    Write-Host ""
    Write-Host $label -ForegroundColor Cyan
    Write-Host ("Registered root: {0}" -f $projectPath) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host " 1. Open Codex App / GUI in this project" -ForegroundColor White
    Write-Host " 2. Launch Codex CLI - default profile" -ForegroundColor White
    Write-Host " 3. Launch Codex CLI - 5.4 Low" -ForegroundColor White
    Write-Host " 4. Launch Codex CLI - 5.5 Low" -ForegroundColor White
    Write-Host " 5. Launch Codex CLI - 5.5 High" -ForegroundColor White
    Write-Host " 6. Resume last Codex session" -ForegroundColor White
    Write-Host " 7. Project state authority check" -ForegroundColor White
    Write-Host " 8. Refresh context / quick truth check" -ForegroundColor White
    Write-Host " 9. Advanced checks" -ForegroundColor White
    Write-Host " S. Save / Backup State" -ForegroundColor White
    Write-Host "    aliases: update files, backup state, save state, heartbeat, handoff" -ForegroundColor DarkGray
    Write-Host " R. Resume state check / recognize saved backup" -ForegroundColor White
    Write-Host " 0. Back" -ForegroundColor Cyan
    Write-Host ""
}

function Open-GuiContext {
    param(
        [object]$Config,
        [object]$Project
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ("Project folder missing: {0}" -f $projectPath) -ForegroundColor Yellow
        return
    }

    Set-LastProjectName -Name ([string]$Project.name)
    Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "Codex App / GUI" -ResumeCommand ""
    $contextPath = Update-SessionContext -Config $Config -Project $Project -Profile "Codex App / GUI"
    Write-Host ""
    Write-Host "Codex App / GUI context is ready." -ForegroundColor Cyan
    Write-Host ("Project root: {0}" -f $projectPath) -ForegroundColor White
    Write-Host ("Session context: {0}" -f $contextPath) -ForegroundColor White
    Write-Host "Open the GUI on the project root above. The GUI must read/write that project's CURRENT_TASK.md and AGENTS.md, not CodexHub CURRENT_TASK.md." -ForegroundColor Yellow
}

function Invoke-RefreshContext {
    param(
        [object]$Config,
        [object]$Project,
        [switch]$AuthorityOnly
    )

    $args = @(
        "-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\refresh-context.ps1"),
        "-ProjectName", ([string]$Project.name)
    )
    if ($AuthorityOnly) {
        $args += "-AuthorityOnly"
    }

    Invoke-LocalCheck -Label "Refresh context" -Arguments $args
}

function Invoke-ResumeStateCheck {
    param(
        [object]$Config,
        [object]$Project = $null
    )

    $arguments = @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\resume_state_check.ps1"))
    if ($null -ne $Project) {
        $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
        if (-not (Test-Path -LiteralPath (Join-Path -Path $projectPath -ChildPath ".git"))) {
            Write-Host ("Resume state check unavailable; selected project is not a git repository: {0}" -f $projectPath) -ForegroundColor Yellow
            return
        }
        $arguments += @("-ProjectPath", $projectPath)
        Write-Host ("Resume state target: {0} ({1})" -f [string]$Project.name, $projectPath) -ForegroundColor DarkCyan
    }

    Invoke-LocalCheck -Label "Resume state check" -Arguments $arguments
}

function Invoke-StateBackup {
    param(
        [object]$Config,
        [object]$Project,
        [string]$OperatorNote = "",
        [switch]$NoteSupplied
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    $taskPath = Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ("Project folder missing: {0}" -f $projectPath) -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath $taskPath)) {
        Write-Host ("CURRENT_TASK.md is missing: {0}" -f $taskPath) -ForegroundColor Yellow
        Write-Host "State backup stopped; creation requires explicit operator approval." -ForegroundColor Yellow
        return
    }

    $note = $OperatorNote
    if (-not $NoteSupplied) {
        $note = Read-Selection -Prompt "Optional operator note (blank for placeholder)"
    }
    $args = @(
        "-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\project-status.ps1"),
        "-ProjectPath", $projectPath,
        "-ProjectName", ([string]$Project.name),
        "-SaveStateBackup",
        "-OperatorNote", $note
    )

    Invoke-LocalCheck -Label "Save / Backup State" -Arguments $args
}

function Open-ProjectMenu {
    param(
        [object]$Config,
        [object]$Project
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    if (-not (Test-Path -LiteralPath $projectPath)) {
        [void](Open-Project -Config $Config -Project $Project)
        return
    }

    if (-not (Test-ProjectLocalAuthority -Project $Project -ProjectPath $projectPath -Mode "LO")) {
        [void](Read-Selection -Prompt "Press Enter to return to menu")
        return
    }

    while ($true) {
        Show-ProjectMenu -Config $Config -Project $Project
        $selection = (Read-Selection -Prompt "Select project action").Trim()
        if ($selection -match '^(?i)(update files|backup state|save state|heartbeat|handoff)\s+["''](.+)["'']$') {
            Invoke-StateBackup -Config $Config -Project $Project -OperatorNote $Matches[2] -NoteSupplied
            continue
        }
        switch ($selection.ToLowerInvariant()) {
            "0" { return }
            "1" {
                Open-GuiContext -Config $Config -Project $Project
                [void](Read-Selection -Prompt "Press Enter to return to menu")
            }
            "2" {
                Set-LastProjectName -Name ([string]$Project.name)
                Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "default" -ResumeCommand ""
                [void](Update-SessionContext -Config $Config -Project $Project -Profile "default")
                Start-CodexHandoff -ProjectPath $projectPath -Profile "default"
                return
            }
            "3" {
                Set-LastProjectName -Name ([string]$Project.name)
                Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "5.4 Low" -ResumeCommand ""
                [void](Update-SessionContext -Config $Config -Project $Project -Profile "5.4 Low")
                Start-CodexHandoff -ProjectPath $projectPath -Profile "5.4 Low"
                return
            }
            "4" {
                Set-LastProjectName -Name ([string]$Project.name)
                Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "5.5 Low" -ResumeCommand ""
                [void](Update-SessionContext -Config $Config -Project $Project -Profile "5.5 Low")
                Start-CodexHandoff -ProjectPath $projectPath -Profile "5.5 Low"
                return
            }
            "5" {
                Set-LastProjectName -Name ([string]$Project.name)
                Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "5.5 High" -ResumeCommand ""
                [void](Update-SessionContext -Config $Config -Project $Project -Profile "5.5 High")
                Start-CodexHandoff -ProjectPath $projectPath -Profile "5.5 High"
                return
            }
            "6" {
                $resumeCommand = Get-LastResumeCommand -ProjectName ([string]$Project.name) -ProjectPath $projectPath
                if ([string]::IsNullOrWhiteSpace($resumeCommand)) {
                    Write-Host "No resume command is recorded for this project." -ForegroundColor Yellow
                    [void](Read-Selection -Prompt "Press Enter to return to menu")
                    continue
                }
                Set-LastProjectName -Name ([string]$Project.name)
                Set-ProjectLaunchState -ProjectName ([string]$Project.name) -ProjectPath $projectPath -Profile "resume" -ResumeCommand $resumeCommand
                [void](Update-SessionContext -Config $Config -Project $Project -Profile "resume")
                Start-CodexHandoff -ProjectPath $projectPath -Profile "resume" -ResumeCommand $resumeCommand
                return
            }
            "7" { Invoke-RefreshContext -Config $Config -Project $Project -AuthorityOnly }
            "8" { Invoke-RefreshContext -Config $Config -Project $Project }
            "9" { Open-AdvancedChecks }
            "s" { Invoke-StateBackup -Config $Config -Project $Project }
            "r" { Invoke-ResumeStateCheck -Config $Config -Project $Project }
            "update files" { Invoke-StateBackup -Config $Config -Project $Project }
            "backup state" { Invoke-StateBackup -Config $Config -Project $Project }
            "save state" { Invoke-StateBackup -Config $Config -Project $Project }
            "heartbeat" { Invoke-StateBackup -Config $Config -Project $Project }
            "handoff" { Invoke-StateBackup -Config $Config -Project $Project }
            default {
                Write-Host "Invalid selection." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-SelfTest {
    $errors = New-Object System.Collections.Generic.List[string]

    try {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path (Get-HubRoot) -ChildPath "RUN.ps1"), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            foreach ($item in $parseErrors) {
                $errors.Add($item.Message) | Out-Null
            }
        }
    } catch {
        $errors.Add($_.Exception.Message) | Out-Null
    }

    try {
        $config = Read-Registry
        if (-not (Test-Path -LiteralPath ([string]$config.authority_root))) {
            $errors.Add(("authority_root missing: {0}" -f [string]$config.authority_root)) | Out-Null
        }

        $json = Get-Content -LiteralPath (Get-RegistryPath) -Raw -Encoding utf8
        if ($json -match '[Cc]:\\' -or $json -match '[Dd]:\\') {
            $errors.Add("registry contains C: or D: path references") | Out-Null
        }

        foreach ($project in $config.projects) {
            foreach ($field in @("name", "display_name", "folder", "remote", "status")) {
                if ($null -eq $project.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$project.$field) -and $field -ne "remote") {
                    $errors.Add(("project missing required field: {0}" -f $field)) | Out-Null
                }
            }
        }
    } catch {
        $errors.Add($_.Exception.Message) | Out-Null
    }

    if ($errors.Count -gt 0) {
        Write-Host "SELFTEST FAIL" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host (" - {0}" -f $err) -ForegroundColor Yellow
        }
        exit 1
    }

    Write-Host "SELFTEST PASS" -ForegroundColor Green
    exit 0
}

if ($SelfTest) {
    Invoke-SelfTest
}

$config = Read-Registry

while ($true) {
    Show-Header -Config $config
    Show-Projects -Config $config

    $selection = Read-Selection -Prompt "Select project #"
    if ([string]::IsNullOrWhiteSpace($selection)) {
        continue
    }

    if ($selection -eq "0") {
        return
    }

    switch ($selection.ToUpperInvariant()) {
        "R" {
            Invoke-ResumeStateCheck -Config $config
            continue
        }
        "A" {
            Open-AdvancedChecks
            continue
        }
    }

    if ($selection -notmatch '^\d+$') {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue
    }

    $index = [int]$selection - 1
    if ($index -lt 0 -or $index -ge $config.projects.Count) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue
    }

    Open-ProjectMenu -Config $config -Project $config.projects[$index]
}

