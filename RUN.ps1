function Get-Root {
    if (Get-Variable -Name CodexRoot -Scope Script -ErrorAction SilentlyContinue) {
        return $script:CodexRoot
    }

    if ($PSCommandPath) {
        $script:CodexRoot = Split-Path -Path $PSCommandPath -Parent
    } elseif ($PSScriptRoot) {
        $script:CodexRoot = $PSScriptRoot
    } else {
        $script:CodexRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    }

    return $script:CodexRoot
}

function Get-RegPath { Join-Path -Path (Get-Root) -ChildPath "projects\projects.json" }
function Get-StateRoot { Join-Path -Path (Get-Root) -ChildPath "state" }
function Get-LastPath { Join-Path -Path (Get-Root) -ChildPath "state\last_project.txt" }
function Get-CtxPath { Join-Path -Path (Get-Root) -ChildPath "CURRENT_CONTEXT.txt" }
function Get-CommandLibraryPath { Join-Path -Path (Get-Root) -ChildPath "COMMAND_LIBRARY.md" }
function Get-PromptsRoot { Join-Path -Path (Get-Root) -ChildPath "prompts" }
function Get-PromptPath {
    param([string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return ""
    }

    return Join-Path -Path (Get-PromptsRoot) -ChildPath "$ProjectName.txt"
}
function Get-ProjectSnapshotPath {
    param([string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return ""
    }

    $safeName = ($ProjectName -replace '[^A-Za-z0-9._-]', '_')
    return Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_snapshot.json" -f $safeName)
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:RegistryStorageShape = "array"

function Ensure-ParentDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and !(Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -LiteralPath $parent -Force | Out-Null
    }
}

function Resolve-Status {
    param([object]$Project)

    $status = ""
    if ($null -ne $Project.PSObject.Properties["status"]) {
        $status = [string]$Project.status
    }

    if ([string]::IsNullOrWhiteSpace($status)) {
        return "active"
    }

    switch ($status.Trim().ToLowerInvariant()) {
        "active" { "active" }
        "deprecated" { "deprecated" }
        "archived" { "archived" }
        default { $status.Trim().ToLowerInvariant() }
    }
}

function ConvertTo-ProjectRecord {
    param([object]$Project)

    if ($null -eq $Project) { return $null }

    [pscustomobject]@{
        name            = if ($null -ne $Project.PSObject.Properties["name"]) { [string]$Project.name } else { "" }
        status          = Resolve-Status $Project
        path            = if ($null -ne $Project.PSObject.Properties["path"]) { [string]$Project.path } else { "" }
        type            = if ($null -ne $Project.PSObject.Properties["type"]) { [string]$Project.type } else { "" }
        startup_context = if ($null -ne $Project.PSObject.Properties["startup_context"]) { [string]$Project.startup_context } else { "" }
        notes           = if ($null -ne $Project.PSObject.Properties["notes"]) { [string]$Project.notes } else { "" }
    }
}

function Normalize-ProjectList {
    param([object]$InputObject)

    if ($null -eq $InputObject) {
        return @()
    }

    if (($InputObject -is [System.Array] -or $InputObject -is [System.Collections.IList]) -and !($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { ConvertTo-ProjectRecord $_ } | Where-Object { $null -ne $_ })
    }

    return @(ConvertTo-ProjectRecord $InputObject | Where-Object { $null -ne $_ })
}

function Get-RegistryProjectItems {
    param([object]$ParsedRegistry)

    if ($null -eq $ParsedRegistry) {
        return @()
    }

    if (($ParsedRegistry -is [System.Array] -or $ParsedRegistry -is [System.Collections.IList]) -and !($ParsedRegistry -is [string])) {
        return @($ParsedRegistry)
    }

    if ($null -ne $ParsedRegistry.PSObject.Properties["projects"]) {
        return @(Normalize-ProjectList $ParsedRegistry.projects)
    }

    if ($null -ne $ParsedRegistry.PSObject.Properties["name"] -or $null -ne $ParsedRegistry.PSObject.Properties["path"]) {
        return @(Normalize-ProjectList $ParsedRegistry)
    }

    throw "Registry JSON must be a project array, a single project object, or an object containing a 'projects' array."
}

function Get-RegistryShape {
    param([object]$ParsedRegistry)

    if ($null -eq $ParsedRegistry) {
        return "array"
    }

    if (($ParsedRegistry -is [System.Array] -or $ParsedRegistry -is [System.Collections.IList]) -and !($ParsedRegistry -is [string])) {
        return "array"
    }

    if ($null -ne $ParsedRegistry.PSObject.Properties["projects"]) {
        return "wrapped"
    }

    if ($null -ne $ParsedRegistry.PSObject.Properties["name"] -or $null -ne $ParsedRegistry.PSObject.Properties["path"]) {
        return "single"
    }

    return "array"
}

function Load-Reg {
    $regPath = Get-RegPath
    if (!(Test-Path -LiteralPath $regPath)) {
        $script:RegistryStorageShape = "array"
        return @()
    }

    $raw = Get-Content -LiteralPath $regPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $script:RegistryStorageShape = "array"
        return @()
    }

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid registry JSON at '$regPath'. $($_.Exception.Message)"
    }

    $script:RegistryStorageShape = Get-RegistryShape -ParsedRegistry $parsed
    return @(Get-RegistryProjectItems -ParsedRegistry $parsed | ForEach-Object { ConvertTo-ProjectRecord $_ } | Where-Object { $null -ne $_ })
}

