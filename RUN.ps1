$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Root {
    if (
        $null -ne $MyInvocation.MyCommand -and
        $null -ne $MyInvocation.MyCommand.PSObject.Properties["Path"] -and
        $MyInvocation.MyCommand.Path
    ) {
        return Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    }

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
function Get-MachineProfilePath { Join-Path -Path (Get-StateRoot) -ChildPath "machine_profile.json" }
function Get-RecentPath { Join-Path -Path (Get-StateRoot) -ChildPath "recent_projects.json" }
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

function Get-MachineProfile {
    $profilePath = Get-MachineProfilePath
    if (-not (Test-Path -LiteralPath $profilePath)) {
        return New-DefaultMachineProfile
    }

    try {
        $raw = Get-Content -LiteralPath $profilePath -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return New-DefaultMachineProfile
        }

        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return New-DefaultMachineProfile
    }
}

function Save-MachineProfile {
    param([object]$Profile)

    if ($null -eq $Profile) {
        return
    }

    $profilePath = Get-MachineProfilePath
    Ensure-ParentDirectory -Path $profilePath
    $Profile | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $profilePath -Encoding utf8
}

function Get-MachineName {
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        return $env:COMPUTERNAME.Trim().ToUpperInvariant()
    }

    return [System.Environment]::MachineName.Trim().ToUpperInvariant()
}

function New-DefaultMachineProfile {
    $machineName = Get-MachineName
    $defaultPreferredRoot = if (Test-Path -LiteralPath "D:\CODEX_PROJECTS") { "D:\CODEX_PROJECTS" } else { "C:\CODEX_PROJECTS" }

    return [pscustomobject]@{
        active_machine = $machineName
        machines = [pscustomobject]@{
            $machineName = [pscustomobject]@{
                preferred_root = $defaultPreferredRoot
            }
            HOME = [pscustomobject]@{
                preferred_root = "D:\CODEX_PROJECTS"
            }
            OFFICE = [pscustomobject]@{
                preferred_root = "C:\CODEX_PROJECTS"
            }
        }
        fallback_roots = @(
            "D:\CODEX_PROJECTS",
            "C:\CODEX_PROJECTS",
            "E:\CODEX_PROJECTS"
        )
    }
}

function Get-ProfileMachineEntry {
    param([object]$Profile)

    $machineName = Get-MachineName
    if ($null -ne $Profile.machines -and $null -ne $Profile.machines.PSObject.Properties[$machineName]) {
        return $Profile.machines.PSObject.Properties[$machineName].Value
    }

    return $null
}

function Get-PreferredProjectRoot {
    $profile = Get-MachineProfile
    if ($null -eq $profile) {
        return ""
    }

    $machine = Get-ProfileMachineEntry -Profile $profile
    if ($null -ne $machine -and $null -ne $machine.PSObject.Properties["preferred_root"]) {
        $preferredRoot = [string]$machine.preferred_root
        if (-not [string]::IsNullOrWhiteSpace($preferredRoot)) {
            return $preferredRoot.Trim()
        }
    }

    if ($null -ne $profile.PSObject.Properties["preferred_project_root"]) {
        $preferredRoot = [string]$profile.preferred_project_root
        if (-not [string]::IsNullOrWhiteSpace($preferredRoot)) {
            return $preferredRoot.Trim()
        }
    }

    return ""
}

function Get-ProjectPathOverride {
    param([object]$Project)

    if ($null -eq $Project -or [string]::IsNullOrWhiteSpace($Project.name)) {
        return ""
    }

    $profile = Get-MachineProfile
    if ($null -eq $profile) {
        return ""
    }

    $machine = Get-ProfileMachineEntry -Profile $profile
    foreach ($container in @($machine, $profile)) {
        if (
            $null -ne $container -and
            $null -ne $container.PSObject.Properties["project_path_overrides"] -and
            $null -ne $container.project_path_overrides.PSObject.Properties[$Project.name]
        ) {
            $overridePath = [string]$container.project_path_overrides.PSObject.Properties[$Project.name].Value
            if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
                return $overridePath.Trim()
            }
        }
    }

    return ""
}

