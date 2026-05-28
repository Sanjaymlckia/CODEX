param(
    [string]$ProjectRoot = "",
    [string]$ExpectedRemote = "",
    [ValidateSet("LIGHT", "LO", "MED", "HI")]
    [string]$Mode = "LO",
    [string]$ErrorText = "",
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Test-CodexHubSandboxStartupFailure {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match 'CreateProcessAsUserW failed:\s*1312' -or $Text -match 'windows sandbox:\s*spawn setup refresh')
}

function Assert-CodexHubPowerShell7 {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return [pscustomobject]@{
            status = "LOCAL_AUTHORITY_OK"
            shell_status = "LOCAL_AUTHORITY_OK"
            message = "PowerShell 7 active."
            version = $PSVersionTable.PSVersion.ToString()
            shell_path = $PSHOME
        }
    }

    return [pscustomobject]@{
        status = "POWERSHELL_VERSION_BLOCKED"
        shell_status = "POWERSHELL_VERSION_BLOCKED"
        message = "PowerShell 7 is required. Install or launch pwsh before running CodexHub."
        version = $PSVersionTable.PSVersion.ToString()
        shell_path = $PSHOME
    }
}

function Invoke-CodexHubGitRead {
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

function Test-CodexHubDirtyRecorded {
    param(
        [string]$RepoRoot,
        [string]$StatusText
    )

    $taskPath = Join-Path -Path $RepoRoot -ChildPath "CURRENT_TASK.md"
    $resumePath = Join-Path -Path $RepoRoot -ChildPath ".codexhub\resume_state\latest.json"
    $releasePath = Join-Path -Path $RepoRoot -ChildPath ".codexhub\release_truth\latest.json"
    $signals = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath $taskPath) {
        $taskText = Get-Content -LiteralPath $taskPath -Raw -Encoding utf8
        if ($taskText -match 'CODEXHUB_STATE_BACKUP_START' -or $taskText -match 'Repository state:\s*DIRTY' -or $taskText -match 'dirty-state') {
            $signals.Add("CURRENT_TASK.md records dirty state") | Out-Null
        }
    }

    foreach ($path in @($resumePath, $releasePath)) {
        if (Test-Path -LiteralPath $path) {
            $jsonText = Get-Content -LiteralPath $path -Raw -Encoding utf8
            if ($jsonText -match '"dirty"\s*:\s*true' -or $jsonText -match 'LOCAL_DIRTY|DIRTY_RECORDED') {
                $signals.Add(("{0} records dirty state" -f (Resolve-Path -LiteralPath $path).Path)) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        recorded = ($signals.Count -gt 0)
        signals = @($signals)
    }
}

function Get-CodexHubRemoteProofDecision {
    param(
        [string]$Status,
        [string]$Mode,
        [string]$FailureReason
    )

    if ($Status -in @("LOCAL_AUTHORITY_OK", "LOCAL_AUTHORITY_DIRTY_RECORDED")) {
        return [pscustomobject]@{
            status = "REMOTE_PROOF_BLOCKED"
            allowed = $false
            reason = "Local authority is sufficient; remote proof is not needed."
        }
    }

    if ($Status -in @("SANDBOX_STARTUP_FAILURE", "POWERSHELL_VERSION_BLOCKED")) {
        return [pscustomobject]@{
            status = "REMOTE_PROOF_BLOCKED"
            allowed = $false
            reason = "Remote proof blocked because failure is environment startup or shell version, not repo authority."
        }
    }

    if ($Mode -eq "HI") {
        return [pscustomobject]@{
            status = "REMOTE_PROOF_ALLOWED"
            allowed = $true
            reason = ("HI mode permits remote proof because local authority status is {0}: {1}" -f $Status, $FailureReason)
        }
    }

    return [pscustomobject]@{
        status = "REMOTE_PROOF_BLOCKED"
        allowed = $false
        reason = ("{0} mode blocks temp repo, remote proof, and outside-memory fallback." -f $Mode)
    }
}

function Test-LocalAuthority {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$ExpectedRemote = "",
        [ValidateSet("LIGHT", "LO", "MED", "HI")]
        [string]$Mode = "LO",
        [string]$ErrorText = ""
    )

    $shell = Assert-CodexHubPowerShell7
    if ($shell.status -eq "POWERSHELL_VERSION_BLOCKED") {
        $remote = Get-CodexHubRemoteProofDecision -Status $shell.status -Mode $Mode -FailureReason $shell.message
        return [pscustomobject]@{
            status = "POWERSHELL_VERSION_BLOCKED"
            message = $shell.message
            project_root = $ProjectRoot
            expected_remote = $ExpectedRemote
            mode = $Mode
            shell = $shell
            remote_proof = $remote
            temp_repo_status = "REMOTE_PROOF_BLOCKED"
            outside_memory_status = "REMOTE_PROOF_BLOCKED"
            mcp_status = "MCP_WARNING_NON_BLOCKING"
        }
    }

    if (Test-CodexHubSandboxStartupFailure -Text $ErrorText) {
        $message = "SANDBOX_STARTUP_FAILURE: Windows sandbox runner could not create process/session. This is environment startup failure, not project authority failure. No temp repo, no outside-memory search, and no remote proof was created."
        $remote = Get-CodexHubRemoteProofDecision -Status "SANDBOX_STARTUP_FAILURE" -Mode $Mode -FailureReason $message
        return [pscustomobject]@{
            status = "SANDBOX_STARTUP_FAILURE"
            message = $message
            project_root = $ProjectRoot
            expected_remote = $ExpectedRemote
            mode = $Mode
            shell = $shell
            remote_proof = $remote
            temp_repo_status = "REMOTE_PROOF_BLOCKED"
            outside_memory_status = "REMOTE_PROOF_BLOCKED"
            mcp_status = "MCP_WARNING_NON_BLOCKING"
        }
    }

    $resolvedRoot = ""
    if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot)) {
        $status = "LOCAL_AUTHORITY_MISSING"
        $message = ("Project root missing: {0}" -f $ProjectRoot)
    } else {
        $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
        if (-not (Test-Path -LiteralPath (Join-Path -Path $resolvedRoot -ChildPath ".git"))) {
            $status = "LOCAL_AUTHORITY_NOT_GIT_REPO"
            $message = ("Project root is not a git repository: {0}" -f $resolvedRoot)
        } else {
            $top = Invoke-CodexHubGitRead -RepoRoot $resolvedRoot -GitArgs @("rev-parse", "--show-toplevel")
            if ($top.code -ne 0) {
                $status = "LOCAL_AUTHORITY_NOT_GIT_REPO"
                $message = ("Unable to read git top-level: {0}" -f $top.text)
            } else {
                $topLevel = (Resolve-Path -LiteralPath $top.text).Path
                if ($topLevel -ne $resolvedRoot) {
                    $status = "LOCAL_AUTHORITY_NOT_GIT_REPO"
                    $message = ("Git top-level mismatch. Expected {0}; got {1}" -f $resolvedRoot, $topLevel)
                } else {
                    $origin = Invoke-CodexHubGitRead -RepoRoot $resolvedRoot -GitArgs @("remote", "get-url", "origin")
                    $originText = if ($origin.code -eq 0) { $origin.text } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($ExpectedRemote) -and $originText -ne $ExpectedRemote) {
                        $status = "LOCAL_AUTHORITY_REMOTE_MISMATCH"
                        $message = ("Origin remote mismatch. Expected {0}; got {1}" -f $ExpectedRemote, $originText)
                    } elseif ($resolvedRoot -like "E:\Gdrive\01 SANJAY\*") {
                        $status = "LOCAL_AUTHORITY_MISSING"
                        $message = "Legacy path E:\Gdrive\01 SANJAY is not active authority when E:\Gdrive\01_SANJAY is current."
                    } else {
                        $porcelain = Invoke-CodexHubGitRead -RepoRoot $resolvedRoot -GitArgs @("status", "--porcelain")
                        if ($porcelain.code -ne 0) {
                            $status = "LOCAL_AUTHORITY_NOT_GIT_REPO"
                            $message = ("Unable to read git status: {0}" -f $porcelain.text)
                        } elseif ($porcelain.output.Count -gt 0) {
                            $recorded = Test-CodexHubDirtyRecorded -RepoRoot $resolvedRoot -StatusText $porcelain.text
                            if ($recorded.recorded) {
                                $status = "LOCAL_AUTHORITY_DIRTY_RECORDED"
                                $message = ("Dirty state is recorded: {0}" -f ($recorded.signals -join "; "))
                            } else {
                                $status = "LOCAL_AUTHORITY_DIRTY_UNRECORDED"
                                $message = "Dirty state is not recorded in CURRENT_TASK.md or .codexhub state."
                            }
                        } else {
                            $status = "LOCAL_AUTHORITY_OK"
                            $message = "Local git authority is clean and valid."
                        }
                    }
                }
            }
        }
    }

    $statusSb = ""
    $originOut = ""
    if (-not [string]::IsNullOrWhiteSpace($resolvedRoot) -and (Test-Path -LiteralPath (Join-Path -Path $resolvedRoot -ChildPath ".git"))) {
        $statusResult = Invoke-CodexHubGitRead -RepoRoot $resolvedRoot -GitArgs @("status", "-sb")
        $originResult = Invoke-CodexHubGitRead -RepoRoot $resolvedRoot -GitArgs @("remote", "get-url", "origin")
        $statusSb = $statusResult.text
        $originOut = $originResult.text
    }

    $remoteDecision = Get-CodexHubRemoteProofDecision -Status $status -Mode $Mode -FailureReason $message

    return [pscustomobject]@{
        status = $status
        message = $message
        project_root = $ProjectRoot
        resolved_root = $resolvedRoot
        expected_remote = $ExpectedRemote
        actual_remote = $originOut
        mode = $Mode
        git_status_sb = $statusSb
        shell = $shell
        remote_proof = $remoteDecision
        temp_repo_status = "REMOTE_PROOF_BLOCKED"
        outside_memory_status = "REMOTE_PROOF_BLOCKED"
        mcp_status = "MCP_WARNING_NON_BLOCKING"
    }
}

if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $result = Test-LocalAuthority -ProjectRoot $ProjectRoot -ExpectedRemote $ExpectedRemote -Mode $Mode -ErrorText $ErrorText
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 8
    } else {
        Write-Host $result.status
        Write-Host $result.message
        Write-Host ("Remote proof: {0} - {1}" -f $result.remote_proof.status, $result.remote_proof.reason)
    }
}