function Save-Reg {
    param([object[]]$Data)

    $regPath = Get-RegPath
    Ensure-ParentDirectory -Path $regPath

    $items = @($Data | ForEach-Object { ConvertTo-ProjectRecord $_ } | Where-Object { $null -ne $_ })
    $shape = $script:RegistryStorageShape
    if ([string]::IsNullOrWhiteSpace($shape)) {
        $shape = "array"
    }

    switch ($shape) {
        "wrapped" {
            $payload = [pscustomobject]@{
                projects = $items
            }
        }
        "single" {
            if ($items.Count -eq 1) {
                $payload = $items[0]
            } else {
                $payload = $items
                $script:RegistryStorageShape = "array"
            }
        }
        default {
            $payload = $items
        }
    }

    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $regPath -Encoding utf8
}

function Pause-Return {
    Write-Host ""
    pause | Out-Null
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

function Set-CurrentContext {
    param([string]$Context)

    $ctxPath = Get-CtxPath
    Ensure-ParentDirectory -Path $ctxPath
    Set-Content -LiteralPath $ctxPath -Value $Context -Encoding utf8
}

function Get-ProjectsByStatus {
    param(
        [object[]]$Projects,
        [string[]]$Status
    )

    $wanted = @($Status | ForEach-Object { $_.ToLowerInvariant() })
    return @($Projects | Where-Object { $wanted -contains (Resolve-Status $_) })
}

function Show-Header {
    $reg = @(Load-Reg)
    $active = @(Get-ProjectsByStatus -Projects $reg -Status @("active")).Count
    $deprecated = @(Get-ProjectsByStatus -Projects $reg -Status @("deprecated")).Count
    $archived = @(Get-ProjectsByStatus -Projects $reg -Status @("archived")).Count
    $last = Get-LastProjectName

    Clear-Host
    Write-Host "=== CODEX CONTROL V3 ===" -ForegroundColor Cyan
    Write-Host "Active: $active   Deprecated: $deprecated   Archived: $archived"
    if ($last) { Write-Host "Last: $last" }
    Write-Host ""
}

function Pick {
    param(
        [object[]]$List,
        [string]$Title
    )

    $arr = @($List | Where-Object { $null -ne $_ })
    if ($arr.Count -eq 0) {
        Write-Host "None"
        return $null
    }

    Write-Host $Title
    Write-Host ""

    for ($i = 0; $i -lt $arr.Count; $i++) {
        $project = $arr[$i]
        Write-Host "$($i + 1). $($project.name) [$($project.status)]"
        Write-Host "   Path: $($project.path)"
    }

    Write-Host ""
    $n = Read-Host "Select #"
    if ($n -match '^\d+$') {
        $idx = [int]$n - 1
        if ($idx -ge 0 -and $idx -lt $arr.Count) {
            return $arr[$idx]
        }
    }

    Write-Host "Invalid selection"
    return $null
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

function Get-FullPathOrOriginal {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        $trimmedPath = $Path.Trim()
        if (Test-Path -LiteralPath $trimmedPath) {
            return (Resolve-Path -LiteralPath $trimmedPath).ProviderPath
        }
    } catch {
    }

    return $Path.Trim()
}

function ConvertTo-SingleQuotedPowerShellLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function New-DirectoryIfMissing {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -LiteralPath $Path -Force | Out-Null
    }
}