function Set-PreferredProjectRoot {
    param([string]$RootPath)

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        return
    }

    $profile = Get-MachineProfile
    $machineName = Get-MachineName
    if ($null -eq $profile.PSObject.Properties["machines"]) {
        $profile | Add-Member -MemberType NoteProperty -Name "machines" -Value ([pscustomobject]@{})
    }

    if ($null -eq $profile.machines.PSObject.Properties[$machineName]) {
        $profile.machines | Add-Member -MemberType NoteProperty -Name $machineName -Value ([pscustomobject]@{ preferred_root = $RootPath })
    } else {
        $profile.machines.PSObject.Properties[$machineName].Value.preferred_root = $RootPath
    }

    if ($null -eq $profile.PSObject.Properties["active_machine"]) {
        $profile | Add-Member -MemberType NoteProperty -Name "active_machine" -Value $machineName
    } else {
        $profile.active_machine = $machineName
    }

    if ($null -eq $profile.PSObject.Properties["fallback_roots"]) {
        $profile | Add-Member -MemberType NoteProperty -Name "fallback_roots" -Value @("D:\CODEX_PROJECTS", "C:\CODEX_PROJECTS", "E:\CODEX_PROJECTS")
    }

    Save-MachineProfile -Profile $profile
}

function Load-RecentProjects {
    $recentPath = Get-RecentPath
    if (-not (Test-Path -LiteralPath $recentPath)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $recentPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @()
    }

    if ($parsed -is [System.Array]) {
        return @($parsed)
    }

    return @($parsed)
}

function Save-RecentProjects {
    param([object[]]$Items)

    $recentPath = Get-RecentPath
    Ensure-ParentDirectory -Path $recentPath
    $json = @($Items) | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath $recentPath -Value $json -Encoding utf8
}

