param(
    [string]$ProjectPath = ".",
    [ValidateSet("LO", "MED", "HI")]
    [string]$Mode = "LO",
    [switch]$AsJson
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Error "PowerShell 7 is required. Install or launch pwsh before running CodexHub."
        exit 1
    }

    Write-Host "Windows PowerShell 5.1 detected. Re-launching CodexHub under PowerShell 7."
    $forwardArgs = @()
    if ($PSBoundParameters.ContainsKey("ProjectPath")) { $forwardArgs += @("-ProjectPath", $ProjectPath) }
    if ($PSBoundParameters.ContainsKey("Mode")) { $forwardArgs += @("-Mode", $Mode) }
    if ($AsJson) { $forwardArgs += "-AsJson" }
    $forwardArgs += $args
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forwardArgs
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-StringList {
    return New-Object System.Collections.Generic.List[string]
}

function New-ObjectList {
    return New-Object System.Collections.Generic.List[object]
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

function Add-SkippedCheck {
    param(
        [System.Collections.Generic.List[object]]$SkippedChecks,
        [string]$Check,
        [string]$Reason
    )
    $SkippedChecks.Add([pscustomobject]@{
        check = $Check
        reason = $Reason
    }) | Out-Null
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

function Get-ConfigInfo {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $configPath = Join-Path -Path $RepoRoot -ChildPath "Config.js"
    $exists = Test-Path -LiteralPath $configPath
    $version = ""
    $deployVersionNumber = ""

    if ($exists) {
        $content = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
        if ($content -match '(?m)\bVERSION\b\s*[:=]\s*["'']([^"'']+)["'']') {
            $version = $Matches[1]
        } else {
            Add-Warning -Warnings $Warnings -Message "Config.js VERSION not found."
        }

        if ($content -match '(?m)\bDEPLOY_VERSION_NUMBER\b\s*[:=]\s*([0-9]+)') {
            $deployVersionNumber = $Matches[1]
        } else {
            Add-Warning -Warnings $Warnings -Message "Config.js DEPLOY_VERSION_NUMBER not found."
        }
    } else {
        Add-Warning -Warnings $Warnings -Message "Config.js not found."
    }

    $expectedVersion = if (-not [string]::IsNullOrWhiteSpace($deployVersionNumber)) { "r$deployVersionNumber" } else { "" }
    $matchesExpected = $false
    if (-not [string]::IsNullOrWhiteSpace($version) -and -not [string]::IsNullOrWhiteSpace($expectedVersion)) {
        $matchesExpected = ($version -eq $expectedVersion)
    }

    [pscustomobject]@{
        path = $configPath
        exists = $exists
        version = $version
        deploy_version_number = $deployVersionNumber
        expected_version_from_deploy = $expectedVersion
        version_matches_expected = $matchesExpected
    }
}

function Get-CurrentTaskBaseline {
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
            version = ""
            deploy_version_number = ""
            lines = @()
        }
    }

    $lines = @(Get-Content -LiteralPath $taskPath -Encoding utf8)
    $version = ""
    $deployVersionNumber = ""
    $captured = New-StringList

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($version) -and $line -match '(?i)\bversion\b[^A-Za-z0-9]*[:= -]+\s*(r[0-9]+)\b') {
            $version = $Matches[1]
            $captured.Add($line.Trim()) | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($deployVersionNumber) -and $line -match '(?i)\bdeploy(?:ment)?(?:\s+version(?:\s+number)?)?\b[^0-9]{0,20}([0-9]+)\b') {
            $deployVersionNumber = $Matches[1]
            $captured.Add($line.Trim()) | Out-Null
        }
    }

    if ([string]::IsNullOrWhiteSpace($version) -and [string]::IsNullOrWhiteSpace($deployVersionNumber)) {
        Add-Warning -Warnings $Warnings -Message "CURRENT_TASK.md release baseline not found."
    }

    [pscustomobject]@{
        path = $taskPath
        exists = $true
        version = $version
        deploy_version_number = $deployVersionNumber
        lines = @($captured)
    }
}

