param(
    [ValidateSet("LIGHT", "FULL_AUDIT")]
    [string]$OperationalMode = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Root {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    throw "PSScriptRoot is unavailable; CodexHub root cannot be derived safely."
}

function Get-RegPath { Join-Path -Path (Get-Root) -ChildPath "projects\projects.json" }
function Get-StateRoot { Join-Path -Path (Get-Root) -ChildPath "state" }
function Get-LastPath { Join-Path -Path (Get-StateRoot) -ChildPath "last_project.txt" }
function Get-LastProjectRootPath { Join-Path -Path (Get-StateRoot) -ChildPath "last_project_root.txt" }
function Get-LocalMachineProfilePath { Join-Path -Path (Get-StateRoot) -ChildPath "local\machine.local.json" }
function Get-RecentPath { Join-Path -Path (Get-StateRoot) -ChildPath "recent_projects.json" }
function Get-PromptsRoot { Join-Path -Path (Get-Root) -ChildPath "prompts" }
function Get-CommandLibraryPath { Join-Path -Path (Get-Root) -ChildPath "COMMAND_LIBRARY.md" }
function Get-HubPromptPath { param([string]$FileName) Join-Path -Path (Get-PromptsRoot) -ChildPath $FileName }
function Get-TemplatesRoot { Join-Path -Path (Get-Root) -ChildPath "templates" }
function Get-ToolsRoot { Join-Path -Path (Get-Root) -ChildPath "tools" }
function Get-CodexSyncRoot { Split-Path -Path (Get-Root) -Parent }

function Resolve-OperationalMode {
    param([string]$RequestedMode = "")

    foreach ($candidate in @($RequestedMode, $env:CODEXHUB_OPERATIONAL_MODE)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $normalized = $candidate.Trim().ToUpperInvariant()
        if ($normalized -in @("LIGHT", "FULL_AUDIT")) {
            return $normalized
        }
    }

    return "LIGHT"
}

function Get-OperationalModeSettings {
    param([string]$Mode)

    $resolvedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "LIGHT" } else { $Mode.Trim().ToUpperInvariant() }
    $isFullAudit = $resolvedMode -eq "FULL_AUDIT"

    return [pscustomobject]@{
        Mode = $resolvedMode
        TokenDisciplineActive = (-not $isFullAudit)
        CurrentTaskReadMode = if ($isFullAudit) { "full" } else { "authoritative" }
    }
}

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

function Get-RegistryConfig {
    $regPath = Get-RegPath
    if (-not (Test-Path -LiteralPath $regPath)) {
        throw "Project registry not found: $regPath"
    }

    $raw = Get-Content -LiteralPath $regPath -Raw -Encoding utf8
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

    if ($parsed -is [System.Array]) {
        return [pscustomobject]@{
            authoritative_root = Get-CodexSyncRoot
            projects = @($parsed)
        }
    }

    $projects = @()
    if ($null -ne $parsed.PSObject.Properties["projects"]) {
        $projects = @($parsed.projects)
    }

    return [pscustomobject]@{
        authoritative_root = if ($null -ne $parsed.PSObject.Properties["authoritative_root"]) { [string]$parsed.authoritative_root } else { Get-CodexSyncRoot }
        projects = $projects
    }
}

function Load-Reg {
    $config = Get-RegistryConfig
    return @($config.projects | ForEach-Object { ConvertTo-ProjectRecord $_ } | Where-Object { $null -ne $_ })
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

function Get-MachineName {
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        return $env:COMPUTERNAME.Trim().ToUpperInvariant()
    }

    return [System.Environment]::MachineName.Trim().ToUpperInvariant()
}