function Add-RecentProject {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $now = (Get-Date).ToString("s")
    $updated = @(
        [pscustomobject]@{
            name         = $Project.name
            display_name = Get-Label -Project $Project
            path         = $Project.path
            opened_at    = $now
        }
    )

    foreach ($item in (Load-RecentProjects)) {
        if (-not [string]::Equals([string]$item.name, $Project.name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $updated += $item
        }
    }

    Save-RecentProjects -Items ($updated | Select-Object -First 5)
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

    $normalizedName = Normalize-ProjectKey -Value $Name
    if (-not [string]::IsNullOrWhiteSpace($normalizedName)) {
        $prefixMatches = @()

        for ($i = 0; $i -lt $Projects.Count; $i++) {
            $candidateKeys = @(
                $(Normalize-ProjectKey -Value ([string]$Projects[$i].name)),
                $(Normalize-ProjectKey -Value ([string]$Projects[$i].display_name))
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

            foreach ($candidateKey in $candidateKeys) {
                if ($candidateKey -eq $normalizedName) {
                    return $i
                }

                if ($candidateKey.StartsWith($normalizedName) -or $normalizedName.StartsWith($candidateKey)) {
                    $prefixMatches += $i
                    break
                }
            }
        }

        $uniqueMatches = @($prefixMatches | Select-Object -Unique)
        if ($uniqueMatches.Count -eq 1) {
            return [int]$uniqueMatches[0]
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

function Test-IsGitRepo {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath ".git")
}

function Read-ConsoleInput {
    param([string]$Prompt)

    Write-Host -NoNewline ("{0}: " -f $Prompt)

    try {
        return [Console]::ReadLine()
    } catch {
        return Read-Host $Prompt
    }
}

function Normalize-ProjectKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value -replace '[^A-Za-z0-9]', '').Trim().ToUpperInvariant())
}

function Test-IsZohoCrmProject {
    param([object]$Project)

    if ($null -eq $Project) {
        return $false
    }

    $nameKey = Normalize-ProjectKey -Value $Project.name
    $labelKey = Normalize-ProjectKey -Value (Get-Label -Project $Project)
    return ($nameKey -eq "ZOHOCRM" -or $labelKey -eq "ZOHOCRM")
}

function Get-CurrentTaskPath {
    param([object]$Project)

    $projectPath = Resolve-ProjectPath -Project $Project
    return Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
}

function Get-ConfiguredProjectRoots {
    $profile = Get-MachineProfile
    if ($null -ne $profile.PSObject.Properties["fallback_roots"]) {
        return @($profile.fallback_roots | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @(
        "D:\CODEX_PROJECTS",
        "C:\CODEX_PROJECTS",
        "E:\CODEX_PROJECTS"
    )
}

function Get-ProjectRelativePath {
    param([string]$ConfiguredPath)

    if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return ""
    }

    $trimmed = $ConfiguredPath.Trim()
    foreach ($root in (Get-ConfiguredProjectRoots)) {
        $rootPrefix = $root.TrimEnd("\")
        if ([string]::Equals($trimmed, $rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ""
        }

        if ($trimmed.StartsWith($rootPrefix + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $trimmed.Substring($rootPrefix.Length + 1)
        }
    }

    return ""
}

function Get-ActiveProjectRoot {
    $preferredRoot = Get-PreferredProjectRoot
    if (-not [string]::IsNullOrWhiteSpace($preferredRoot) -and (Test-Path -LiteralPath $preferredRoot)) {
        return $preferredRoot
    }

    foreach ($root in (Get-ConfiguredProjectRoots)) {
        if (Test-Path -LiteralPath $root) {
            Set-PreferredProjectRoot -RootPath $root
            return $root
        }
    }

    return ""
}

function Resolve-ProjectPath {
    param([object]$Project)

    return (Resolve-ProjectPathInfo -Project $Project).Path
}

function Resolve-ProjectPathInfo {
    param([object]$Project)

    if ($null -eq $Project -or [string]::IsNullOrWhiteSpace($Project.path)) {
        return [pscustomobject]@{
            Path              = ""
            Source            = "missing"
            ConfiguredPath    = ""
            OverridePath      = ""
            ConfiguredMissing = $false
        }
    }

    $configuredPath = $Project.path.Trim()
    $configuredMissing = -not (Test-Path -LiteralPath $configuredPath)
    $overridePath = Get-ProjectPathOverride -Project $Project
    if (-not [string]::IsNullOrWhiteSpace($overridePath) -and (Test-Path -LiteralPath $overridePath)) {
        return [pscustomobject]@{
            Path              = $overridePath
            Source            = "override"
            ConfiguredPath    = $configuredPath
            OverridePath      = $overridePath
            ConfiguredMissing = $configuredMissing
        }
    }

    if (Test-Path -LiteralPath $configuredPath) {
        return [pscustomobject]@{
            Path              = $configuredPath
            Source            = "default"
            ConfiguredPath    = $configuredPath
            OverridePath      = $overridePath
            ConfiguredMissing = $false
        }
    }

    $relativePath = Get-ProjectRelativePath -ConfiguredPath $configuredPath
    $activeRoot = Get-ActiveProjectRoot
    if (-not [string]::IsNullOrWhiteSpace($activeRoot) -and -not [string]::IsNullOrWhiteSpace($relativePath)) {
        if (Test-IsZohoCrmProject -Project $Project) {
            foreach ($alias in @("CODEX_CRM", "ZOHO_CRM")) {
                $aliasPath = Join-Path -Path $activeRoot -ChildPath $alias
                if (Test-Path -LiteralPath $aliasPath) {
                    return [pscustomobject]@{
                        Path              = $aliasPath
                        Source            = "fallback"
                        ConfiguredPath    = $configuredPath
                        OverridePath      = $overridePath
                        ConfiguredMissing = $configuredMissing
                    }
                }
            }
        }

        $candidatePath = Join-Path -Path $activeRoot -ChildPath $relativePath
        if (Test-Path -LiteralPath $candidatePath) {
            return [pscustomobject]@{
                Path              = $candidatePath
                Source            = "fallback"
                ConfiguredPath    = $configuredPath
                OverridePath      = $overridePath
                ConfiguredMissing = $configuredMissing
            }
        }

        return [pscustomobject]@{
            Path              = $candidatePath
            Source            = "missing"
            ConfiguredPath    = $configuredPath
            OverridePath      = $overridePath
            ConfiguredMissing = $configuredMissing
        }
    }

    return [pscustomobject]@{
        Path              = $configuredPath
        Source            = "missing"
        ConfiguredPath    = $configuredPath
        OverridePath      = $overridePath
        ConfiguredMissing = $configuredMissing
    }
}

function Resolve-ProjectLaunchContext {
    param([object]$Project)

    $pathInfo = Resolve-ProjectPathInfo -Project $Project
    $projectPath = $pathInfo.Path
    $activeRoot = Get-ActiveProjectRoot

    return [pscustomobject]@{
        ActiveProjectRoot = $activeRoot
        SelectedProject   = Get-Label -Project $Project
        ProjectPath       = $projectPath
        PathSource        = $pathInfo.Source
        ConfiguredMissing = $pathInfo.ConfiguredMissing
    }
}

function Get-LiteOpsFileNames {
    return @(
        "CURRENT_TASK.md",
        "DECISIONS.md",
        "KNOWN_GOOD_STATE.md"
    )
}

function Initialize-LiteOpsFiles {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = Resolve-ProjectPath -Project $Project
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ""
        Write-Host "Missing path: $projectPath" -ForegroundColor Yellow
        return
    }

    $templates = @{
        "CURRENT_TASK.md" = @(
            "# CURRENT TASK",
            "",
            "- Objective:",
            "- Next step:",
            "- Notes:"
        )
        "DECISIONS.md" = @(
            "# DECISIONS",
            "",
            "- Date:",
            "- Decision:",
            "- Reason:"
        )
        "KNOWN_GOOD_STATE.md" = @(
            "# KNOWN GOOD STATE",
            "",
            "- Date:",
            "- State:",
            "- Verify:"
        )
    }

    $created = @()
    foreach ($fileName in (Get-LiteOpsFileNames)) {
        $filePath = Join-Path -Path $projectPath -ChildPath $fileName
        if (Test-Path -LiteralPath $filePath) {
            continue
        }

        $templates[$fileName] | Set-Content -LiteralPath $filePath -Encoding utf8
        $created += $filePath
    }

    if ($created.Count -eq 0) {
        Write-Host "Lite Ops files already present for $(Get-Label -Project $Project)." -ForegroundColor DarkGray
        return
    }

    foreach ($path in $created) {
        Write-Host "Created: $path" -ForegroundColor Green
    }
}

function Show-Header {
    $reg = @(Load-Reg)
    $active = @(Get-ProjectsByStatus -Projects $reg -Status @("active")).Count
    $deprecated = @(Get-ProjectsByStatus -Projects $reg -Status @("deprecated")).Count
    $archived = @(Get-ProjectsByStatus -Projects $reg -Status @("archived")).Count
    $last = Get-LastProjectName
    $recent = @(Load-RecentProjects)
    $activeRoot = Get-ActiveProjectRoot

    Clear-Host
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host "               CODEX HUB LAUNCHER            " -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host (" Active: {0}   Deprecated: {1}   Archived: {2}" -f $active, $deprecated, $archived) -ForegroundColor Gray
    Write-Host (" Active root: {0}" -f $activeRoot) -ForegroundColor DarkCyan
    if ($last) {
        Write-Host (" Last: {0}" -f $last) -ForegroundColor DarkGray
    }
    if ($recent.Count -gt 0) {
        $recentLabels = @($recent | Select-Object -First 3 | ForEach-Object { $_.display_name })
        Write-Host (" Recent: {0}" -f ($recentLabels -join " | ")) -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Open-Proj {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $launchContext = Resolve-ProjectLaunchContext -Project $Project
    $projectPath = $launchContext.ProjectPath
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ""
        Write-Host "Missing path: $projectPath" -ForegroundColor Yellow
        Write-Host ("Path source: {0}" -f $launchContext.PathSource) -ForegroundColor Yellow
        return
    }

    Set-LastProjectName -Name $Project.name
    Add-RecentProject -Project $Project

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
`$liteOpsFiles = @('CURRENT_TASK.md', 'DECISIONS.md', 'KNOWN_GOOD_STATE.md')

Set-Location -LiteralPath `$projectPath

Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host " `$displayName" -ForegroundColor Cyan
Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host "Active project root: $($launchContext.ActiveProjectRoot)" -ForegroundColor DarkCyan
Write-Host "Selected project: $($launchContext.SelectedProject)" -ForegroundColor DarkCyan
Write-Host "Resolved project path: `$projectPath" -ForegroundColor DarkCyan
Write-Host "Path source: $($launchContext.PathSource)" -ForegroundColor DarkCyan
if ($($launchContext.ConfiguredMissing.ToString().ToLowerInvariant())) {
    Write-Host 'Configured registry path is missing on this machine; resolved path used instead.' -ForegroundColor Yellow
}
Write-Host "Path: `$projectPath" -ForegroundColor Gray
Write-Host "Context: `$startupContext" -ForegroundColor DarkGray
Write-Host ''

foreach (`$fileName in `$liteOpsFiles) {
    `$filePath = Join-Path -Path `$projectPath -ChildPath `$fileName
    Write-Host `$fileName -ForegroundColor Magenta
    Write-Host ('-' * `$fileName.Length) -ForegroundColor DarkMagenta
    if (Test-Path -LiteralPath `$filePath) {
        Get-Content -LiteralPath `$filePath -Encoding utf8
    } else {
        Write-Host 'missing' -ForegroundColor Yellow
    }
    Write-Host ''
}

if (Test-Path -LiteralPath '.\.git') {
    Write-Host 'git status -sb' -ForegroundColor Magenta
    Write-Host '--------------' -ForegroundColor DarkMagenta
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

function Open-ProjInCodexApp {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $pathInfo = Resolve-ProjectPathInfo -Project $Project
    $projectPath = $pathInfo.Path
    if (-not (Test-Path -LiteralPath $projectPath)) {
        Write-Host ""
        Write-Host "Missing path: $projectPath" -ForegroundColor Yellow
        Write-Host ("Path source: {0}" -f $pathInfo.Source) -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host ("Codex App project path: {0}" -f $projectPath) -ForegroundColor Cyan
    Write-Host ("Path source: {0}" -f $pathInfo.Source) -ForegroundColor DarkCyan
    if (Get-Command codex -ErrorAction SilentlyContinue) {
        & codex app $projectPath
        Write-Host ("If Codex Desktop did not open this workspace automatically, open it manually with: {0}" -f $projectPath) -ForegroundColor Yellow
    } else {
        Write-Host "codex CLI not found in PATH. Open Codex Desktop manually and use this project path." -ForegroundColor Yellow
    }
}

function Pick-Project {
    param(
        [object[]]$Projects,
        [string]$Title
    )

    $items = @($Projects | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) {
        Write-Host "No projects available." -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $items.Count; $i++) {
        $project = $items[$i]
        $pathInfo = Resolve-ProjectPathInfo -Project $project
        $resolvedPath = $pathInfo.Path
        $repoStatus = if (Test-IsGitRepo -Path $resolvedPath) { "git" } else { "folder" }
        Write-Host ("{0,2}. {1}" -f ($i + 1), (Get-Label -Project $project)) -ForegroundColor White
        Write-Host ("    {0} [{1}; source: {2}]" -f $resolvedPath, $repoStatus, $pathInfo.Source) -ForegroundColor DarkGray
        if ($pathInfo.ConfiguredMissing) {
            Write-Host ("    warning: configured path missing: {0}" -f $pathInfo.ConfiguredPath) -ForegroundColor Yellow
        }
    }

    Write-Host ""
    $rawSelection = Read-ConsoleInput "Select project #"
    if ([string]::IsNullOrWhiteSpace($rawSelection)) {
        return $null
    }

    if ($rawSelection -match '^\d+$') {
        $index = [int]$rawSelection - 1
        if ($index -ge 0 -and $index -lt $items.Count) {
            return $items[$index]
        }
    }

    Write-Host "Invalid selection." -ForegroundColor Yellow
    return $null
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

function Open-CurrentTaskQuick {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = Resolve-ProjectPath -Project $Project
    $taskPath = Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $taskPath)) {
        Write-Host "CURRENT_TASK.md not found for $($Project.name)." -ForegroundColor Yellow
        return
    }

    $taskPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $taskPath
    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", "Get-Content -LiteralPath $taskPathLiteral -Encoding utf8"
    ) | Out-Null
}

function Show-RecentProjectsMenu {
    $reg = @(Load-Reg)
    $recentEntries = @(Load-RecentProjects)
    $resolved = @()

    foreach ($entry in $recentEntries) {
        $index = Find-ProjectIndexByName -Projects $reg -Name $entry.name
        if ($index -ge 0) {
            $resolved += $reg[$index]
        }
    }

    $selected = Pick-Project -Projects $resolved -Title "Recent Projects"
    if ($null -ne $selected) {
        Open-Proj -Project $selected
    }
}

function Show-CodexAppProjectsMenu {
    $reg = @(Load-Reg)
    $activeProjects = @(Get-ProjectsByStatus -Projects $reg -Status @("active"))
    $selected = Pick-Project -Projects $activeProjects -Title "Open in Codex App"
    if ($null -ne $selected) {
        Open-ProjInCodexApp -Project $selected
    }
}

function New-SnapshotHandoff {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = Resolve-ProjectPath -Project $Project
    $snapshotDir = Join-Path -Path $projectPath -ChildPath "SNAPSHOT"
    if (-not (Test-Path -LiteralPath $snapshotDir)) {
        Write-Host "SNAPSHOT folder not found: $snapshotDir" -ForegroundColor Yellow
        return
    }

    $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $fileName = "HANDOFF_$stamp.md"
    $snapshotPath = Join-Path -Path $snapshotDir -ChildPath $fileName
    $taskPath = Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
    $currentTaskSummary = if (Test-Path -LiteralPath $taskPath) { Get-Content -LiteralPath $taskPath -TotalCount 12 -Encoding utf8 } else { @("CURRENT_TASK.md not found.") }

    $content = @(
        "# HANDOFF SNAPSHOT"
        ""
        "- Project: $(Get-Label -Project $Project)"
        "- Path: $projectPath"
        "- Created: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
        "- Git repo: $(if (Test-IsGitRepo -Path $projectPath) { 'Yes' } else { 'No' })"
        ""
        "## Resume Point"
        "- Record the next exact action here."
        ""
        "## Current Task Snapshot"
    ) + $currentTaskSummary

    $content | Set-Content -LiteralPath $snapshotPath -Encoding utf8
    Write-Host "Created snapshot: $snapshotPath" -ForegroundColor Green
}

while ($true) {
    Show-Header
    $activeProjects = @(Get-ProjectsByStatus -Projects (Load-Reg) -Status @("active"))

    for ($i = 0; $i -lt $activeProjects.Count; $i++) {
        $project = $activeProjects[$i]
        $menuNumber = $i + 1
        $pathInfo = Resolve-ProjectPathInfo -Project $project
        $resolvedPath = $pathInfo.Path
        $repoStatus = if (Test-IsGitRepo -Path $resolvedPath) { "git repo" } else { "folder only" }
        Write-Host ("{0,2}. {1}" -f $menuNumber, (Get-Label -Project $project)) -ForegroundColor White
        Write-Host ("    {0}" -f $resolvedPath) -ForegroundColor DarkGray
        Write-Host ("    status: {0}; source: {1}" -f $repoStatus, $pathInfo.Source) -ForegroundColor DarkCyan
        if ($pathInfo.ConfiguredMissing) {
            Write-Host ("    warning: configured path missing: {0}" -f $pathInfo.ConfiguredPath) -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "R. Resume last project" -ForegroundColor Cyan
    Write-Host "J. Open from recent projects" -ForegroundColor Cyan
    Write-Host "T. Quick-open CURRENT_TASK.md" -ForegroundColor Cyan
    Write-Host "S. Create snapshot handoff" -ForegroundColor Cyan
    Write-Host "A. Open in Codex App" -ForegroundColor Cyan
    Write-Host "C. Open command library" -ForegroundColor Cyan
    Write-Host "H. Open CODEX root" -ForegroundColor Cyan
    Write-Host "V. Initialize CODEX LITE OPS files" -ForegroundColor Cyan
    Write-Host "0. Exit" -ForegroundColor Cyan
    Write-Host ""

    $rawSelection = Read-ConsoleInput "Select an option"
    if ($null -eq $rawSelection) {
        break
    }

    $selection = $rawSelection.Trim()
    if ([string]::IsNullOrWhiteSpace($selection)) {
        continue
    }

    switch -Regex ($selection) {
        '^0$' { return }
        '^[Rr]$' {
            Resume-Last
            continue
        }
        '^[Jj]$' {
            Show-RecentProjectsMenu
            continue
        }
        '^[Tt]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Quick-Open CURRENT_TASK.md"
            if ($null -ne $project) {
                Open-CurrentTaskQuick -Project $project
            }
            continue
        }
        '^[Ss]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Create Snapshot Handoff"
            if ($null -ne $project) {
                New-SnapshotHandoff -Project $project
            }
            continue
        }
        '^[Aa]$' {
            Show-CodexAppProjectsMenu
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
        '^[Vv]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Initialize CODEX LITE OPS files"
            if ($null -ne $project) {
                Initialize-LiteOpsFiles -Project $project
            }
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
