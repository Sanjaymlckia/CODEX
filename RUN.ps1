$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Root {
    if ($PSCommandPath) {
        return Split-Path -Path $PSCommandPath -Parent
    }

    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    return (Get-Location).Path
}

function Get-RegPath { Join-Path -Path (Get-Root) -ChildPath "projects\projects.json" }
function Get-StateRoot { Join-Path -Path (Get-Root) -ChildPath "state" }
function Get-LastPath { Join-Path -Path (Get-StateRoot) -ChildPath "last_project.txt" }
function Get-PromptsRoot { Join-Path -Path (Get-Root) -ChildPath "prompts" }
function Get-CommandLibraryPath { Join-Path -Path (Get-Root) -ChildPath "COMMAND_LIBRARY.md" }

function Get-PromptPath {
    param([string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return ""
    }

    return Join-Path -Path (Get-PromptsRoot) -ChildPath "$ProjectName.txt"
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -LiteralPath $parent -Force | Out-Null
    }
}

function Resolve-Status {
    param([object]$Project)

    $status = if ($null -ne $Project.PSObject.Properties["status"]) { [string]$Project.status } else { "" }
    if ([string]::IsNullOrWhiteSpace($status)) {
        return "active"
    }

    return $status.Trim().ToLowerInvariant()
}

function ConvertTo-ProjectRecord {
    param([object]$Project)

    if ($null -eq $Project) { return $null }

    [pscustomobject]@{
        name            = if ($null -ne $Project.PSObject.Properties["name"]) { [string]$Project.name } else { "" }
        display_name    = if ($null -ne $Project.PSObject.Properties["display_name"]) { [string]$Project.display_name } else { "" }
        status          = Resolve-Status $Project
        path            = if ($null -ne $Project.PSObject.Properties["path"]) { [string]$Project.path } else { "" }
        type            = if ($null -ne $Project.PSObject.Properties["type"]) { [string]$Project.type } else { "" }
        startup_context = if ($null -ne $Project.PSObject.Properties["startup_context"]) { [string]$Project.startup_context } else { "" }
        notes           = if ($null -ne $Project.PSObject.Properties["notes"]) { [string]$Project.notes } else { "" }
    }
}

function Load-Reg {
    $regPath = Get-RegPath
    if (-not (Test-Path -LiteralPath $regPath)) {
        throw "Project registry not found: $regPath"
    }

    $raw = Get-Content -LiteralPath $regPath -Raw -Encoding utf8
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    return @($parsed | ForEach-Object { ConvertTo-ProjectRecord $_ } | Where-Object { $null -ne $_ })
}

function Get-ProjectsByStatus {
    param(
        [object[]]$Projects,
        [string[]]$Status
    )

    $wanted = @($Status | ForEach-Object { $_.ToLowerInvariant() })
    return @($Projects | Where-Object { $wanted -contains (Resolve-Status $_) })
}

function Get-Label {
    param([object]$Project)

    if ($null -ne $Project -and -not [string]::IsNullOrWhiteSpace($Project.display_name)) {
        return $Project.display_name
    }

    return $Project.name
}

function Get-LastProjectName {
    $lastPath = Get-LastPath
    if (Test-Path -LiteralPath $lastPath) {
        return (Get-Content -LiteralPath $lastPath -Raw -Encoding utf8).Trim()
    }

    return ""
}

function Set-LastProjectName {
    param([string]$Name)

    $lastPath = Get-LastPath
    Ensure-ParentDirectory -Path $lastPath
    Set-Content -LiteralPath $lastPath -Value $Name -Encoding utf8
}

