<#
.SYNOPSIS
  Build ShahGrid frontend + backend on your LOCAL machine and publish a GitHub
  Release that the server's update.ps1 / setup.ps1 will pull.

.DESCRIPTION
  Runs where the build tools live (Flutter SDK, Node/npm, GitHub CLI `gh`):
    - Frontend: flutter build web --release (API URL baked in at build time)
                -> frontend-<tag>.zip  (contains web\...)
    - Backend:  npm ci + npm run build (tsc)
                -> backend-<tag>.zip   (dist\ + prisma\ + package.json + lock)
                  NOTE: node_modules is NOT shipped; the server runs npm ci.
    - gh release create <tag> with both zips attached.

  Requires: flutter, node/npm, gh (logged in with push access to the repo).

.PARAMETER Tag
  Release tag, e.g. v1.2.0. Required.

.PARAMETER ApiBaseUrl
  Baked into the Flutter web build. Default https://app.shahgrid.com/api/v1.

.PARAMETER SkipFrontend / .PARAMETER SkipBackend
  Build/publish only one side. The matching -FrontendOnly/-BackendOnly on the
  server's update.ps1 then reuses the unchanged half.

.PARAMETER Notes
  Release notes text.

.EXAMPLE
  pwsh ./deploy/windows/release.ps1 -Tag v1.2.0 -Notes "fix retailer export"
  pwsh ./deploy/windows/release.ps1 -Tag v1.2.1 -SkipBackend   # frontend-only
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$ApiBaseUrl = 'https://app.shahgrid.com/api/v1',
    [switch]$SkipFrontend,
    [switch]$SkipBackend,
    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
function Step([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$FrontendDir= Join-Path $RepoRoot 'Frontend\shah_grid'
$BackendDir = Join-Path $RepoRoot 'Backend'
$OutDir     = Join-Path $RepoRoot '.release'
if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir | Out-Null

$assets = @()

# -- Frontend -----------------------------------------------------------------
if (-not $SkipFrontend) {
    Step "Flutter web build (API_BASE_URL=$ApiBaseUrl)"
    Push-Location $FrontendDir
    try {
        & flutter build web --release --dart-define=API_BASE_URL=$ApiBaseUrl
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
    } finally { Pop-Location }

    $feZip = Join-Path $OutDir "frontend-$Tag.zip"
    # Archive the 'web' folder itself so it extracts to <dest>\web\...
    Compress-Archive -Path (Join-Path $FrontendDir 'build\web') -DestinationPath $feZip -Force
    $assets += $feZip
    Write-Host "  built $feZip" -ForegroundColor Green
}

# -- Backend ------------------------------------------------------------------
if (-not $SkipBackend) {
    Step "Backend build (tsc)"
    Push-Location $BackendDir
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
        & npm run build
        if ($LASTEXITCODE -ne 0) { throw "tsc build failed" }
    } finally { Pop-Location }

    $stage = Join-Path $OutDir 'backend-stage'
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item (Join-Path $BackendDir 'dist')              $stage -Recurse
    Copy-Item (Join-Path $BackendDir 'prisma')            $stage -Recurse
    Copy-Item (Join-Path $BackendDir 'package.json')      $stage
    Copy-Item (Join-Path $BackendDir 'package-lock.json') $stage

    $beZip = Join-Path $OutDir "backend-$Tag.zip"
    # Archive stage contents at the zip root (dist\, prisma\, package.json, lock).
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $beZip -Force
    $assets += $beZip
    Write-Host "  built $beZip" -ForegroundColor Green
}

if (-not $assets.Count) { throw "Nothing built (both sides skipped)." }

# -- Publish GitHub Release ---------------------------------------------------
Step "Publishing GitHub release $Tag"
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { throw "GitHub CLI 'gh' not found. Install it and 'gh auth login'." }

if (-not $Notes) { $Notes = "ShahGrid release $Tag" }
# Create or, if the tag already exists, upload/clobber the assets onto it.
$exists = (& gh release view $Tag 2>$null)
if ($LASTEXITCODE -eq 0) {
    & gh release upload $Tag @assets --clobber
} else {
    & gh release create $Tag @assets --title $Tag --notes $Notes
}
if ($LASTEXITCODE -ne 0) { throw "gh release failed" }

Write-Host "`nDone. On the server run:  .\update.ps1" -ForegroundColor Green
if ($SkipBackend)  { Write-Host "  (frontend-only -> server: .\update.ps1 -FrontendOnly)" -ForegroundColor Gray }
if ($SkipFrontend) { Write-Host "  (backend-only  -> server: .\update.ps1 -BackendOnly)"  -ForegroundColor Gray }
