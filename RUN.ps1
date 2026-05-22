param(
    [ValidateSet("LIGHT", "FULL_AUDIT")]
    [string]$OperationalMode = "LIGHT",
    [switch]$SelfTest
)

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

function Read-Registry {
    $path = Get-RegistryPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Registry not found: $path"
    }

    $raw = Get-Content -LiteralPath $path -Raw -Encoding utf8
    $config = $raw | ConvertFrom-Json -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace([string]$config.authority_root)) {
        throw "Registry authority_root is required."
    }

    if ($null -eq $config.projects) {
        throw "Registry projects array is required."
    }

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

function Start-CodexHandoff {
    param([string]$ProjectPath)

    $literal = "'" + $ProjectPath.Replace("'", "''") + "'"
    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command",
        "Set-Location -LiteralPath $literal; codex"
    ) | Out-Null
}

function Show-Header {
    param([object]$Config)

    $activeCount = @($Config.projects | Where-Object { [string]$_.status -eq "active" }).Count
    $placeholderCount = @($Config.projects | Where-Object { [string]$_.status -eq "placeholder" }).Count

    Clear-Host
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

    Write-Host "Checks:" -ForegroundColor Cyan
    Write-Host " R. Resume state check" -ForegroundColor White
    Write-Host " L. Release truth check - LO" -ForegroundColor White
    Write-Host " M. Release truth check - MED" -ForegroundColor White
    Write-Host " H. Release truth check - HI" -ForegroundColor White
    Write-Host ""
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
    Write-Host "0. Exit" -ForegroundColor Cyan
    Write-Host ""
}

function Open-Project {
    param(
        [object]$Config,
        [object]$Project
    )

    $projectPath = Get-ProjectPath -AuthorityRoot ([string]$Config.authority_root) -Project $Project
    $hasRemote = -not [string]::IsNullOrWhiteSpace([string]$Project.remote)

    if (Test-Path -LiteralPath $projectPath) {
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
        if ([string]$config.authority_root -ne "E:\Gdrive\01_SANJAY\Codex_Sync") {
            $errors.Add("authority_root mismatch") | Out-Null
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
            Invoke-LocalCheck -Label "Resume state check" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\resume_state_check.ps1"))
            continue
        }
        "L" {
            Invoke-LocalCheck -Label "Release truth check - LO" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "LO")
            continue
        }
        "M" {
            Invoke-LocalCheck -Label "Release truth check - MED" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "MED")
            continue
        }
        "H" {
            Invoke-LocalCheck -Label "Release truth check - HI" -Arguments @("-File", (Join-Path -Path (Get-HubRoot) -ChildPath "tools\release_truth_check.ps1"), "-Mode", "HI")
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

    if (Open-Project -Config $config -Project $config.projects[$index]) {
        return
    }

    [void](Read-Selection -Prompt "Press Enter to return to menu")
}

