param(
  [string]$AdminUrl,
  [string]$StudentUrl,
  [string]$ExpectedVersion = "r213",
  [string]$ExpectedVersionNumber = "213"
)

$ErrorActionPreference = "Stop"

if ($AdminUrl) { $env:FODE_ADMIN_URL = $AdminUrl }
if ($StudentUrl) { $env:FODE_STUDENT_URL = $StudentUrl }
$env:EXPECTED_VERSION = $ExpectedVersion
$env:EXPECTED_VERSION_NUMBER = $ExpectedVersionNumber

npm run test:smoke
