param(
  [string]$AdminUrl,
  [string]$ExpectedVersion
)

$ErrorActionPreference = "Stop"

$defaultAdminUrl = "https://script.google.com/macros/s/AKfycbxkuj6ElPa8xE9WJnECcW9u_hGNPMpd79F5Vhxgur-p7MCpmDF2HaLFIgx7yTYRC8aZ/exec"

$adminUrl = $AdminUrl
if ([string]::IsNullOrWhiteSpace($adminUrl)) {
  $adminUrl = Read-Host "Press Enter to use default Admin URL, or paste a different base URL"
}
if ([string]::IsNullOrWhiteSpace($adminUrl)) {
  $adminUrl = $defaultAdminUrl
}
$adminUrl = ($adminUrl -replace '\?.*$','').Trim()

$expectedVersion = $ExpectedVersion
if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
  $expectedVersion = Read-Host "Expected runtime version, e.g. r213"
}
if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
  throw "Expected version is required."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = "reports\fode-smoke"
$reportFile = "$reportDir\fode-smoke-$stamp.txt"
$jsonFile = "$reportDir\fode-smoke-$stamp.json"
$profileDir = "$PWD\.pw-fode-profile"

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$env:FODE_ADMIN_URL = $adminUrl
$env:EXPECTED_VERSION = $expectedVersion
$env:PW_USER_DATA_DIR = $profileDir

$runTs = Get-Date -Format s
$commandUsed = "npx playwright test tools/playwright/fode-smoke.spec.ts --headed --browser=chromium --reporter=json"

function Get-ShortFailureReason {
  param(
    [Parameter(Mandatory = $false)]
    $TestResult
  )

  if ($null -eq $TestResult) {
    return ""
  }

  $parts = @()

  if ($TestResult.error) {
    if ($TestResult.error.message) {
      $parts += [string]$TestResult.error.message
    } elseif ($TestResult.error.value) {
      $parts += [string]$TestResult.error.value
    }
  }

  if ($TestResult.errors) {
    foreach ($err in $TestResult.errors) {
      if ($err.message) {
        $parts += [string]$err.message
      } elseif ($err.value) {
        $parts += [string]$err.value
      }
    }
  }

  $joined = (($parts -join " | ") -replace '\s+', ' ').Trim()
  if ([string]::IsNullOrWhiteSpace($joined)) {
    return ""
  }

  if ($joined.Length -gt 240) {
    return $joined.Substring(0, 240) + "..."
  }

  return $joined
}

function Get-TestSummaries {
  param(
    [Parameter(Mandatory = $true)]
    $Node,
    [Parameter(Mandatory = $false)]
    [string]$Prefix = ""
  )

  $items = @()

  if ($Node.specs) {
    foreach ($spec in $Node.specs) {
      $specTitle = @($Prefix, $spec.title) -ne "" -join " :: "
      foreach ($test in $spec.tests) {
        $results = @($test.results)
        $lastResult = if ($results.Count -gt 0) { $results[-1] } else { $null }
        $status = if ($lastResult -and $lastResult.status) { [string]$lastResult.status } else { "unknown" }
        $reason = if ($status -eq "passed" -or $status -eq "skipped") { "" } else { Get-ShortFailureReason -TestResult $lastResult }
        $items += [pscustomobject]@{
          title = $specTitle
          status = $status.ToUpperInvariant()
          reason = $reason
        }
      }
    }
  }

  if ($Node.suites) {
    foreach ($suite in $Node.suites) {
      $suitePrefix = if ([string]::IsNullOrWhiteSpace($suite.title)) { $Prefix } else { @($Prefix, $suite.title) -ne "" -join " :: " }
      $items += Get-TestSummaries -Node $suite -Prefix $suitePrefix
    }
  }

  return $items
}

Remove-Item -LiteralPath $jsonFile -ErrorAction SilentlyContinue

$consoleLines = @()

try {
  $consoleLines = & npx playwright test "tools/playwright/fode-smoke.spec.ts" --headed --browser=chromium --reporter=json 2>&1
  $consoleLines | Set-Content -Path $jsonFile
  $exit = $LASTEXITCODE
} catch {
  $consoleLines = @([string]$_)
  $exit = 1
}

$overall = if ($exit -eq 0) { "PASS" } else { "FAIL" }
$testSummaries = @()
$failureReasons = @()

if (Test-Path $jsonFile) {
  try {
    $jsonText = Get-Content -Raw -Path $jsonFile
    $json = $jsonText | ConvertFrom-Json -Depth 100
    $testSummaries = @(Get-TestSummaries -Node $json)
    $failureReasons = @($testSummaries | Where-Object { $_.status -notin @("PASSED", "SKIPPED") -and -not [string]::IsNullOrWhiteSpace($_.reason) } | Select-Object -ExpandProperty reason)
  } catch {
    $failureReasons += "Unable to parse Playwright JSON output: $($_.Exception.Message)"
  }
} elseif ($consoleLines.Count -gt 0) {
  $failureReasons += (($consoleLines | Out-String) -replace '\s+', ' ').Trim()
}

if ($failureReasons.Count -eq 0 -and $exit -ne 0) {
  $failureReasons += "Playwright exited non-zero without a parsed failure message."
}

$reportLines = @(
  "PLAYWRIGHT FODE SMOKE TEST"
  "Timestamp: $runTs"
  "Admin URL: $adminUrl"
  "Expected Version: $expectedVersion"
  "Command: $commandUsed"
  "Profile Dir: $profileDir"
  "Test Result: $overall"
  "Per-Test:"
)

if ($testSummaries.Count -gt 0) {
  foreach ($testSummary in $testSummaries) {
    $line = "- [$($testSummary.status)] $($testSummary.title)"
    if (-not [string]::IsNullOrWhiteSpace($testSummary.reason)) {
      $line += " | Reason: $($testSummary.reason)"
    }
    $reportLines += $line
  }
} else {
  $reportLines += "- [UNKNOWN] No parsed test summaries were available."
}

if ($failureReasons.Count -gt 0) {
  $reportLines += "Failure Reason: $($failureReasons[0])"
}

$resolvedReport = Join-Path $PWD $reportFile
$reportLines += "Report Path: $resolvedReport"

$reportLines | Set-Content -Path $reportFile
Remove-Item -LiteralPath $jsonFile -ErrorAction SilentlyContinue

if ($exit -eq 0) {
  Write-Host ""
  Write-Host "COMPACT RESULT:"
  Write-Host "PLAYWRIGHT RESULT: PASS"
  Write-Host "Expected Version: $expectedVersion"
  Write-Host "Report: $resolvedReport"
} else {
  Write-Host ""
  Write-Host "COMPACT RESULT:"
  Write-Host "PLAYWRIGHT RESULT: FAIL"
  Write-Host "Expected Version: $expectedVersion"
  Write-Host "Report: $resolvedReport"
  if ($failureReasons.Count -gt 0) {
    Write-Host "Failure: $($failureReasons[0])"
  }
  exit $exit
}
