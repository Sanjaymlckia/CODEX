[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$AdminUrl,

  [Parameter(Mandatory = $true)]
  [string]$ExpectedRuntime,

  [Parameter(Mandatory = $true)]
  [string]$ExpectedDeploy,

  [Parameter(Mandatory = $true)]
  [string]$ApplicantId,

  [string]$Spec = 'specs/fode-admin-document-preview.spec.ts',

  [switch]$Headed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DotEnvValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Key
  )
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $idx = $trimmed.IndexOf('=')
    if ($idx -lt 1) { continue }
    $name = $trimmed.Substring(0, $idx).Trim()
    if ($name -ne $Key) { continue }
    return $trimmed.Substring($idx + 1).Trim()
  }
  return $null
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $toolRoot
try {
  $packageJson = Join-Path $toolRoot 'package.json'
  $authState = Join-Path $toolRoot 'auth\admin-storage-state.json'
  $specPath = Join-Path $toolRoot $Spec
  $dotEnvPath = Join-Path $toolRoot '.env'

  foreach ($required in @($packageJson, $authState, $specPath)) {
    if (-not (Test-Path -LiteralPath $required)) {
      throw "Required file missing: $required"
    }
  }

  $studentUrl = $env:FODE_STUDENT_URL
  if (-not $studentUrl) {
    $studentUrl = Get-DotEnvValue -Path $dotEnvPath -Key 'FODE_STUDENT_URL'
  }
  if (-not $studentUrl) {
    throw 'FODE_STUDENT_URL is required via environment or .env for the existing specs.'
  }

  $env:FODE_ADMIN_URL = $AdminUrl
  $env:FODE_STUDENT_URL = $studentUrl
  $env:FODE_EXPECTED_RUNTIME = $ExpectedRuntime
  $env:FODE_EXPECTED_DEPLOY = $ExpectedDeploy
  $env:FODE_ACCEPT_HEAD = 'false'
  $env:FODE_DOC_REVIEW_APPLICANT_ID = $ApplicantId

  $runArgs = @('playwright', 'test', $Spec, '--project=chromium')
  if ($Headed) { $runArgs += '--headed' }
  $listArgs = @('playwright', 'test', $Spec, '--list')

  Write-Host 'FODE staging acceptance check' -ForegroundColor Cyan
  Write-Host ("  ToolRoot: {0}" -f $toolRoot)
  Write-Host ("  Tested URL: {0}" -f $env:FODE_ADMIN_URL)
  Write-Host ("  Expected Runtime: {0}" -f $env:FODE_EXPECTED_RUNTIME)
  Write-Host ("  Expected Deploy: {0}" -f $env:FODE_EXPECTED_DEPLOY)
  Write-Host ("  Applicant ID: {0}" -f $env:FODE_DOC_REVIEW_APPLICANT_ID)
  Write-Host ("  Spec: {0}" -f $Spec)
  Write-Host ("  Headed: {0}" -f [bool]$Headed)

  Write-Host "`nListing spec..." -ForegroundColor Yellow
  & npx @listArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Spec listing failed with exit code $LASTEXITCODE"
  }

  $reportsBefore = @()
  if (Test-Path -LiteralPath (Join-Path $toolRoot 'reports')) {
    $reportsBefore = Get-ChildItem -LiteralPath (Join-Path $toolRoot 'reports') -Directory | Sort-Object LastWriteTimeUtc
  }

  Write-Host "`nRunning Playwright acceptance..." -ForegroundColor Yellow
  & npx @runArgs
  $exitCode = $LASTEXITCODE

  $reportsAfter = @()
  if (Test-Path -LiteralPath (Join-Path $toolRoot 'reports')) {
    $reportsAfter = Get-ChildItem -LiteralPath (Join-Path $toolRoot 'reports') -Directory | Sort-Object LastWriteTimeUtc
  }
  $latestReport = $reportsAfter | Select-Object -Last 1
  $latestReportPath = if ($latestReport) { $latestReport.FullName } else { '' }

  if ($exitCode -eq 0) {
    Write-Host "`nPASS" -ForegroundColor Green
  } else {
    Write-Host "`nFAIL" -ForegroundColor Red
  }
  Write-Host ("  Tested URL: {0}" -f $env:FODE_ADMIN_URL)
  Write-Host ("  Expected Runtime/Deploy: {0} / {1}" -f $env:FODE_EXPECTED_RUNTIME, $env:FODE_EXPECTED_DEPLOY)
  Write-Host ("  Applicant ID: {0}" -f $env:FODE_DOC_REVIEW_APPLICANT_ID)
  Write-Host ("  Spec: {0}" -f $Spec)
  if ($latestReportPath) {
    Write-Host ("  Latest Report Dir: {0}" -f $latestReportPath)
  }

  exit $exitCode
}
finally {
  Pop-Location
}