function Find-ProjectIndexByName {
    param(
        [object[]]$Projects,
        [string]$Name
    )

    for ($i = 0; $i -lt $Projects.Count; $i++) {
        if ([string]::Equals([string]$Projects[$i].name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $i
        }
    }

    return -1
}

function ConvertTo-SingleQuotedPowerShellLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function Show-Header {
    $reg = @(Load-Reg)
    $active = @(Get-ProjectsByStatus -Projects $reg -Status @("active")).Count
    $deprecated = @(Get-ProjectsByStatus -Projects $reg -Status @("deprecated")).Count
    $archived = @(Get-ProjectsByStatus -Projects $reg -Status @("archived")).Count
    $last = Get-LastProjectName

    Clear-Host
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "        CODEX HUB LAUNCHER       " -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "Active: $active   Deprecated: $deprecated   Archived: $archived"
    if ($last) {
        Write-Host "Last: $last"
    }
    Write-Host ""
}

function Open-Proj {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = $Project.path.Trim()
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ""
        Write-Host "Missing path: $projectPath" -ForegroundColor Yellow
        return
    }

    Set-LastProjectName -Name $Project.name

    $projectNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.name
    $displayNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value (Get-Label -Project $Project)
    $projectPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $projectPath
    $contextLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.startup_context
    $promptPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value (Get-PromptPath -ProjectName $Project.name)

    $bootstrap = @"
`$projectName = $projectNameLiteral
`$displayName = $displayNameLiteral
`$projectPath = $projectPathLiteral
`$startupContext = $contextLiteral
`$promptPath = $promptPathLiteral
`$currentTaskPath = Join-Path -Path `$projectPath -ChildPath 'CURRENT_TASK.md'

Set-Location -LiteralPath `$projectPath

Write-Host '=================================' -ForegroundColor Cyan
Write-Host " `$displayName" -ForegroundColor Cyan
Write-Host '=================================' -ForegroundColor Cyan
Write-Host "Path: `$projectPath"
Write-Host "Context: `$startupContext"
Write-Host ''

if (Test-Path -LiteralPath `$currentTaskPath) {
    Write-Host 'CURRENT_TASK.md' -ForegroundColor Magenta
    Write-Host '---------------' -ForegroundColor Magenta
    Get-Content -LiteralPath `$currentTaskPath -Encoding utf8
    Write-Host ''
}

if (Test-Path -LiteralPath '.\.git') {
    Write-Host 'git status -sb' -ForegroundColor Magenta
    Write-Host '--------------' -ForegroundColor Magenta
    git status -sb
    Write-Host ''
}

if (Get-Command codex -ErrorAction SilentlyContinue) {
    if (Test-Path -LiteralPath `$promptPath) {
        `$initialPrompt = Get-Content -LiteralPath `$promptPath -Raw -Encoding utf8
        if (-not [string]::IsNullOrWhiteSpace(`$initialPrompt)) {
            & codex `$initialPrompt
        } else {
            & codex
        }
    } else {
        & codex
    }
} else {
    Write-Host 'codex CLI not found in PATH. Shell opened at project root.' -ForegroundColor Yellow
}
"@

    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", $bootstrap
    ) | Out-Null
}

function Resume-Last {
    $name = Get-LastProjectName
    if (-not $name) {
        Write-Host "No last project." -ForegroundColor Yellow
        return
    }

    $reg = @(Load-Reg)
    $index = Find-ProjectIndexByName -Projects $reg -Name $name
    if ($index -lt 0) {
        Write-Host "Last project not found in registry." -ForegroundColor Yellow
        return
    }

    Open-Proj -Project $reg[$index]
}

while ($true) {
    Show-Header
    $activeProjects = @(Get-ProjectsByStatus -Projects (Load-Reg) -Status @("active"))

    for ($i = 0; $i -lt $activeProjects.Count; $i++) {
        $project = $activeProjects[$i]
        $menuNumber = $i + 1
        Write-Host "$menuNumber. $(Get-Label -Project $project)"
        Write-Host "   $($project.path)"
    }

    Write-Host ""
    Write-Host "R. Resume last"
    Write-Host "C. Open command library"
    Write-Host "H. Open CODEX root"
    Write-Host "0. Exit"
    Write-Host ""

    $rawSelection = Read-Host "Select an option"
    if ($null -eq $rawSelection) {
        break
    }

    $selection = $rawSelection.Trim()
    if ([string]::IsNullOrWhiteSpace($selection)) {
        continue
    }

    switch -Regex ($selection) {
        '^0$' { break }
        '^[Rr]$' {
            Resume-Last
            continue
        }
        '^[Cc]$' {
            $path = Get-CommandLibraryPath
            if (Test-Path -LiteralPath $path) {
                Start-Process powershell.exe -ArgumentList @(
                    "-NoExit",
                    "-ExecutionPolicy", "Bypass",
                    "-Command", "Get-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral -Value $path)"
                ) | Out-Null
            }
            continue
        }
        '^[Hh]$' {
            Open-Proj -Project ([pscustomobject]@{
                name = "CODEX_ROOT"
                display_name = "CODEX Root"
                path = Get-Root
                startup_context = "CODEX hub root. Review launcher, registry, prompts, and documentation before making hub-level changes."
            })
            continue
        }
        '^\d+$' {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $activeProjects.Count) {
                Open-Proj -Project $activeProjects[$index]
            } else {
                Write-Host ""
                Write-Host "Invalid selection." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
            continue
        }
        default {
            Write-Host ""
            Write-Host "Invalid selection." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}