function Open-Proj {
    param([object]$Project)

    if ($null -eq $Project) { return }

    Set-LastProjectName -Name $Project.name
    Set-CurrentContext -Context $Project.startup_context

    $projectPath = Get-FullPathOrOriginal -Path $Project.path
    if (Test-Path -LiteralPath $projectPath) {
        $promptPath = Get-PromptPath -ProjectName $Project.name
        $snapshotPath = Get-ProjectSnapshotPath -ProjectName $Project.name
        $projectNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.name
        $projectPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $projectPath
        $startupContextLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.startup_context
        $promptPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $promptPath
        $snapshotPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $snapshotPath

        $launchCommand = @"
`$projectName = $projectNameLiteral
`$projectPath = $projectPathLiteral
`$startupContext = $startupContextLiteral
`$promptPath = $promptPathLiteral
`$snapshotPath = $snapshotPathLiteral
`$currentTaskPath = Join-Path -Path `$projectPath -ChildPath 'CURRENT_TASK.md'
`$agentsPath = Join-Path -Path `$projectPath -ChildPath 'AGENTS.md'

Set-Location -LiteralPath `$projectPath

Write-Host ''
Write-Host "Project: `$projectName" -ForegroundColor Cyan
Write-Host "Path: `$projectPath" -ForegroundColor Cyan
Write-Host "Startup Context: `$startupContext" -ForegroundColor Green

if (Test-Path -LiteralPath `$snapshotPath) {
    try {
        `$previousSnapshot = Get-Content -LiteralPath `$snapshotPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        Write-Host "Previous Snapshot: `$(`$previousSnapshot.timestamp)" -ForegroundColor DarkGray
        if (`$previousSnapshot.last_modified_file) {
            Write-Host "Previous Last-Modified Hint: `$(`$previousSnapshot.last_modified_file)" -ForegroundColor DarkGray
        }
        if (`$previousSnapshot.current_task_path) {
            Write-Host "Previous Task File: `$(`$previousSnapshot.current_task_path)" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "Previous snapshot unreadable: `$snapshotPath" -ForegroundColor Yellow
    }
}

if (Test-Path -LiteralPath `$agentsPath) {
    Write-Host "AGENTS.md: `$agentsPath" -ForegroundColor DarkGray
}

if (Test-Path -LiteralPath `$promptPath) {
    Write-Host "Prompt File: `$promptPath" -ForegroundColor DarkGray
    `$initialPrompt = Get-Content -LiteralPath `$promptPath -Raw -Encoding utf8
} else {
    `$initialPrompt = ''
}

`$recentFile = Get-ChildItem -LiteralPath `$projectPath -File -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { `$_.FullName -notmatch '\\\\.git(\\\\|$)' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (`$recentFile) {
    Write-Host "Last-Modified File Hint: `$(`$recentFile.FullName)" -ForegroundColor Yellow
    Write-Host "Last-Modified Time: `$(`$recentFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
}

if (Test-Path -LiteralPath `$currentTaskPath) {
    Write-Host ''
    Write-Host "CURRENT_TASK.md" -ForegroundColor Magenta
    Write-Host "---------------" -ForegroundColor Magenta
    Get-Content -LiteralPath `$currentTaskPath -Encoding utf8
} else {
    Write-Host "CURRENT_TASK.md: not found" -ForegroundColor DarkGray
}

if (`$projectName -eq 'FODE_RUNTIME') {
    Write-Host ''
    Write-Host "git status -sb" -ForegroundColor Magenta
    Write-Host "--------------" -ForegroundColor Magenta
    & git -C `$projectPath status -sb
}

`$snapshotDirectory = Split-Path -Path `$snapshotPath -Parent
if (`$snapshotDirectory -and !(Test-Path -LiteralPath `$snapshotDirectory)) {
    New-Item -ItemType Directory -LiteralPath `$snapshotDirectory -Force | Out-Null
}

`$snapshotData = [pscustomobject]@{
    timestamp          = (Get-Date).ToString('s')
    project_name       = `$projectName
    project_path       = `$projectPath
    startup_context    = `$startupContext
    prompt_path        = if (Test-Path -LiteralPath `$promptPath) { `$promptPath } else { '' }
    agents_path        = if (Test-Path -LiteralPath `$agentsPath) { `$agentsPath } else { '' }
    current_task_path  = if (Test-Path -LiteralPath `$currentTaskPath) { `$currentTaskPath } else { '' }
    last_modified_file = if (`$recentFile) { `$recentFile.FullName } else { '' }
    last_modified_time = if (`$recentFile) { `$recentFile.LastWriteTime.ToString('s') } else { '' }
    resume_hint        = 'Use codex resume --last from this workspace to continue the most recent interactive session when appropriate.'
}

`$snapshotData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath `$snapshotPath -Encoding utf8

Write-Host ''

if ([string]::IsNullOrWhiteSpace(`$initialPrompt)) {
    & codex
} else {
    & codex `$initialPrompt
}
"@

        Start-Process -FilePath "powershell.exe" -WorkingDirectory $projectPath -ArgumentList @(
            "-NoExit",
            "-Command",
            $launchCommand
        ) | Out-Null
    } else {
        Write-Host "Path missing: $projectPath" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Context:" -ForegroundColor Green
    Write-Host $Project.startup_context
}

function Resume-Last {
    $name = Get-LastProjectName
    if (!$name) {
        Write-Host "No last project"
        return
    }

    $reg = @(Load-Reg)
    $index = Find-ProjectIndexByName -Projects $reg -Name $name
    if ($index -lt 0) {
        Write-Host "Last project not found in registry"
        return
    }

    Open-Proj -Project $reg[$index]
}

function Add-Proj {
    $name = (Read-Host "Name").Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    $path = (Read-Host "Path").Trim()
    $type = Read-Host "Type"
    $ctx = Read-Host "Startup context"
    $notes = Read-Host "Notes"

    $reg = @(Load-Reg)
    if ((Find-ProjectIndexByName -Projects $reg -Name $name) -ge 0) {
        Write-Host "Project name already exists"
        return
    }

    $reg += [pscustomobject]@{
        name            = $name
        status          = "active"
        path            = $path
        type            = $type
        startup_context = $ctx
        notes           = $notes
    }

    Save-Reg -Data $reg
    Write-Host "Added: $name"
}

function Set-Status {
    param([string]$To)

    $reg = @(Load-Reg)
    $p = Pick -List $reg -Title "Select project"
    if ($null -eq $p) { return }

    $index = Find-ProjectIndexByName -Projects $reg -Name $p.name
    if ($index -lt 0) {
        Write-Host "Project not found"
        return
    }

    $reg[$index].status = $To
    Save-Reg -Data $reg
    Write-Host "Updated: $($reg[$index].name) -> $To"
}

function Reactivate-Proj {
    $reg = @(Load-Reg)
    $inactive = @(Get-ProjectsByStatus -Projects $reg -Status @("deprecated", "archived"))
    $p = Pick -List $inactive -Title "Select deprecated/archived project"
    if ($null -eq $p) { return }

    $index = Find-ProjectIndexByName -Projects $reg -Name $p.name
    if ($index -lt 0) {
        Write-Host "Project not found"
        return
    }

    $reg[$index].status = "active"
    Save-Reg -Data $reg
    Write-Host "Reactivated: $($reg[$index].name)"
}

function Update-Path {
    $reg = @(Load-Reg)
    $p = Pick -List $reg -Title "Select project"
    if ($null -eq $p) { return }

    $index = Find-ProjectIndexByName -Projects $reg -Name $p.name
    if ($index -lt 0) {
        Write-Host "Project not found"
        return
    }

    $newPath = Read-Host "New path"
    if ([string]::IsNullOrWhiteSpace($newPath)) { return }

    $reg[$index].path = Get-FullPathOrOriginal -Path $newPath
    Save-Reg -Data $reg
    Write-Host "Path updated: $($reg[$index].path)"
}

function Show-Project-Details {
    $reg = @(Load-Reg)
    $p = Pick -List $reg -Title "Select project"
    if ($null -eq $p) { return }

    Write-Host ""
    Write-Host "Name:    $($p.name)"
    Write-Host "Status:  $($p.status)"
    Write-Host "Type:    $($p.type)"
    Write-Host "Path:    $($p.path)"
    Write-Host "Context: $($p.startup_context)"
    Write-Host "Notes:   $($p.notes)"
}

function Move-To-Archive-Path {
    $reg = @(Load-Reg)
    $p = Pick -List $reg -Title "Select project to move"
    if ($null -eq $p) { return }

    $index = Find-ProjectIndexByName -Projects $reg -Name $p.name
    if ($index -lt 0) {
        Write-Host "Project not found"
        return
    }

    $sourcePath = Get-FullPathOrOriginal -Path $reg[$index].path
    if (!(Test-Path -LiteralPath $sourcePath)) {
        Write-Host "Source path missing: $sourcePath"
        return
    }

    $targetRoot = Read-Host "Archive root path (e.g. E:\CODEX_ARCHIVE)"
    if ([string]::IsNullOrWhiteSpace($targetRoot)) { return }
    $targetRoot = Get-FullPathOrOriginal -Path $targetRoot

    if (!(Test-Path -LiteralPath $targetRoot)) {
        New-DirectoryIfMissing -Path $targetRoot
    }

    $leaf = Split-Path -Path $sourcePath -Leaf
    $dest = Join-Path -Path $targetRoot -ChildPath $leaf
    $resolvedSource = Get-FullPathOrOriginal -Path $sourcePath
    $resolvedDest = Get-FullPathOrOriginal -Path $dest

    if ([string]::Equals($resolvedSource, $resolvedDest, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Source and destination are the same"
        return
    }

    if (Test-Path -LiteralPath $dest) {
        Write-Host "Destination already exists: $dest"
        return
    }

    Write-Host ""
    Write-Host "Move:"
    Write-Host "  From: $sourcePath"
    Write-Host "  To:   $dest"
    $confirm = Read-Host "Proceed? (y/n)"
    if ($confirm.Trim().ToLowerInvariant() -ne "y") { return }

    Move-Item -LiteralPath $sourcePath -Destination $dest -ErrorAction Stop
    $reg[$index].path = $dest
    $reg[$index].status = "archived"
    Save-Reg -Data $reg
    Write-Host "Moved and archived: $($reg[$index].name)"
}

while ($true) {
    try {
        Show-Header
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        break
    }

    Write-Host "1. Resume last"
    Write-Host "2. Active projects"
    Write-Host "3. Deprecated/Archived projects"
    Write-Host "4. Add project"
    Write-Host "5. Deprecate project"
    Write-Host "6. Archive project"
    Write-Host "7. Update project path"
    Write-Host "8. Command library"
    Write-Host "9. Open CODEX root"
    Write-Host "10. Open project registry"
    Write-Host "11. Reactivate project"
    Write-Host "12. Project details"
    Write-Host "13. Move project to archive path"
    Write-Host "0. Exit"
    Write-Host ""

    $c = Read-Host "Choice"

    try {
        switch ($c) {
            "1" {
                Resume-Last
                Pause-Return
            }
            "2" {
                $reg = @(Load-Reg)
                $p = Pick -List (Get-ProjectsByStatus -Projects $reg -Status @("active")) -Title "Active projects"
                Open-Proj -Project $p
                Pause-Return
            }
            "3" {
                $reg = @(Load-Reg)
                $p = Pick -List (Get-ProjectsByStatus -Projects $reg -Status @("deprecated", "archived")) -Title "Deprecated / Archived projects"
                Open-Proj -Project $p
                Pause-Return
            }
            "4" {
                Add-Proj
                Pause-Return
            }
            "5" {
                Set-Status -To "deprecated"
                Pause-Return
            }
            "6" {
                Set-Status -To "archived"
                Pause-Return
            }
            "7" {
                Update-Path
                Pause-Return
            }
            "8" {
                & code -- (Get-CommandLibraryPath)
                Pause-Return
            }
            "9" {
                & explorer.exe (Get-Root)
                Pause-Return
            }
            "10" {
                & code -- (Get-RegPath)
                Pause-Return
            }
            "11" {
                Reactivate-Proj
                Pause-Return
            }
            "12" {
                Show-Project-Details
                Pause-Return
            }
            "13" {
                Move-To-Archive-Path
                Pause-Return
            }
            "0" {
                return
            }
            default {
            }
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-Return
    }
}