function Get-StagingTags {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings,
        [System.Collections.Generic.List[object]]$SkippedChecks,
        [string]$Mode
    )

    $localResult = Invoke-GitRead -RepoRoot $RepoRoot -GitArgs @("tag", "--list", "--sort=-creatordate", "*staging*")
    $localTags = if ($localResult.code -eq 0) { @($localResult.output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }
    $localTagCount = @($localTags).Length
    if ($localResult.code -ne 0) {
        Add-Warning -Warnings $Warnings -Message "Unable to read local tags."
    } elseif ($localTagCount -eq 0) {
        Add-Warning -Warnings $Warnings -Message "No local staging tags found."
    }

    $remoteTag = ""
    $remoteOrigin = ""
    $remoteError = ""
    $remoteLookupAttempted = $false

    if ($Mode -eq "LO") {
        Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "remote_staging_tag" -Reason "LO mode is fully local; remote tag lookup disabled."
    } else {
        $remoteOriginResult = Invoke-GitRead -RepoRoot $RepoRoot -GitArgs @("remote", "get-url", "origin")
        $remoteOrigin = $remoteOriginResult.text
        $remoteConfigured = ($remoteOriginResult.code -eq 0 -and -not [string]::IsNullOrWhiteSpace($remoteOrigin))
        if ($remoteConfigured) {
            $remoteLookupAttempted = $true
            $remoteResult = Invoke-GitRead -RepoRoot $RepoRoot -GitArgs @("ls-remote", "--tags", "--sort=-version:refname", "origin", "*staging*")
            if ($remoteResult.code -eq 0) {
                $remoteTagLine = $remoteResult.output | Where-Object { $_ -match 'refs/tags/' } | Select-Object -First 1
                if ($remoteTagLine) {
                    $remoteTag = (($remoteTagLine -split 'refs/tags/', 2)[1] -replace '\^\{\}$', '').Trim()
                } else {
                    Add-Warning -Warnings $Warnings -Message "No remote staging tags found."
                }
            } else {
                $remoteError = if ([string]::IsNullOrWhiteSpace($remoteResult.text)) { "git ls-remote failed." } else { $remoteResult.text }
                Add-Warning -Warnings $Warnings -Message ("Remote staging tag lookup unavailable: {0}" -f $remoteError)
            }
        } else {
            Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "remote_staging_tag" -Reason "No git origin remote configured."
        }
    }

    [pscustomobject]@{
        local_latest = if ($localTagCount -gt 0) { [string]$localTags[0] } else { "" }
        remote_latest = $remoteTag
        remote_origin = $remoteOrigin
        remote_lookup_attempted = $remoteLookupAttempted
        remote_lookup_error = $remoteError
    }
}

function Get-ClaspInventory {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings,
        [System.Collections.Generic.List[object]]$SkippedChecks,
        [string]$Mode
    )

    $claspPath = Join-Path -Path $RepoRoot -ChildPath ".clasp.json"
    if (-not (Test-Path -LiteralPath $claspPath)) {
        Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "clasp_inventory" -Reason ".clasp.json not present."
        return [pscustomobject]@{
            path = $claspPath
            exists = $false
            script_id = ""
            root_dir = ""
            inventory_available = $false
        }
    }

    if ($Mode -eq "LO") {
        Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "clasp_inventory" -Reason "LO mode skips clasp inventory."
        return [pscustomobject]@{
            path = $claspPath
            exists = $true
            script_id = ""
            root_dir = ""
            inventory_available = $false
        }
    }

    try {
        $clasp = Get-Content -LiteralPath $claspPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            path = $claspPath
            exists = $true
            script_id = if ($clasp.PSObject.Properties["scriptId"]) { [string]$clasp.scriptId } else { "" }
            root_dir = if ($clasp.PSObject.Properties["rootDir"]) { [string]$clasp.rootDir } else { "" }
            inventory_available = $true
        }
    } catch {
        Add-Warning -Warnings $Warnings -Message ".clasp.json exists but could not be parsed."
        return [pscustomobject]@{
            path = $claspPath
            exists = $true
            script_id = ""
            root_dir = ""
            inventory_available = $false
        }
    }
}

function Get-LiveUrlCandidates {
    param([string]$RepoRoot)

    $candidates = @("LIVE_URLS.md", "CURRENT_TASK.md", "KNOWN_GOOD_STATE.md", "README.md", "Config.js")
    $adminUrl = ""
    $studentUrl = ""

    foreach ($relativePath in $candidates) {
        $fullPath = Join-Path -Path $RepoRoot -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }
        $text = Get-Content -LiteralPath $fullPath -Raw -Encoding utf8
        foreach ($line in ($text -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($adminUrl) -and $line -match '(?i)admin[^\r\n]*?(https://script\.google\.com/macros/s/[^\s`"''<>]+/exec(?:\?[^\s`"''<>]+)?)') {
                $adminUrl = $Matches[1]
            }
            if ([string]::IsNullOrWhiteSpace($studentUrl) -and $line -match '(?i)student[^\r\n]*?(https://script\.google\.com/macros/s/[^\s`"''<>]+/exec(?:\?[^\s`"''<>]+)?)') {
                $studentUrl = $Matches[1]
            }
        }
    }

    [pscustomobject]@{
        admin_url = $adminUrl
        student_url = $studentUrl
    }
}