function Get-LocalMachineProfile {
    $profilePath = Get-LocalMachineProfilePath
    if (-not (Test-Path -LiteralPath $profilePath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $profilePath -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-ProjectPathOverride {
    param([object]$Project)

    if ($null -eq $Project -or [string]::IsNullOrWhiteSpace($Project.name)) {
        return ""
    }

    $profile = Get-LocalMachineProfile
    if (
        $null -ne $profile -and
        $null -ne $profile.PSObject.Properties["projects"] -and
        $null -ne $profile.projects.PSObject.Properties[$Project.name]
    ) {
        $overridePath = [string]$profile.projects.PSObject.Properties[$Project.name].Value
        if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
            return $overridePath.Trim()
        }
    }

    return ""
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

function Save-Reg {
    param([object[]]$Projects)

    $regPath = Get-RegPath
    Ensure-ParentDirectory -Path $regPath
    [pscustomobject]@{
        authoritative_root = Get-AuthoritativeRoot
        projects = @($Projects)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $regPath -Encoding utf8
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

function Get-CurrentTaskPath {
    param([object]$Project)

    $projectPath = Resolve-ProjectPath -Project $Project
    return Join-Path -Path $projectPath -ChildPath "CURRENT_TASK.md"
}

function Get-AuthoritativeRoot {
    $config = Get-RegistryConfig
    $root = if ($null -ne $config -and $null -ne $config.PSObject.Properties["authoritative_root"]) { [string]$config.authoritative_root } else { "" }
    if ([string]::IsNullOrWhiteSpace($root)) {
        return Get-CodexSyncRoot
    }

    return $root.TrimEnd("\")
}

function Get-ActiveProjectRoot {
    $syncRoot = Get-AuthoritativeRoot
    if ([string]::IsNullOrWhiteSpace($syncRoot) -or -not (Test-Path -LiteralPath $syncRoot)) {
        return ""
    }

    return $syncRoot
}

function Get-LegacyFallbackRoots {
    return @(
        "D:\CODEX_PROJECTS",
        "C:\CODEX_PROJECTS"
    )
}

function Get-AuthorityCandidatePath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($RelativePath)) {
        return ""
    }

    return (Join-Path -Path $Root.TrimEnd("\") -ChildPath $RelativePath)
}

function Test-DeprecatedRootPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return $Path -match '^[Cc]:\\CODEX_PROJECTS(\\|$)'
}

function Get-NormalizedResumeRepoPath {
    param(
        [object]$Project,
        [string]$SavedRepoPath
    )

    if ($null -eq $Project -or [string]::IsNullOrWhiteSpace($SavedRepoPath)) {
        return $SavedRepoPath
    }

    $relativePath = Get-ProjectRelativePath -ConfiguredPath $Project.path
    $authoritativeCandidate = Get-AuthorityCandidatePath -Root (Get-AuthoritativeRoot) -RelativePath $relativePath
    if (-not [string]::IsNullOrWhiteSpace($authoritativeCandidate) -and
        (Test-Path -LiteralPath $authoritativeCandidate) -and
        $SavedRepoPath -match '^[CDcd]:\\CODEX_PROJECTS(\\|$)') {
        return $authoritativeCandidate
    }

    return $SavedRepoPath
}

function Initialize-AuthorityState {
    $authorityRoot = Get-AuthoritativeRoot
    if ([string]::IsNullOrWhiteSpace($authorityRoot)) {
        return
    }

    $lastProjectRootPath = Get-LastProjectRootPath
    Ensure-ParentDirectory -Path $lastProjectRootPath
    Set-Content -LiteralPath $lastProjectRootPath -Value $authorityRoot -Encoding utf8
}

function Get-ProjectRelativePath {
    param([string]$ConfiguredPath)

    if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return ""
    }

    return (Split-Path -Path $ConfiguredPath.TrimEnd("\") -Leaf)
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
            TaskPath          = ""
            TaskExists        = $false
            Reason            = "Project registry entry has no path."
        }
    }

    $configuredPath = $Project.path.Trim()
    $overridePath = Get-ProjectPathOverride -Project $Project
    $relativePath = Get-ProjectRelativePath -ConfiguredPath $configuredPath
    $authoritativeRoot = Get-AuthoritativeRoot
    $authoritativePath = Get-AuthorityCandidatePath -Root $authoritativeRoot -RelativePath $relativePath
    $legacyFallbackPaths = @(Get-LegacyFallbackRoots | ForEach-Object { Get-AuthorityCandidatePath -Root $_ -RelativePath $relativePath } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $resolvedPath = ""
    $source = "missing"
    $reason = "Project path could not be resolved."
    $authorityConflict = $false
    $existingCandidates = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @($configuredPath, $authoritativePath) + $legacyFallbackPaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if ((Test-Path -LiteralPath $candidate) -and -not ($existingCandidates.Contains($candidate))) {
            $existingCandidates.Add($candidate) | Out-Null
        }
    }

    if ($existingCandidates.Count -gt 1) {
        $authorityConflict = $true
    }

    $candidates = @(
        [pscustomobject]@{ Path = $overridePath; Source = "override"; Reason = "Local machine override path is missing."; Deprecated = $false },
        [pscustomobject]@{ Path = $configuredPath; Source = "explicit"; Reason = "Explicit project path is missing."; Deprecated = $false },
        [pscustomobject]@{ Path = $authoritativePath; Source = "authoritative"; Reason = "Authoritative root candidate is missing."; Deprecated = $false }
    )
    foreach ($fallbackPath in $legacyFallbackPaths) {
        $deprecatedNote = if (Test-DeprecatedRootPath -Path $fallbackPath) { "Deprecated legacy root candidate is missing." } else { "Legacy fallback candidate is missing." }
        $candidates += [pscustomobject]@{ Path = $fallbackPath; Source = "deprecated-fallback"; Reason = $deprecatedNote; Deprecated = $true }
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Path)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidate.Path)) {
            $resolvedPath = [string]$candidate.Path
            $source = [string]$candidate.Source
            $reason = [string]$candidate.Reason
            continue
        }

        $taskCandidate = Join-Path -Path $candidate.Path -ChildPath "CURRENT_TASK.md"
        if (-not (Test-Path -LiteralPath $taskCandidate)) {
            $resolvedPath = [string]$candidate.Path
            $source = [string]$candidate.Source
            $reason = "Resolved project path does not contain CURRENT_TASK.md."
            continue
        }

        $resolvedPath = [string]$candidate.Path
        $source = [string]$candidate.Source
        $reason = ""
        if ($candidate.Deprecated) {
            $reason = "Using deprecated legacy fallback root as a recovery hint only."
        }
        break
    }

    $taskPath = if ([string]::IsNullOrWhiteSpace($resolvedPath)) { "" } else { Join-Path -Path $resolvedPath -ChildPath "CURRENT_TASK.md" }
    $taskExists = (-not [string]::IsNullOrWhiteSpace($taskPath)) -and (Test-Path -LiteralPath $taskPath)
    if ([string]::IsNullOrWhiteSpace($reason) -and -not $taskExists) {
        $source = "missing"
        $reason = "Resolved project path does not contain CURRENT_TASK.md."
    }
    if ($authorityConflict) {
        $reason = @(
            "ROOT AUTHORITY CONFLICT",
            $(if ([string]::IsNullOrWhiteSpace($reason)) { "Multiple roots detected for the same repo." } else { $reason })
        ) -join " | "
    }

    return [pscustomobject]@{
        Path              = $resolvedPath
        Source            = $source
        ConfiguredPath    = $configuredPath
        OverridePath      = $overridePath
        ConfiguredMissing = -not (Test-Path -LiteralPath $configuredPath)
        TaskPath          = $taskPath
        TaskExists        = $taskExists
        Reason            = $reason
        AuthorityRoot     = $authoritativeRoot
        AuthorityConflict = $authorityConflict
        ExistingCandidates = @($existingCandidates)
    }
}

function Resolve-ProjectLaunchContext {
    param([object]$Project)

    $pathInfo = Resolve-ProjectPathInfo -Project $Project
    $projectPath = $pathInfo.Path
    $activeRoot = Get-ActiveProjectRoot

    return [pscustomobject]@{
        CodexHubRoot      = Get-Root
        CodexSyncRoot     = $activeRoot
        OperationalMode   = $script:CodexHubOperationalMode
        SelectedProject   = Get-Label -Project $Project
        ProjectPath       = $projectPath
        CurrentTaskPath   = $pathInfo.TaskPath
        PathSource        = $pathInfo.Source
        ConfiguredMissing = $pathInfo.ConfiguredMissing
        Ready             = ((-not [string]::IsNullOrWhiteSpace($projectPath)) -and (Test-Path -LiteralPath $projectPath) -and $pathInfo.TaskExists)
        FailureReason     = $pathInfo.Reason
    }
}

function Get-ProjectGitSummary {
    param([string]$ProjectPath)

    if (-not (Test-IsGitRepo -Path $ProjectPath)) {
        return [pscustomobject]@{
            Branch = "no git"
            Head = ""
            DirtyCount = 0
            State = "NO-GIT"
            Detached = $false
            StatusSummary = "Not a git repository."
        }
    }

    $branch = (& git -C $ProjectPath rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        $branch = "unknown"
    }

    $head = (& git -C $ProjectPath rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        $head = ""
    }

    $status = @(& git -C $ProjectPath status --porcelain 2>$null)
    $dirtyCount = if ($LASTEXITCODE -eq 0) { $status.Count } else { 0 }
    $detached = [string]::Equals($branch, "HEAD", [System.StringComparison]::OrdinalIgnoreCase)
    $statusSummary = & git -C $ProjectPath status -sb 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($statusSummary)) {
        $statusSummary = if ($dirtyCount -gt 0) { "dirty" } else { "clean" }
    }

    return [pscustomobject]@{
        Branch = $branch
        Head = [string]$head
        DirtyCount = $dirtyCount
        State = if ($dirtyCount -gt 0) { "DIRTY (+$dirtyCount)" } else { "CLEAN" }
        Detached = $detached
        StatusSummary = [string]$statusSummary
    }
}

function Get-ProjectCurrentTaskDigest {
    param([string]$ProjectPath)

    $taskPath = Join-Path -Path $ProjectPath -ChildPath "CURRENT_TASK.md"
    if (-not (Test-Path -LiteralPath $taskPath)) {
        return [pscustomobject]@{
            Path = $taskPath
            Exists = $false
            Hash = ""
            LastWriteTime = $null
            Timestamp = ""
        }
    }

    $item = Get-Item -LiteralPath $taskPath
    $hash = ""
    try {
        $hash = (Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash
    } catch {
        $hash = ""
    }

    return [pscustomobject]@{
        Path = $taskPath
        Exists = $true
        Hash = [string]$hash
        LastWriteTime = $item.LastWriteTime
        Timestamp = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Get-ProjectResumeStatePath {
    param([string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return ""
    }

    $safeProjectName = ($ProjectName -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeProjectName)) {
        $safeProjectName = "PROJECT"
    }

    return Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_resume_state.json" -f $safeProjectName)
}

function Get-CodexSessionId {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) {
        return $env:CODEX_THREAD_ID.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_SESSION_ID)) {
        return $env:CODEX_SESSION_ID.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_RESUME_SESSION_ID)) {
        return $env:CODEX_RESUME_SESSION_ID.Trim()
    }

    return ""
}

function Load-ProjectResumeState {
    param(
        [string]$ProjectName,
        [object]$Project = $null
    )

    $statePath = Get-ProjectResumeStatePath -ProjectName $ProjectName
    if ([string]::IsNullOrWhiteSpace($statePath) -or -not (Test-Path -LiteralPath $statePath)) {
        return $null
    }

    try {
        $resumeState = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $Project) {
            $originalRepoPath = [string]$resumeState.repo_path
            $normalizedRepoPath = Get-NormalizedResumeRepoPath -Project $Project -SavedRepoPath $originalRepoPath
            if (-not [string]::Equals($originalRepoPath, $normalizedRepoPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $resumeState.repo_path = $normalizedRepoPath
                $resumeState | Add-Member -NotePropertyName deprecated_root_reference -NotePropertyValue $false -Force
                Save-ProjectResumeState -State $resumeState -ProjectName $ProjectName | Out-Null
            } elseif (Test-DeprecatedRootPath -Path $originalRepoPath) {
                $resumeState | Add-Member -NotePropertyName deprecated_root_reference -NotePropertyValue $true -Force
            }
        }

        return $resumeState
    } catch {
        return $null
    }
}

function Save-ProjectResumeState {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$ProjectName
    )

    $statePath = Get-ProjectResumeStatePath -ProjectName $ProjectName
    if ([string]::IsNullOrWhiteSpace($statePath)) {
        return ""
    }

    Ensure-ParentDirectory -Path $statePath
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding utf8
    return $statePath
}

