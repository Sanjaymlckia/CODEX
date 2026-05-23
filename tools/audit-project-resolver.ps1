# CodexHub Project Resolver Audit
# SAFE: no project moves, no registry mutation unless explicitly copied later

$CodexRoot = Split-Path -Parent $PSScriptRoot
$ProjectsJson = Join-Path $CodexRoot "projects\projects.json"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = Join-Path $CodexRoot "audit\resolver_normalization_$Timestamp"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Report = Join-Path $OutDir "resolver_normalization_report.txt"
$PreviewJson = Join-Path $OutDir "projects.normalized.preview.json"

# Authority root: E:\Gdrive\01_SANJAY\Codex_Sync
# Legacy fallback roots below are for discovery only and must not override authority-root matches.
$CandidateRoots = @(
    "E:\Gdrive\01_SANJAY\Codex_Sync",
    "D:\CODEX_PROJECTS",
    "C:\CODEX_PROJECTS"
)

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Write-Host $line
    Add-Content -Path $Report -Value $line
}

function Get-PossibleNames {
    param(
        [string]$ProjectName,
        [string]$DisplayName
    )

    $names = @(
        $ProjectName,
        $DisplayName,
        ($DisplayName -replace " ", "_"),
        ($ProjectName -replace "_", " ")
    )

    # Special legacy alias ONLY for Zoho CRM
    if ($ProjectName -eq "ZOHO_CRM") {
        $names += "CODEX_CRM"
    }

    return $names | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique
}

function Find-ProjectFolder {
    param(
        [string]$ProjectName,
        [string]$DisplayName,
        [string]$CurrentPath
    )

    $candidates = @()

    if ($CurrentPath -and (Test-Path $CurrentPath)) {
        $candidates += $CurrentPath
    }

    foreach ($root in $CandidateRoots) {
        if (Test-Path $root) {
            $possibleNames = Get-PossibleNames -ProjectName $ProjectName -DisplayName $DisplayName

            foreach ($name in $possibleNames) {
                $path = Join-Path $root $name
                if (Test-Path $path) {
                    $candidates += $path
                }
            }
        }
    }

    return $candidates | Select-Object -Unique
}

if (!(Test-Path $ProjectsJson)) {
    throw "projects.json not found: $ProjectsJson"
}

Log "Starting CodexHub resolver normalization audit."
Log "Codex root: $CodexRoot"
Log "Registry: $ProjectsJson"

$projects = Get-Content $ProjectsJson -Raw | ConvertFrom-Json
$normalized = @()

foreach ($p in $projects) {
    Log ""
    Log "Project: $($p.name)"
    Log "Display: $($p.display_name)"
    Log "Registry path: $($p.path)"

    $found = Find-ProjectFolder -ProjectName $p.name -DisplayName $p.display_name -CurrentPath $p.path

    if ($found.Count -eq 0) {
        Log "STATUS: MISSING"
        $preferred = $p.path
    }
    else {
        Log "Found candidates:"
        foreach ($f in $found) {
            $git = if (Test-Path (Join-Path $f ".git")) { "git" } else { "no-git" }
            Log " - $f [$git]"
        }

        $preferred = $found | Where-Object { $_ -like "E:\Gdrive\01_SANJAY\Codex_Sync\*" } | Select-Object -First 1
        if (!$preferred) { $preferred = $found | Where-Object { $_ -like "D:\CODEX_PROJECTS\*" } | Select-Object -First 1 }
        if (!$preferred) { $preferred = $found | Where-Object { $_ -like "C:\CODEX_PROJECTS\*" } | Select-Object -First 1 }
        if (!$preferred) { $preferred = $found | Select-Object -First 1 }

        Log "Preferred path: $preferred"
    }

    $obj = [ordered]@{
        name            = $p.name
        display_name    = $p.display_name
        status          = $p.status
        path            = $preferred
        type            = $p.type
        startup_context = $p.startup_context
        notes           = $p.notes
        resolver        = [ordered]@{
            preferred_path = $preferred
            candidates     = @($found)
            home_root      = "D:\CODEX_PROJECTS"
            sync_root      = "E:\Gdrive\01_SANJAY\Codex_Sync"
            office_root    = "C:\CODEX_PROJECTS"
        }
    }

    $normalized += New-Object psobject -Property $obj
}

$normalized | ConvertTo-Json -Depth 8 | Set-Content -Path $PreviewJson -Encoding UTF8

Log ""
Log "Audit complete."
Log "Report: $Report"
Log "Preview normalized registry: $PreviewJson"
Log "No files were moved."
Log "Original projects.json was not changed."