function Invoke-WhoAmI {
    param([string]$BaseUrl)

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return [pscustomobject]@{
            configured = $false
            url = ""
            success = $false
            status_code = $null
            payload = $null
            error = ""
        }
    }

    $whoAmIUrl = if ($BaseUrl -match '\?') { "$BaseUrl&view=whoami" } else { "$BaseUrl?view=whoami" }
    try {
        $response = Invoke-WebRequest -Uri $whoAmIUrl -Method Get -TimeoutSec 20 -UseBasicParsing
        $payload = $null
        try {
            $payload = $response.Content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $payload = $response.Content
        }
        return [pscustomobject]@{
            configured = $true
            url = $whoAmIUrl
            success = $true
            status_code = [int]$response.StatusCode
            payload = $payload
            error = ""
        }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        return [pscustomobject]@{
            configured = $true
            url = $whoAmIUrl
            success = $false
            status_code = $statusCode
            payload = $null
            error = $_.Exception.Message
        }
    }
}

function Get-LiveInfo {
    param(
        [string]$RepoRoot,
        [System.Collections.Generic.List[string]]$Warnings,
        [System.Collections.Generic.List[object]]$SkippedChecks,
        [string]$Mode
    )

    $urls = Get-LiveUrlCandidates -RepoRoot $RepoRoot
    $urlsConfigured = (-not [string]::IsNullOrWhiteSpace($urls.admin_url) -or -not [string]::IsNullOrWhiteSpace($urls.student_url))

    if ($Mode -ne "HI") {
        Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "live_whoami" -Reason ("{0} mode does not perform live whoami checks." -f $Mode)
        return [pscustomobject]@{
            configured = $urlsConfigured
            admin = [pscustomobject]@{ configured = -not [string]::IsNullOrWhiteSpace($urls.admin_url); url = ""; success = $false; status_code = $null; payload = $null; error = "" }
            student = [pscustomobject]@{ configured = -not [string]::IsNullOrWhiteSpace($urls.student_url); url = ""; success = $false; status_code = $null; payload = $null; error = "" }
            match = $null
        }
    }

    $admin = Invoke-WhoAmI -BaseUrl $urls.admin_url
    $student = Invoke-WhoAmI -BaseUrl $urls.student_url

    if (-not $admin.configured -and -not $student.configured) {
        Add-SkippedCheck -SkippedChecks $SkippedChecks -Check "live_whoami" -Reason "No Admin/Student live URLs configured."
        return [pscustomobject]@{
            configured = $false
            admin = $admin
            student = $student
            match = $null
        }
    }

    if ($admin.configured -and -not $admin.success) {
        Add-Warning -Warnings $Warnings -Message ("Admin whoami check failed: {0}" -f $admin.error)
    }
    if ($student.configured -and -not $student.success) {
        Add-Warning -Warnings $Warnings -Message ("Student whoami check failed: {0}" -f $student.error)
    }

    $match = $null
    if ($admin.success -and $student.success) {
        $adminJson = $admin.payload | ConvertTo-Json -Depth 10 -Compress
        $studentJson = $student.payload | ConvertTo-Json -Depth 10 -Compress
        $match = ($adminJson -eq $studentJson)
    }

    [pscustomobject]@{
        configured = $true
        admin = $admin
        student = $student
        match = $match
    }
}

function Get-NextRecommendedMode {
    param(
        [string]$CurrentMode,
        [object]$TagInfo,
        [object]$ClaspInfo,
        [object]$LiveInfo
    )

    if ($CurrentMode -eq "LO") {
        if (-not [string]::IsNullOrWhiteSpace($TagInfo.remote_origin) -or $ClaspInfo.exists -or $LiveInfo.configured) {
            return "MED"
        }
        return "LO"
    }

    if ($CurrentMode -eq "MED") {
        if ($LiveInfo.configured) {
            return "HI"
        }
        return "MED"
    }

    return "HI"
}