function Get-ProjectResumeValidation {
    param(
        [object]$Project,
        [object]$GitSummary,
        [object]$TaskDigest,
        [object]$ResumeState,
        [object]$SnapshotInfo
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $state = "CLEAN"
    $machineName = [string]$env:COMPUTERNAME
    $crossMachine = $false
    $recommendedMode = "resume"
    $resumeCommand = ""
    $pathInfo = if ($null -ne $Project) { Resolve-ProjectPathInfo -Project $Project } else { $null }
    $projectPathValue = if ($null -ne $pathInfo) { [string]$pathInfo.Path } else { "" }
    $projectNameValue = if ($null -ne $Project -and $null -ne $Project.PSObject.Properties["name"]) { [string]$Project.name } else { "" }
    $currentTaskHash = if ($null -ne $TaskDigest) { [string]$TaskDigest.Hash } else { "" }
    $currentTaskTimestamp = if ($null -ne $TaskDigest) { [string]$TaskDigest.Timestamp } else { "" }
    $runtimeVersion = ""
    $deployVersion = 0
    if ($null -ne $SnapshotInfo) {
        if ($SnapshotInfo.PSObject.Properties["apps_script_version"]) { $runtimeVersion = [string]$SnapshotInfo.apps_script_version }
        if ($SnapshotInfo.PSObject.Properties["apps_script_deploy_version_number"]) { $deployVersion = [int]$SnapshotInfo.apps_script_deploy_version_number }
        if ([string]::IsNullOrWhiteSpace($runtimeVersion) -and $SnapshotInfo.PSObject.Properties["version"]) { $runtimeVersion = [string]$SnapshotInfo.version }
        if ($deployVersion -le 0 -and $SnapshotInfo.PSObject.Properties["deployVersion"]) { $deployVersion = [int]$SnapshotInfo.deployVersion }
    }

    if ($null -eq $ResumeState) {
        return [pscustomobject]@{
            State = "BLOCKED"
            Reasons = @("Missing resume state.")
            ResumeCommand = ""
            RecommendedMode = "reconstruct"
            CrossMachine = $false
            ResumeAvailable = $false
            SavedSessionId = ""
            CurrentTaskHash = $currentTaskHash
            CurrentTaskTimestamp = $currentTaskTimestamp
            SavedMachineName = ""
            CurrentMachineName = $machineName
            SavedBranch = ""
            CurrentBranch = if ($null -ne $GitSummary) { [string]$GitSummary.Branch } else { "" }
            SavedHead = ""
            CurrentHead = if ($null -ne $GitSummary) { [string]$GitSummary.Head } else { "" }
            RuntimeVersion = $runtimeVersion
            DeployVersion = $deployVersion
        }
    }

    $savedSessionId = [string]$ResumeState.codex_session_id
    $savedRepoPath = [string]$ResumeState.repo_path
    $savedMachineName = [string]$ResumeState.machine_name
    $savedBranch = [string]$ResumeState.branch
    $savedHead = [string]$ResumeState.git_head
    $savedTaskHash = [string]$ResumeState.current_task_hash
    $savedTaskTimestamp = if ($null -ne $ResumeState.PSObject.Properties["current_task_timestamp"]) { [string]$ResumeState.current_task_timestamp } else { "" }
    $savedRuntimeVersion = [string]$ResumeState.runtime_version
    $savedDeployVersion = [int]($ResumeState.deploy_version_number | ForEach-Object { $_ })
    if ($savedDeployVersion -eq 0 -and $null -ne $ResumeState.PSObject.Properties["deploy_version_number"]) {
        $savedDeployVersion = [int]$ResumeState.deploy_version_number
    }

    if ([string]::IsNullOrWhiteSpace($savedSessionId)) {
        $state = "BLOCKED"
        $reasons.Add("Missing Codex session ID.") | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($projectPathValue) -or -not (Test-Path -LiteralPath $projectPathValue)) {
        $state = "BLOCKED"
        $reasons.Add("Project path is missing.") | Out-Null
    }

    if ($null -eq $GitSummary -or [string]::IsNullOrWhiteSpace([string]$GitSummary.Branch) -or [string]::Equals([string]$GitSummary.State, "NO-GIT", [System.StringComparison]::OrdinalIgnoreCase)) {
        $state = "BLOCKED"
        $reasons.Add("Git repository is missing.") | Out-Null
    } elseif ($GitSummary.Detached) {
        $state = "BLOCKED"
        $reasons.Add("Detached HEAD detected.") | Out-Null
    }

    if ($null -eq $TaskDigest -or -not $TaskDigest.Exists) {
        $state = "BLOCKED"
        $reasons.Add("CURRENT_TASK.md is missing.") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($savedRepoPath) -and -not [string]::Equals($savedRepoPath, $projectPathValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $state = "BLOCKED"
        $reasons.Add("Saved repo path does not match the selected project path.") | Out-Null
    }
    if ($null -ne $pathInfo -and $pathInfo.AuthorityConflict) {
        $state = "BLOCKED"
        $reasons.Add("ROOT AUTHORITY CONFLICT") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($savedMachineName) -and -not [string]::Equals($savedMachineName, $machineName, [System.StringComparison]::OrdinalIgnoreCase)) {
        $crossMachine = $true
        if ($state -ne "BLOCKED") {
            $state = "WARNING"
        }
        $reasons.Add("CROSS-MACHINE RESUME") | Out-Null
    }

    if ($null -ne $GitSummary -and -not [string]::IsNullOrWhiteSpace($savedBranch) -and -not [string]::Equals($savedBranch, [string]$GitSummary.Branch, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($state -ne "BLOCKED") {
            $state = "WARNING"
        }
        $reasons.Add("Branch changed since last shutdown.") | Out-Null
    }

    if ($null -ne $GitSummary -and -not [string]::IsNullOrWhiteSpace($savedHead) -and -not [string]::Equals($savedHead, [string]$GitSummary.Head, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($state -ne "BLOCKED") {
            $state = "WARNING"
        }
        $reasons.Add("Git HEAD changed since last shutdown.") | Out-Null
    }

    if ($null -ne $GitSummary -and $GitSummary.DirtyCount -gt 0) {
        if ($state -ne "BLOCKED") {
            $state = "WARNING"
        }
        $reasons.Add(("Working tree has {0} change(s)." -f $GitSummary.DirtyCount)) | Out-Null
    }

    if ($null -ne $TaskDigest -and $TaskDigest.Exists -and -not [string]::IsNullOrWhiteSpace($savedTaskHash) -and -not [string]::Equals($savedTaskHash, $currentTaskHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($state -ne "BLOCKED") {
            $state = "WARNING"
        }
        $reasons.Add("CURRENT_TASK.md changed since last shutdown.") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($savedRuntimeVersion) -and -not [string]::IsNullOrWhiteSpace($runtimeVersion) -and -not [string]::Equals($savedRuntimeVersion, $runtimeVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
        $state = "BLOCKED"
        $reasons.Add("Runtime version changed since last shutdown.") | Out-Null
    }

    if ($savedDeployVersion -gt 0 -and $deployVersion -gt 0 -and $savedDeployVersion -ne $deployVersion) {
        $state = "BLOCKED"
        $reasons.Add("Deploy version changed since last shutdown.") | Out-Null
    }

    if ($state -eq "BLOCKED") {
        $recommendedMode = "reconstruct"
    } elseif ($state -eq "WARNING") {
        $recommendedMode = "reconstruct"
    }

    if ($state -eq "CLEAN" -and -not [string]::IsNullOrWhiteSpace($savedSessionId)) {
        $resumeCommand = "codex resume $savedSessionId"
    } elseif (-not [string]::IsNullOrWhiteSpace($savedSessionId)) {
        $resumeCommand = "codex resume $savedSessionId"
    }

    return [pscustomobject]@{
        State = $state
        Reasons = @($reasons)
        ResumeCommand = $resumeCommand
        RecommendedMode = $recommendedMode
        CrossMachine = $crossMachine
        ResumeAvailable = (-not [string]::IsNullOrWhiteSpace($savedSessionId))
        SavedSessionId = $savedSessionId
        SavedRepoPath = $savedRepoPath
        SavedMachineName = $savedMachineName
        SavedBranch = $savedBranch
        SavedHead = $savedHead
        SavedTaskHash = $savedTaskHash
        SavedTaskTimestamp = $savedTaskTimestamp
        SavedRuntimeVersion = $savedRuntimeVersion
        SavedDeployVersion = $savedDeployVersion
        CurrentTaskHash = $currentTaskHash
        CurrentTaskTimestamp = $currentTaskTimestamp
        CurrentMachineName = $machineName
        CurrentProjectPath = $projectPathValue
        CurrentProjectName = $projectNameValue
        CurrentBranch = if ($null -ne $GitSummary) { [string]$GitSummary.Branch } else { "" }
        CurrentHead = if ($null -ne $GitSummary) { [string]$GitSummary.Head } else { "" }
        CurrentStatusSummary = if ($null -ne $GitSummary) { [string]$GitSummary.StatusSummary } else { "" }
        RuntimeVersion = $runtimeVersion
        DeployVersion = $deployVersion
    }
}

function Show-ProjectResumeSummary {
    param(
        [object]$Project,
        [object]$GitSummary,
        [object]$TaskDigest,
        [object]$ResumeState,
        [object]$Validation,
        [object]$SnapshotInfo
    )

    $projectLabel = Get-Label -Project $Project
    $lastSession = if ($null -ne $ResumeState -and -not [string]::IsNullOrWhiteSpace([string]$ResumeState.codex_session_id)) { [string]$ResumeState.codex_session_id } else { "none" }
    $branch = if ($null -ne $GitSummary) { [string]$GitSummary.Branch } else { "unknown" }
    $statusSummary = if ($null -ne $GitSummary) { [string]$GitSummary.StatusSummary } else { "unknown" }
    $runtimeText = "unknown"
    if ($null -ne $SnapshotInfo) {
        $runtimeVersion = ""
        $deployVersion = 0
        if ($SnapshotInfo.PSObject.Properties["apps_script_version"]) { $runtimeVersion = [string]$SnapshotInfo.apps_script_version }
        if ($SnapshotInfo.PSObject.Properties["apps_script_deploy_version_number"]) { $deployVersion = [int]$SnapshotInfo.apps_script_deploy_version_number }
        if ([string]::IsNullOrWhiteSpace($runtimeVersion) -and $SnapshotInfo.PSObject.Properties["version"]) { $runtimeVersion = [string]$SnapshotInfo.version }
        if ($deployVersion -le 0 -and $SnapshotInfo.PSObject.Properties["deployVersion"]) { $deployVersion = [int]$SnapshotInfo.deployVersion }
        if (-not [string]::IsNullOrWhiteSpace($runtimeVersion) -or $deployVersion -gt 0) {
            $runtimeText = "{0} / {1}" -f $(if ([string]::IsNullOrWhiteSpace($runtimeVersion)) { "-" } else { $runtimeVersion }), $(if ($deployVersion -gt 0) { $deployVersion } else { "-" })
        }
    }

    Write-Host ""
    Write-Host "Resume Summary" -ForegroundColor Cyan
    Write-Host ("Project: {0}" -f $projectLabel)
    Write-Host ("Last session: {0}" -f $lastSession)
    Write-Host ("Branch: {0}" -f $branch)
    Write-Host ("Git status: {0}" -f $statusSummary)
    Write-Host ("CURRENT_TASK.md: {0}" -f $(if ($null -ne $TaskDigest -and $TaskDigest.Exists) { $TaskDigest.Timestamp } else { "missing" }))
    Write-Host ("Last runtime/version: {0}" -f $runtimeText)
    Write-Host ("Drift state: {0}" -f $Validation.State) -ForegroundColor $(if ($Validation.State -eq "CLEAN") { "Green" } elseif ($Validation.State -eq "WARNING") { "Yellow" } else { "Red" })
    Write-Host ("Recommended next launch mode: {0}" -f $Validation.RecommendedMode)
    if ($Validation.CrossMachine) {
        Write-Host "CROSS-MACHINE RESUME" -ForegroundColor Yellow
    }
    if ($Validation.Reasons.Count -gt 0) {
        Write-Host ("Notes: {0}" -f ($Validation.Reasons -join " | "))
    }
    Write-Host ""
}

function Get-ProjectFreshLaunchBootstrap {
    param(
        [object]$Project,
        [string]$ProjectPath,
        [string]$PromptPath,
        [object]$LaunchContext
    )

    $projectNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.name
    $displayNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value (Get-Label -Project $Project)
    $projectPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $ProjectPath
    $contextLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $Project.startup_context
    $promptPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $PromptPath
    $modeLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $LaunchContext.OperationalMode

    return @"
`$projectName = $projectNameLiteral
`$displayName = $displayNameLiteral
`$projectPath = $projectPathLiteral
`$startupContext = $contextLiteral
`$promptPath = $promptPathLiteral
`$operationalMode = $modeLiteral

Set-Location -LiteralPath `$projectPath

function Get-CurrentTaskSummary {
    param([string]`$TaskPath, [string]`$Mode)

    if (-not (Test-Path -LiteralPath `$TaskPath)) {
        return @('CURRENT_TASK.md missing.')
    }

    `$lines = @(Get-Content -LiteralPath `$TaskPath -Encoding utf8)
    if (`$Mode -eq 'FULL_AUDIT') {
        return `$lines
    }

    `$sections = [ordered]@{
        'Current Runtime' = @()
        'Active Blockers' = @()
        'Next Action' = @()
        'Latest Accepted Release' = @()
    }
    `$activeSection = ''
    foreach (`$line in `$lines) {
        if (`$line -match '^\s*#{1,6}\s+(.+?)\s*$') {
            `$candidate = `$Matches[1].Trim()
            if (`$sections.Contains(`$candidate)) {
                `$activeSection = `$candidate
            } else {
                `$activeSection = ''
            }
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace(`$activeSection) -and -not [string]::IsNullOrWhiteSpace(`$line)) {
            `$sections[`$activeSection] += `$line
        }
    }

    `$summary = New-Object System.Collections.Generic.List[string]
    foreach (`$heading in `$sections.Keys) {
        `$summary.Add("## `$heading") | Out-Null
        if (`$sections[`$heading].Count -gt 0) {
            foreach (`$entry in `$sections[`$heading]) {
                `$summary.Add([string]`$entry) | Out-Null
            }
        } else {
            `$summary.Add('Not stated.') | Out-Null
        }
        `$summary.Add('') | Out-Null
    }

    return @(`$summary)
}

Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host " `$displayName" -ForegroundColor Cyan
Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host "MODE: `$operationalMode" -ForegroundColor Cyan
Write-Host "AUTH ROOT: $($LaunchContext.CodexSyncRoot)" -ForegroundColor Cyan
Write-Host "Token discipline active: $(if ($operationalMode -eq 'LIGHT') { 'YES' } else { 'NO - FULL AUDIT' })" -ForegroundColor DarkCyan
Write-Host "CodexHub root: $($LaunchContext.CodexHubRoot)" -ForegroundColor DarkCyan
Write-Host "Codex_Sync root: $($LaunchContext.CodexSyncRoot)" -ForegroundColor DarkCyan
Write-Host "Selected project: $($LaunchContext.SelectedProject)" -ForegroundColor DarkCyan
Write-Host "Selected project path: `$projectPath" -ForegroundColor DarkCyan
Write-Host "CURRENT_TASK path: $($LaunchContext.CurrentTaskPath)" -ForegroundColor DarkCyan
Write-Host "Path source: $($LaunchContext.PathSource)" -ForegroundColor DarkCyan
Write-Host "Context: `$startupContext" -ForegroundColor Gray
Write-Host ''
Write-Host "Read policy: $(if ($operationalMode -eq 'FULL_AUDIT') { 'full project context allowed' } else { 'CURRENT_TASK.md, AGENTS.md, changed files, and explicitly requested files only' })" -ForegroundColor DarkCyan
Write-Host "Search policy: $(if ($operationalMode -eq 'FULL_AUDIT') { 'broad audits allowed' } else { 'no repo-wide scans, recursive searches, or historical scans by default' })" -ForegroundColor DarkCyan
Write-Host "Reading CURRENT_TASK from: $($LaunchContext.CurrentTaskPath)" -ForegroundColor Cyan
Write-Host ''

Write-Host 'CURRENT_TASK.md' -ForegroundColor Magenta
Write-Host ('-' * 'CURRENT_TASK.md'.Length) -ForegroundColor DarkMagenta
Get-CurrentTaskSummary -TaskPath '$($LaunchContext.CurrentTaskPath)' -Mode `$operationalMode
Write-Host ''

`$agentsPath = Join-Path -Path `$projectPath -ChildPath 'AGENTS.md'
Write-Host 'AGENTS.md' -ForegroundColor Magenta
Write-Host ('-' * 'AGENTS.md'.Length) -ForegroundColor DarkMagenta
if (Test-Path -LiteralPath `$agentsPath) {
    if (`$operationalMode -eq 'FULL_AUDIT') {
        Get-Content -LiteralPath `$agentsPath -Encoding utf8
    } else {
        Get-Content -LiteralPath `$agentsPath -Encoding utf8 | Select-Object -First 40
    }
} else {
    Write-Host 'missing' -ForegroundColor Yellow
}
Write-Host ''

if (Test-Path -LiteralPath '.\.git') {
    `$gitBranch = (git rev-parse --abbrev-ref HEAD 2>`$null)
    if (`$LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(`$gitBranch)) { `$gitBranch = 'unknown' }
    `$gitHash = (git rev-parse --short HEAD 2>`$null)
    if (`$LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(`$gitHash)) { `$gitHash = '' }
    `$gitStatus = (git status -sb 2>`$null)
    if (`$LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(`$gitStatus)) { `$gitStatus = 'git status failed.' }
    Write-Host ("Git branch/hash: {0} {1}" -f `$gitBranch, `$gitHash) -ForegroundColor Magenta
    Write-Host ("Git status: {0}" -f `$gitStatus) -ForegroundColor DarkMagenta
    Write-Host ''
}

if (Get-Command codex -ErrorAction SilentlyContinue) {
    if (Test-Path -LiteralPath `$promptPath) {
        `$initialPrompt = Get-Content -LiteralPath `$promptPath -Raw -Encoding utf8
        `$modeRules = if (`$operationalMode -eq 'FULL_AUDIT') {
@'
Operational mode: FULL_AUDIT
- Broad repo scans, historical governance parsing, drift analysis, and release-history inspection are allowed when needed.
- Keep output concise, but audit depth is allowed.
'@
        } else {
@'
Operational mode: LIGHT
- Read only CURRENT_TASK.md, AGENTS.md, changed files, and explicitly requested files unless the user asks for more.
- Do not start repo-wide scans, recursive searches, historical release scans, or broad audits by default.
- Do not repeat governance recap or resolved runtime truth unless it changes.
- Use concise operational summaries, command-style output, and delta summaries.
- For CURRENT_TASK.md, prioritize current runtime, active blockers, next action, and latest accepted release; ignore archived sections unless requested.
'@
        }
        `$initialPrompt = (`$modeRules.Trim() + "`r`n`r`n" + `$initialPrompt.Trim())
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
}

function Get-ProjectResumeLaunchBootstrap {
    param(
        [object]$Project,
        [string]$ProjectPath,
        [string]$PromptPath,
        [object]$LaunchContext,
        [string]$ResumeSessionId
    )

    $freshBootstrap = Get-ProjectFreshLaunchBootstrap -Project $Project -ProjectPath $ProjectPath -PromptPath $PromptPath -LaunchContext $LaunchContext
    $resumeSessionLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $ResumeSessionId

    return @"
`$projectPath = $(ConvertTo-SingleQuotedPowerShellLiteral -Value $ProjectPath)
Set-Location -LiteralPath `$projectPath

Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host " $(Get-Label -Project $Project)" -ForegroundColor Cyan
Write-Host '=================================' -ForegroundColor DarkCyan
Write-Host "Resume session: $ResumeSessionId" -ForegroundColor Cyan
Write-Host "CodexHub root: $($LaunchContext.CodexHubRoot)" -ForegroundColor DarkCyan
Write-Host "Codex_Sync root: $($LaunchContext.CodexSyncRoot)" -ForegroundColor DarkCyan
Write-Host "Selected project: $($LaunchContext.SelectedProject)" -ForegroundColor DarkCyan
Write-Host "Selected project path: `$projectPath" -ForegroundColor DarkCyan
Write-Host "CURRENT_TASK path: $($LaunchContext.CurrentTaskPath)" -ForegroundColor DarkCyan
Write-Host "Path source: $($LaunchContext.PathSource)" -ForegroundColor DarkCyan
Write-Host ''

if (Get-Command codex -ErrorAction SilentlyContinue) {
    & codex resume $resumeSessionLiteral
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'RESUME STATE DRIFT DETECTED' -ForegroundColor Yellow
        Write-Host 'Codex resume failed; falling back to fresh reconstruction.' -ForegroundColor Yellow
$freshBootstrap
    }
} else {
    Write-Host 'codex CLI not found in PATH. Falling back to fresh reconstruction.' -ForegroundColor Yellow
$freshBootstrap
}
"@
}

function Start-ProjectLaunch {
    param(
        [object]$Project,
        [string]$ProjectPath,
        [object]$LaunchContext,
        [string]$LaunchMode,
        [object]$Validation,
        [object]$TaskDigest,
        [object]$SnapshotInfo,
        [object]$ResumeState
    )

    $promptPath = Get-PromptPath -ProjectName $Project.name
    $bootstrap = $null
    if ($LaunchMode -eq "resume" -and $Validation.State -eq "CLEAN" -and $Validation.ResumeAvailable) {
        $bootstrap = Get-ProjectResumeLaunchBootstrap -Project $Project -ProjectPath $ProjectPath -PromptPath $promptPath -LaunchContext $LaunchContext -ResumeSessionId $Validation.SavedSessionId
    } else {
        if ($LaunchMode -eq "resume" -and $Validation.State -ne "CLEAN") {
            Write-Host "RESUME STATE DRIFT DETECTED" -ForegroundColor Yellow
            Write-Host ("Drift state: {0}" -f $Validation.State) -ForegroundColor Yellow
            if ($Validation.Reasons.Count -gt 0) {
                Write-Host ("Reasons: {0}" -f ($Validation.Reasons -join " | ")) -ForegroundColor Yellow
            }
        }
        $bootstrap = Get-ProjectFreshLaunchBootstrap -Project $Project -ProjectPath $ProjectPath -PromptPath $promptPath -LaunchContext $LaunchContext
    }

    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", $bootstrap
    ) | Out-Null
}

function Read-ProjectLaunchMode {
    param([object]$Validation)

    Write-Host "Launch mode: [A]uto (recommended)  [R]esume prior Codex session  [F]Fresh reconstruction"
    $answer = Read-ConsoleInput "Select launch mode"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return "auto"
    }

    switch -Regex ($answer.Trim()) {
        '^[Rr]$' { return "resume" }
        '^[Ff]$' { return "fresh" }
        default { return "auto" }
    }
}

$script:CodexHubOperationalMode = Resolve-OperationalMode -RequestedMode $OperationalMode
$script:CodexHubModeSettings = Get-OperationalModeSettings -Mode $script:CodexHubOperationalMode
Initialize-AuthorityState

function Get-LastHandoffInfo {
    param(
        [string]$ProjectPath,
        [string]$ProjectName = ""
    )

    if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not (Test-Path -LiteralPath $ProjectPath)) {
        return [pscustomobject]@{ Text = "none"; Hours = 999999 }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $safeProjectName = ($ProjectName -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
        $stateSnapshot = Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_snapshot.json" -f $safeProjectName)
        if (Test-Path -LiteralPath $stateSnapshot) {
            $age = (Get-Date) - (Get-Item -LiteralPath $stateSnapshot).LastWriteTime
            $text = if ($age.TotalHours -lt 1) {
                "{0}m ago" -f [Math]::Max(1, [int]$age.TotalMinutes)
            } elseif ($age.TotalHours -lt 48) {
                "{0}h ago" -f [int]$age.TotalHours
            } else {
                "{0}d ago" -f [int]$age.TotalDays
            }

            return [pscustomobject]@{ Text = $text; Hours = $age.TotalHours }
        }
    }

    $snapshotDir = Join-Path -Path $ProjectPath -ChildPath "SNAPSHOT"
    if (-not (Test-Path -LiteralPath $snapshotDir)) {
        return [pscustomobject]@{ Text = "none"; Hours = 999999 }
    }

    $latest = Get-ChildItem -LiteralPath $snapshotDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        return [pscustomobject]@{ Text = "none"; Hours = 999999 }
    }

    $age = (Get-Date) - $latest.LastWriteTime
    $text = if ($age.TotalHours -lt 1) {
        "{0}m ago" -f [Math]::Max(1, [int]$age.TotalMinutes)
    } elseif ($age.TotalHours -lt 48) {
        "{0}h ago" -f [int]$age.TotalHours
    } else {
        "{0}d ago" -f [int]$age.TotalDays
    }

    return [pscustomobject]@{ Text = $text; Hours = $age.TotalHours }
}

function Get-ProjectHealth {
    param(
        [object]$Project,
        [object]$PathInfo,
        [object]$GitSummary,
        [object]$HandoffInfo
    )

    if ($null -eq $PathInfo -or [string]::IsNullOrWhiteSpace($PathInfo.Path) -or -not (Test-Path -LiteralPath $PathInfo.Path)) {
        return "AMBER"
    }

    if ($null -eq $GitSummary -or [string]::Equals([string]$GitSummary.State, "NO-GIT", [System.StringComparison]::OrdinalIgnoreCase) -or $GitSummary.Detached) {
        return "AMBER"
    }

    if (-not (Test-Path -LiteralPath (Join-Path -Path $PathInfo.Path -ChildPath "CURRENT_TASK.md"))) {
        return "AMBER"
    }

    return "GREEN"
}

function ConvertTo-ProjectFolderName {
    param([string]$ProjectName)

    $name = ($ProjectName -replace '[^A-Za-z0-9]+', '_').Trim('_').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Project name did not produce a deterministic folder name."
    }

    return $name
}

function Expand-TemplateText {
    param(
        [string]$Text,
        [string]$ProjectName,
        [string]$ProjectPath
    )

    return $Text.Replace("{{PROJECT_NAME}}", $ProjectName).
        Replace("{{PROJECT_PATH}}", $ProjectPath).
        Replace("{{CURRENT_OBJECTIVE}}", "Define the first concrete objective.").
        Replace("{{DATE}}", (Get-Date -Format "yyyy-MM-dd"))
}

function Copy-GovernanceTemplate {
    param(
        [string]$TemplateName,
        [string]$TargetName,
        [string]$ProjectName,
        [string]$ProjectPath
    )

    throw "Project governance writes are disabled until a separate U command exists."
}

function Get-ProjectStatusFromTool {
    param(
        [string]$ProjectPath,
        [string]$ProjectName
    )

    $toolPath = Join-Path -Path (Get-ToolsRoot) -ChildPath "project-status.ps1"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Project status tool not found: $toolPath"
    }

    $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath `
        -ProjectPath $ProjectPath `
        -ProjectName $ProjectName `
        -StateRoot (Get-StateRoot) `
        -AsJson
    if ($LASTEXITCODE -ne 0) {
        throw "Project status tool failed for $ProjectPath"
    }

    return (($json -join "`n") | ConvertFrom-Json -ErrorAction Stop)
}

function Get-ProjectSnapshotPath {
    param([string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return ""
    }

    $safeProjectName = ($ProjectName -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeProjectName)) {
        $safeProjectName = "PROJECT"
    }

    return Join-Path -Path (Get-StateRoot) -ChildPath ("{0}_snapshot.json" -f $safeProjectName)
}

function Get-ProjectSnapshotInfo {
    param([string]$ProjectName)

    $snapshotPath = Get-ProjectSnapshotPath -ProjectName $ProjectName
    if ([string]::IsNullOrWhiteSpace($snapshotPath) -or -not (Test-Path -LiteralPath $snapshotPath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $snapshotPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Get-ResumeReadiness {
    param([object]$Status)

    if ($null -eq $Status) {
        return "BLOCKED"
    }

    if (
        -not $Status.path_exists -or
        -not $Status.governance.current_task_present -or
        [string]::Equals([string]$Status.severity, "RED", [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return "BLOCKED"
    }

    return "READY"
}

function Show-HandoffReport {
    param(
        [object]$Project,
        [object]$Status,
        [object]$SnapshotInfo,
        [object]$ResumeState,
        [object]$Validation
    )

    $projectLabel = Get-Label -Project $Project
    $machineName = if ($null -ne $SnapshotInfo -and $SnapshotInfo.PSObject.Properties["machine"]) { [string]$SnapshotInfo.machine } else { $env:COMPUTERNAME }
    $pathValue = if ($null -ne $Status) { [string]$Status.project_path } else { Resolve-ProjectPath -Project $Project }
    $gitStatusSummary = if ($null -ne $Status) { ([string]$Status.git.status_sb -replace "`r?`n", " | ") } else { "Not available." }
    $taskCheck = if ($null -ne $Status -and $Status.governance.current_task_present) {
        if ([string]::IsNullOrWhiteSpace([string]$Status.governance.next_exact_step)) {
            "Checked only; CURRENT_TASK.md present; next exact step not detected; no update performed."
        } else {
            "Checked only; CURRENT_TASK.md present; next exact step detected; no update performed."
        }
    } else {
        "Checked only; CURRENT_TASK.md missing; no update performed."
    }
    $handoffLocation = if ($null -ne $SnapshotInfo -and $SnapshotInfo.PSObject.Properties["handoff_path"] -and -not [string]::IsNullOrWhiteSpace([string]$SnapshotInfo.handoff_path)) {
        [string]$SnapshotInfo.handoff_path
    } else {
        "Not created."
    }
    $snapshotLocation = if ($null -ne $SnapshotInfo) {
        Get-ProjectSnapshotPath -ProjectName $Project.name
    } else {
        "Not created."
    }
    $resumeCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f (Join-Path -Path (Get-Root) -ChildPath "RUN.ps1")
    $lastCompletedAction = if ($null -ne $Status -and -not [string]::IsNullOrWhiteSpace([string]$Status.git.latest_commit)) {
        [string]$Status.git.latest_commit
    } else {
        "Not detected."
    }
    $pendingNextAction = if ($null -ne $Status -and -not [string]::IsNullOrWhiteSpace([string]$Status.governance.next_exact_step)) {
        [string]$Status.governance.next_exact_step
    } else {
        "Not detected."
    }
    $savedSessionId = if ($null -ne $ResumeState -and -not [string]::IsNullOrWhiteSpace([string]$ResumeState.codex_session_id)) { [string]$ResumeState.codex_session_id } else { "not saved" }
    $driftState = if ($null -ne $Validation) { [string]$Validation.State } else { "unknown" }
    $launchMode = if ($null -ne $Validation) { [string]$Validation.RecommendedMode } else { "reconstruct" }
    $notes = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Status) {
        if (-not $Status.path_exists) {
            $notes.Add("Project path is missing.") | Out-Null
        }
        if (-not $Status.governance.current_task_present) {
            $notes.Add("CURRENT_TASK.md missing.") | Out-Null
        }
        if ($Status.git.dirty) {
            $notes.Add("Working tree is dirty.") | Out-Null
        }
        if ($null -ne $Status.apps_script -and $Status.apps_script.applicable -and $Status.apps_script.warnings.Count -gt 0) {
            $notes.Add(($Status.apps_script.warnings -join "; ")) | Out-Null
        }
    }
    if ($null -eq $SnapshotInfo) {
        $notes.Add("Snapshot metadata could not be reloaded after handoff.") | Out-Null
    }
    if ($notes.Count -eq 0) {
        $notes.Add("No blocking shutdown issues detected.") | Out-Null
    }

    Write-Host ""
    Write-Host "Shutdown Report" -ForegroundColor Cyan
    Write-Host ("Project: {0}" -f $projectLabel) -ForegroundColor White
    Write-Host ("Machine: {0}" -f $machineName)
    Write-Host ("Path: {0}" -f $pathValue)
    Write-Host ("Git status: {0}" -f $gitStatusSummary)
    Write-Host ("CURRENT_TASK.md check: {0}" -f $taskCheck)
    Write-Host ("Handoff file: {0}" -f $handoffLocation) -ForegroundColor Cyan
    Write-Host ("Snapshot/checklist: {0}" -f $snapshotLocation) -ForegroundColor DarkCyan
    Write-Host ("Codex session ID saved: {0}" -f $savedSessionId)
    Write-Host ("Drift state: {0}" -f $driftState)
    Write-Host ("Recommended next launch mode: {0}" -f $launchMode)
    Write-Host ("Next recommended resume command: {0}" -f $resumeCommand) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "Resume Block" -ForegroundColor Cyan
    Write-Host ("Project: {0}" -f $projectLabel)
    Write-Host ("Machine: {0}" -f $machineName)
    Write-Host ("Path: {0}" -f $pathValue)
    Write-Host ("Git status: {0}" -f $gitStatusSummary)
    Write-Host ("Last completed action: {0}" -f $lastCompletedAction)
    Write-Host ("Pending next action: {0}" -f $pendingNextAction)
    Write-Host ("Resume readiness: {0}" -f $(if ($null -ne $Validation) { $Validation.State } else { (Get-ResumeReadiness -Status $Status) })) -ForegroundColor Cyan
    Write-Host ("Notes: {0}" -f ($notes -join " | "))
    Write-Host ""
}

function Confirm-GovernanceWrite {
    param(
        [string]$ProjectPath,
        [string]$ProjectName,
        [string[]]$TargetFiles
    )

    $status = Get-ProjectStatusFromTool -ProjectPath $ProjectPath -ProjectName $ProjectName
    Write-Host ""
    Write-Host "Auto-status before project governance write" -ForegroundColor Cyan
    Write-Host ("Project path: {0}" -f $status.project_path)
    Write-Host ("Git status: {0}" -f ($status.git.status_sb -replace "`r?`n", " | "))
    Write-Host ("Latest commit: {0}" -f $status.git.latest_commit)
    Write-Host ("Detected current objective: {0}" -f $(if ($status.governance.current_objective) { $status.governance.current_objective } else { "Not detected." }))
    Write-Host ("Detected next exact step: {0}" -f $(if ($status.governance.next_exact_step) { $status.governance.next_exact_step } else { "Not detected." }))
    Write-Host "Files that would be modified:" -ForegroundColor Yellow
    foreach ($target in $TargetFiles) {
        Write-Host ("- {0}" -f $target) -ForegroundColor Yellow
    }

    $updatesCurrentTask = @($TargetFiles | Where-Object { [string]::Equals((Split-Path -Path $_ -Leaf), "CURRENT_TASK.md", [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    $prompt = if ($updatesCurrentTask) { "Proceed with updating CURRENT_TASK.md? Y/N" } else { "Proceed with this write action? Y/N" }
    $answer = Read-ConsoleInput $prompt
    return ($answer -match '^[Yy]$')
}

function New-CodexHubProject {
    Write-Host "New Project is disabled in this CIS because no separate U command exists." -ForegroundColor Yellow
    Write-Host "No project files were modified." -ForegroundColor Yellow
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

    Write-Host "Initialize CODEX LITE OPS files is disabled in this CIS because no separate U command exists." -ForegroundColor Yellow
    Write-Host "No project files were modified." -ForegroundColor Yellow
}

function Show-Header {
    $reg = @(Load-Reg)
    $active = @(Get-ProjectsByStatus -Projects $reg -Status @("active")).Count
    $deprecated = @(Get-ProjectsByStatus -Projects $reg -Status @("deprecated")).Count
    $archived = @(Get-ProjectsByStatus -Projects $reg -Status @("archived")).Count
    $last = Get-LastProjectName
    $recent = @(Load-RecentProjects)
    $syncRoot = Get-ActiveProjectRoot
    $hubRoot = Get-Root

    Clear-Host
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host "               CODEX HUB LAUNCHER            " -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor DarkCyan
    Write-Host (" MODE: {0}" -f $script:CodexHubModeSettings.Mode) -ForegroundColor Cyan
    Write-Host (" AUTH ROOT: {0}" -f $syncRoot) -ForegroundColor Cyan
    Write-Host (" Token discipline: {0}" -f $(if ($script:CodexHubModeSettings.TokenDisciplineActive) { "ACTIVE" } else { "FULL AUDIT" })) -ForegroundColor DarkCyan
    Write-Host (" Active: {0}   Deprecated: {1}   Archived: {2}" -f $active, $deprecated, $archived) -ForegroundColor Gray
    Write-Host (" CodexHub root: {0}" -f $hubRoot) -ForegroundColor DarkCyan
    Write-Host (" Codex_Sync root: {0}" -f $syncRoot) -ForegroundColor DarkCyan
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
    if (-not $launchContext.Ready) {
        Write-Host ""
        Write-Host "Project launch blocked." -ForegroundColor Yellow
        Write-Host ("Selected project path: {0}" -f $projectPath) -ForegroundColor Yellow
        Write-Host ("CURRENT_TASK path: {0}" -f $launchContext.CurrentTaskPath) -ForegroundColor Yellow
        Write-Host ("Path source: {0}" -f $launchContext.PathSource) -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($launchContext.FailureReason)) {
            Write-Host ("Reason: {0}" -f $launchContext.FailureReason) -ForegroundColor Yellow
        }
        return
    }

    Set-LastProjectName -Name $Project.name
    Add-RecentProject -Project $Project

    $taskDigest = Get-ProjectCurrentTaskDigest -ProjectPath $projectPath
    $gitSummary = Get-ProjectGitSummary -ProjectPath $projectPath
    $snapshotInfo = Get-ProjectSnapshotInfo -ProjectName $Project.name
    $resumeState = Load-ProjectResumeState -ProjectName $Project.name -Project $Project
    $validation = Get-ProjectResumeValidation -Project $Project -GitSummary $gitSummary -TaskDigest $taskDigest -ResumeState $resumeState -SnapshotInfo $snapshotInfo

    Show-ProjectResumeSummary -Project $Project -GitSummary $gitSummary -TaskDigest $taskDigest -ResumeState $resumeState -Validation $validation -SnapshotInfo $snapshotInfo

    $launchMode = Read-ProjectLaunchMode -Validation $validation
    if ($launchMode -eq "auto") {
        if ($validation.State -eq "CLEAN") {
            $launchMode = "resume"
        } else {
            $launchMode = "fresh"
        }
    }

    if ($launchMode -eq "resume" -and $validation.State -ne "CLEAN") {
        Write-Host "RESUME STATE DRIFT DETECTED" -ForegroundColor Yellow
        if ($validation.Reasons.Count -gt 0) {
            Write-Host ("Reasons: {0}" -f ($validation.Reasons -join " | ")) -ForegroundColor Yellow
        }
        $launchMode = "fresh"
    }

    Start-ProjectLaunch -Project $Project -ProjectPath $projectPath -LaunchContext $launchContext -LaunchMode $launchMode -Validation $validation -TaskDigest $taskDigest -SnapshotInfo $snapshotInfo -ResumeState $resumeState
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
        if (-not [string]::IsNullOrWhiteSpace($pathInfo.Reason)) {
            Write-Host ("Reason: {0}" -f $pathInfo.Reason) -ForegroundColor Yellow
        }
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
        Write-Host ("    CURRENT_TASK: {0}" -f $pathInfo.TaskPath) -ForegroundColor DarkGray
        if (-not [string]::IsNullOrWhiteSpace($pathInfo.Reason)) {
            Write-Host ("    warning: {0}" -f $pathInfo.Reason) -ForegroundColor Yellow
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

    $pathInfo = Resolve-ProjectPathInfo -Project $Project
    $projectPath = $pathInfo.Path
    $taskPath = $pathInfo.TaskPath
    if (-not $pathInfo.TaskExists) {
        Write-Host "CURRENT_TASK.md not found for $($Project.name)." -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($taskPath)) {
            Write-Host ("Expected CURRENT_TASK path: {0}" -f $taskPath) -ForegroundColor Yellow
        }
        return
    }

    Write-Host ("Opening CURRENT_TASK: {0}" -f $taskPath) -ForegroundColor Cyan
    $taskPathLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value $taskPath
    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", "Get-Content -LiteralPath $taskPathLiteral -Encoding utf8"
    ) | Out-Null
}

function Open-HubPrompt {
    param([string]$FileName)

    $path = Get-HubPromptPath -FileName $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Prompt not found: $path" -ForegroundColor Yellow
        return
    }

    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", "Get-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral -Value $path) -Encoding utf8"
    ) | Out-Null
}

function Invoke-DriftAudit {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = Resolve-ProjectPath -Project $Project
    $toolPath = Join-Path -Path (Get-ToolsRoot) -ChildPath "drift-audit.ps1"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        Write-Host "Drift audit tool not found: $toolPath" -ForegroundColor Yellow
        return
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath `
        -ProjectPath $projectPath `
        -ProjectName $Project.name `
        -RegistryPath (Get-RegPath) `
        -MachineProfilePath (Get-MachineProfilePath)

    [void](Read-ConsoleInput "Press Enter to return to menu...")
}

function Invoke-Handoff {
    param([object]$Project)

    if ($null -eq $Project) {
        return
    }

    $projectPath = Resolve-ProjectPath -Project $Project
    $toolPath = Join-Path -Path (Get-ToolsRoot) -ChildPath "handoff.ps1"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        Write-Host "Handoff tool not found: $toolPath" -ForegroundColor Yellow
        return $false
    }

    $operatorNote = Read-ConsoleInput "Add one optional operator note? Leave blank to skip"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath `
        -ProjectPath $projectPath `
        -ProjectName $Project.name `
        -StateRoot (Get-StateRoot) `
        -OperatorNote $operatorNote `
        -SkipPause

    $shouldExit = ($LASTEXITCODE -eq 10)
    $status = Get-ProjectStatusFromTool -ProjectPath $projectPath -ProjectName $Project.name
    $snapshotInfo = Get-ProjectSnapshotInfo -ProjectName $Project.name
    $taskDigest = Get-ProjectCurrentTaskDigest -ProjectPath $projectPath
    $gitSummary = Get-ProjectGitSummary -ProjectPath $projectPath
    $resumeState = Load-ProjectResumeState -ProjectName $Project.name -Project $Project
    $validation = Get-ProjectResumeValidation -Project $Project -GitSummary $gitSummary -TaskDigest $taskDigest -ResumeState $resumeState -SnapshotInfo $snapshotInfo
    $codexSessionId = Get-CodexSessionId
    $savedState = [pscustomobject]@{
        project = $Project.name
        repo_path = $projectPath
        codex_session_id = $codexSessionId
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        branch = [string]$gitSummary.Branch
        git_head = [string]$gitSummary.Head
        git_status_summary = [string]$gitSummary.StatusSummary
        current_task_hash = [string]$taskDigest.Hash
        current_task_timestamp = [string]$taskDigest.Timestamp
        machine_name = [string]$env:COMPUTERNAME
        last_shutdown_status = $(if ($shouldExit) { "EXIT" } else { "RETURN" })
        drift_state = [string]$validation.State
        resume_readiness = [string]$validation.State
        recommended_next_launch_mode = [string]$validation.RecommendedMode
        runtime_version = [string]$validation.RuntimeVersion
        deploy_version_number = [int]$validation.DeployVersion
        codex_resume_command = [string]$validation.ResumeCommand
    }
    if ($validation.State -eq "BLOCKED" -and ($validation.Reasons -contains "ROOT AUTHORITY CONFLICT")) {
        Write-Host "ROOT AUTHORITY CONFLICT" -ForegroundColor Red
        Write-Host "Metadata persistence refused until only one valid root remains for this repo." -ForegroundColor Yellow
    } else {
        Save-ProjectResumeState -State $savedState -ProjectName $Project.name | Out-Null
    }
    $resumeState = Load-ProjectResumeState -ProjectName $Project.name -Project $Project
    Show-HandoffReport -Project $Project -Status $status -SnapshotInfo $snapshotInfo -ResumeState $resumeState -Validation $validation

    if (-not $shouldExit) {
        $exitAnswer = Read-ConsoleInput "Exit CodexHub now? Y/N"
        if ($exitAnswer -match '^[Yy]$') {
            $shouldExit = $true
        } else {
            [void](Read-ConsoleInput "Press Enter to return to CodexHub menu")
        }
    }

    return $shouldExit
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
        return $false
    }

    Write-Host "Project SNAPSHOT handoff is replaced by hub Auto-Handoff under state\\handoffs." -ForegroundColor Yellow
    return (Invoke-Handoff -Project $Project)
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
        $gitSummary = Get-ProjectGitSummary -ProjectPath $resolvedPath
        $handoffInfo = Get-LastHandoffInfo -ProjectPath $resolvedPath -ProjectName $project.name
        $health = Get-ProjectHealth -Project $project -PathInfo $pathInfo -GitSummary $gitSummary -HandoffInfo $handoffInfo
        Write-Host ("{0,2}. {1}" -f $menuNumber, (Get-Label -Project $project)) -ForegroundColor White
        Write-Host ("    {0}" -f $resolvedPath) -ForegroundColor DarkGray
        Write-Host ("    CURRENT_TASK: {0}" -f $pathInfo.TaskPath) -ForegroundColor DarkGray
        Write-Host ("    Branch: {0}; Hash: {1}; State: {2}; Last handoff: {3}; Health: {4}" -f $gitSummary.Branch, $gitSummary.Head, $gitSummary.State, $handoffInfo.Text, $health) -ForegroundColor DarkCyan
        Write-Host ("    status: {0}; source: {1}" -f $repoStatus, $pathInfo.Source) -ForegroundColor DarkGray
        if (-not [string]::IsNullOrWhiteSpace($pathInfo.Reason)) {
            Write-Host ("    warning: {0}" -f $pathInfo.Reason) -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "A. Audit current project" -ForegroundColor Cyan
    Write-Host "D. Drift Audit" -ForegroundColor Cyan
    Write-Host "H. Auto-Handoff / Shutdown" -ForegroundColor Cyan
    Write-Host "N. New Project" -ForegroundColor Cyan
    Write-Host "R. Resume last project" -ForegroundColor Cyan
    Write-Host "J. Open from recent projects" -ForegroundColor Cyan
    Write-Host "T. Quick-open CURRENT_TASK.md" -ForegroundColor Cyan
    Write-Host "S. Create hub auto-handoff snapshot" -ForegroundColor DarkCyan
    Write-Host "X. Open in Codex App" -ForegroundColor Cyan
    Write-Host "C. Open command library" -ForegroundColor Cyan
    Write-Host "B. Open new project bootstrap prompt" -ForegroundColor DarkCyan
    Write-Host "P. Open project shutdown check prompt" -ForegroundColor DarkCyan
    Write-Host "O. Open CODEX root" -ForegroundColor Cyan
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
            $project = Pick-Project -Projects $activeProjects -Title "Create Hub Auto-Handoff Snapshot"
            if ($null -ne $project) {
                if (New-SnapshotHandoff -Project $project) {
                    return
                }
            }
            continue
        }
        '^[Aa]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Audit Current Project"
            if ($null -ne $project) {
                Invoke-DriftAudit -Project $project
            }
            continue
        }
        '^[Dd]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Drift Audit"
            if ($null -ne $project) {
                Invoke-DriftAudit -Project $project
            }
            continue
        }
        '^[Hh]$' {
            $project = Pick-Project -Projects $activeProjects -Title "Auto-Handoff / Shutdown"
            if ($null -ne $project) {
                if (Invoke-Handoff -Project $project) {
                    return
                }
            }
            continue
        }
        '^[Nn]$' {
            New-CodexHubProject
            continue
        }
        '^[Xx]$' {
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
        '^[Bb]$' {
            Open-HubPrompt -FileName "NEW_PROJECT_BOOTSTRAP.txt"
            continue
        }
        '^[Pp]$' {
            Open-HubPrompt -FileName "PROJECT_SHUTDOWN_CHECK.txt"
            continue
        }
        '^[Oo]$' {
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


