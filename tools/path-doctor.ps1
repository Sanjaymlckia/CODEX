param(
  [string]$ProjectId = "FODE_RUNTIME"
)

$HubRoot = Split-Path -Parent $PSScriptRoot
$ProfilePath = Join-Path $HubRoot "state\machine_profile.json"
$ProjectsPath = Join-Path $HubRoot "projects\projects.json"

Write-Host "`n=== CODEX PATH DOCTOR ===" -ForegroundColor Cyan
Write-Host "Hub root: $HubRoot"
Write-Host "Machine: $env:COMPUTERNAME"

if (-not (Test-Path $ProfilePath)) {
  Write-Host "FAIL: Missing machine_profile.json" -ForegroundColor Red
  exit 1
}

$profile = Get-Content $ProfilePath -Raw | ConvertFrom-Json
$machineName = $env:COMPUTERNAME
$machine = $profile.machines.$machineName

if (-not $machine) {
  Write-Host "FAIL: No machine profile for $machineName" -ForegroundColor Red
  exit 2
}

Write-Host "`nPreferred root: $($machine.preferred_root)"

$resolved = $null
if ($machine.project_path_overrides -and $machine.project_path_overrides.$ProjectId) {
  $resolved = $machine.project_path_overrides.$ProjectId
  Write-Host "Project override: $resolved"
} else {
  Write-Host "WARN: No override for $ProjectId" -ForegroundColor Yellow
}

Write-Host "`nResolved project path:" -ForegroundColor Cyan
Write-Host $resolved

if ($resolved -and (Test-Path $resolved)) {
  Write-Host "PASS: Path exists" -ForegroundColor Green
  Write-Host "`nGit status:" -ForegroundColor Cyan
  git -C $resolved status --porcelain=v2 -b
  Write-Host "`nLatest commit:" -ForegroundColor Cyan
  git -C $resolved log -1 --oneline
} else {
  Write-Host "FAIL: Resolved path missing" -ForegroundColor Red
}

Write-Host "`nAbsolute path warnings in projects.json:" -ForegroundColor Cyan
if (Test-Path $ProjectsPath) {
  Select-String -Path $ProjectsPath -Pattern "^[\s`"']*[A-Z]:\\|E:\\Gdrive|C:\\GoogleDRIVE|C:\\FODE_Runtime_1wog" -ErrorAction SilentlyContinue
}

Write-Host "`nDeprecated path warnings:" -ForegroundColor Cyan
Get-ChildItem $HubRoot -Recurse -File -Include *.json,*.md,*.txt,*.ps1 |
Where-Object { $_.FullName -notmatch "\\.git\\|\\state\\handoffs\\|\\backup" } |
Select-String -Pattern "C:\\FODE_Runtime_1wog|C:\\CODEX_PROJECTS\\FODE_Runtime_1wog" -ErrorAction SilentlyContinue

Write-Host "`n=== PATH DOCTOR COMPLETE ===" -ForegroundColor Green