function Get-Classification {
    param(
        [object]$GitInfo,
        [object]$ConfigInfo,
        [object]$TagInfo,
        [object]$LiveInfo
    )

    if ($GitInfo.is_repo -and $GitInfo.dirty) { return "LOCAL_DIRTY" }
    if ($ConfigInfo.exists -and -not $ConfigInfo.version_matches_expected) { return "VERSION_MISMATCH" }
    if (-not [string]::IsNullOrWhiteSpace($TagInfo.local_latest) -and -not [string]::IsNullOrWhiteSpace($TagInfo.remote_latest) -and $TagInfo.local_latest -ne $TagInfo.remote_latest) {
        return "TAG_MISMATCH"
    }
    if ($LiveInfo.configured -and $LiveInfo.match -eq $false) { return "LIVE_MISMATCH" }

    $hasConfigSignal = $ConfigInfo.exists -and -not [string]::IsNullOrWhiteSpace($ConfigInfo.version) -and -not [string]::IsNullOrWhiteSpace($ConfigInfo.deploy_version_number)
    $hasTagSignal = -not [string]::IsNullOrWhiteSpace($TagInfo.local_latest) -or -not [string]::IsNullOrWhiteSpace($TagInfo.remote_latest)
    $hasLiveSignal = ($LiveInfo.match -ne $null) -or $LiveInfo.admin.success -or $LiveInfo.student.success
    if (-not $GitInfo.is_repo -or ((-not $hasConfigSignal) -and (-not $hasTagSignal) -and (-not $hasLiveSignal))) {
        return "INSUFFICIENT_DATA"
    }

    return "CLEAN_MATCH"
}

$repoRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path -Path $repoRoot -ChildPath ".git"))) {
    throw "Run this script from a git repo root or pass -ProjectPath to a git repo root."
}

$authorityTool = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "tools\local_authority_check.ps1"
if (Test-Path -LiteralPath $authorityTool) {
    $callerProjectPath = $ProjectPath
    $callerMode = $Mode
    $callerAsJson = $AsJson
    . $authorityTool
    $ProjectPath = $callerProjectPath
    $Mode = $callerMode
    $AsJson = $callerAsJson
    $authority = Test-LocalAuthority -ProjectRoot $repoRoot -Mode $Mode
    if ($authority.status -notin @("LOCAL_AUTHORITY_OK", "LOCAL_AUTHORITY_DIRTY_RECORDED")) {
        Write-Host $authority.status
        Write-Host $authority.message
        Write-Host ("Remote proof: {0} - {1}" -f $authority.remote_proof.status, $authority.remote_proof.reason)
        throw "Release truth stopped before remote checks because local authority is not established."
    }
}

$warnings = New-StringList
$skippedChecks = New-ObjectList
$gitBranch = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")
$gitHead = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("rev-parse", "HEAD")
$gitStatus = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("status", "-sb")
$gitPorcelain = Invoke-GitRead -RepoRoot $repoRoot -GitArgs @("status", "--porcelain")

if ($gitBranch.code -ne 0) { Add-Warning -Warnings $warnings -Message "Unable to read git branch." }
if ($gitHead.code -ne 0) { Add-Warning -Warnings $warnings -Message "Unable to read git HEAD." }
if ($gitStatus.code -ne 0) { Add-Warning -Warnings $warnings -Message "Unable to read git status -sb." }

$gitInfo = [pscustomobject]@{
    is_repo = $true
    branch = $gitBranch.text
    head = $gitHead.text
    status_sb = $gitStatus.text
    dirty = ($gitPorcelain.code -eq 0 -and $gitPorcelain.output.Count -gt 0)
}

$configInfo = Get-ConfigInfo -RepoRoot $repoRoot -Warnings $warnings
$taskInfo = Get-CurrentTaskBaseline -RepoRoot $repoRoot -Warnings $warnings
$tagInfo = Get-StagingTags -RepoRoot $repoRoot -Warnings $warnings -SkippedChecks $skippedChecks -Mode $Mode
$claspInfo = Get-ClaspInventory -RepoRoot $repoRoot -Warnings $warnings -SkippedChecks $skippedChecks -Mode $Mode
$liveInfo = Get-LiveInfo -RepoRoot $repoRoot -Warnings $warnings -SkippedChecks $skippedChecks -Mode $Mode
$classification = Get-Classification -GitInfo $gitInfo -ConfigInfo $configInfo -TagInfo $tagInfo -LiveInfo $liveInfo
$nextRecommendedMode = Get-NextRecommendedMode -CurrentMode $Mode -TagInfo $tagInfo -ClaspInfo $claspInfo -LiveInfo $liveInfo
$skippedChecksArray = @($skippedChecks | ForEach-Object { $_ })
$warningsArray = @($warnings | ForEach-Object { $_ })

$report = New-Object psobject
$report | Add-Member -NotePropertyName "timestamp_utc" -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
$report | Add-Member -NotePropertyName "repo_root" -NotePropertyValue $repoRoot
$report | Add-Member -NotePropertyName "mode" -NotePropertyValue $Mode
$report | Add-Member -NotePropertyName "git" -NotePropertyValue $gitInfo
$report | Add-Member -NotePropertyName "config" -NotePropertyValue $configInfo
$report | Add-Member -NotePropertyName "tags" -NotePropertyValue $tagInfo
$report | Add-Member -NotePropertyName "clasp" -NotePropertyValue $claspInfo
$report | Add-Member -NotePropertyName "current_task" -NotePropertyValue $taskInfo
$report | Add-Member -NotePropertyName "live" -NotePropertyValue $liveInfo
$report | Add-Member -NotePropertyName "skipped_checks" -NotePropertyValue $skippedChecksArray
$report | Add-Member -NotePropertyName "warnings" -NotePropertyValue $warningsArray
$report | Add-Member -NotePropertyName "classification" -NotePropertyValue $classification
$report | Add-Member -NotePropertyName "next_recommended_mode" -NotePropertyValue $nextRecommendedMode

$reportDir = Join-Path -Path $repoRoot -ChildPath ".codexhub\release_truth"
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

Write-Host "Release Truth Check"
Write-Host ("Mode: {0}" -f $Mode)
Write-Host ("Repo root: {0}" -f $repoRoot)
Write-Host ("Branch: {0}" -f $(if ($gitInfo.branch) { $gitInfo.branch } else { "unknown" }))
Write-Host ("HEAD: {0}" -f $(if ($gitInfo.head) { $gitInfo.head } else { "unknown" }))
Write-Host "git status -sb:"
Write-Host $gitInfo.status_sb
Write-Host ("Latest local staging tag: {0}" -f $(if ($tagInfo.local_latest) { $tagInfo.local_latest } else { "not found" }))
Write-Host ("Latest remote staging tag: {0}" -f $(if ($tagInfo.remote_latest) { $tagInfo.remote_latest } else { "not available" }))
Write-Host ("Config.js VERSION: {0}" -f $(if ($configInfo.version) { $configInfo.version } else { "not found" }))
Write-Host ("Config.js DEPLOY_VERSION_NUMBER: {0}" -f $(if ($configInfo.deploy_version_number) { $configInfo.deploy_version_number } else { "not found" }))
Write-Host ("VERSION == r + DEPLOY_VERSION_NUMBER: {0}" -f $configInfo.version_matches_expected)
Write-Host ("CURRENT_TASK baseline version: {0}" -f $(if ($taskInfo.version) { $taskInfo.version } else { "not found" }))
Write-Host ("CURRENT_TASK baseline deploy: {0}" -f $(if ($taskInfo.deploy_version_number) { $taskInfo.deploy_version_number } else { "not found" }))
Write-Host ("Clasp inventory available: {0}" -f $claspInfo.inventory_available)
if ($liveInfo.configured -and $Mode -eq "HI") {
    Write-Host ("Admin whoami: {0}" -f $(if ($liveInfo.admin.success) { "OK" } else { "FAILED" }))
    Write-Host ("Student whoami: {0}" -f $(if ($liveInfo.student.success) { "OK" } else { "FAILED" }))
    Write-Host ("Live match: {0}" -f $(if ($liveInfo.match -ne $null) { $liveInfo.match } else { "not comparable" }))
} else {
    Write-Host "Live whoami: not configured or skipped"
}
if ($skippedChecks.Count -gt 0) {
    Write-Host "Skipped checks:"
    foreach ($entry in $skippedChecks) {
        Write-Host ("- {0}: {1}" -f $entry.check, $entry.reason)
    }
}
if ($warnings.Count -gt 0) {
    Write-Host "Warnings:"
    foreach ($warning in $warnings) {
        Write-Host ("- {0}" -f $warning)
    }
}
Write-Host ("Classification: {0}" -f $classification)
Write-Host ("Next recommended mode: {0}" -f $nextRecommendedMode)
Write-Host ("JSON report: {0}" -f $reportPath)
