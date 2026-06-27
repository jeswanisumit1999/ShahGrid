<#
.SYNOPSIS
  Pull the latest ShahGrid release from GitHub and activate it.

.DESCRIPTION
  Downloads the backend/frontend zips published by release.ps1, extracts them
  into E:\apps\shahgrid\releases\<tag>\, runs prisma generate + migrate deploy
  for the backend, flips the `current` junction to the new release, restarts the
  services, and verifies /health. On failure it rolls the junction back.

  Repo is public, so no GitHub login is needed on the server.

.PARAMETER BackendOnly
  Only refresh the backend (reuse current frontend).

.PARAMETER FrontendOnly
  Only refresh the frontend (reuse current backend; no migrations).

.PARAMETER Tag
  Deploy a specific release tag instead of "latest".

.PARAMETER Force
  Re-deploy even if the resolved tag already matches the active release.

.EXAMPLE
  .\update.ps1
  .\update.ps1 -FrontendOnly
  .\update.ps1 -Tag v1.2.0 -Force
#>
[CmdletBinding()]
param(
    [switch]$BackendOnly,
    [switch]$FrontendOnly,
    [string]$Tag,
    [switch]$Force
)

. "$PSScriptRoot\lib\common.ps1"
Assert-Admin
New-Dirs

# Make sure node + npm/npx from nvm are on PATH for the prisma steps.
$env:Path = "$($SG.NvmHome);$env:Path"
$env:Path = "$(Split-Path (Get-NodeExe));$env:Path"

Write-Step "Resolving release"
if ($Tag) {
    $tagName = $Tag
    $rel = Get-LatestRelease   # still need asset list; fall back below if tag differs
    if ($rel.Tag -ne $Tag) {
        # Query the specific tag's assets.
        $headers = @{ 'User-Agent' = 'shahgrid-deploy'; 'Accept' = 'application/vnd.github+json' }
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$($SG.Repo)/releases/tags/$Tag" -Headers $headers
        $assets = @{}; foreach ($a in $r.assets) { $assets[$a.name] = $a.browser_download_url }
        $rel = [pscustomobject]@{ Tag = $r.tag_name; Assets = $assets }
    }
} else {
    $rel = Get-LatestRelease
    $tagName = $rel.Tag
}
Write-Ok "target release: $tagName"

$activeTag = Get-StateValue 'current_tag'
if ($activeTag -eq $tagName -and -not $Force) {
    Write-Warn "release $tagName is already active. Use -Force to redeploy."
    return
}

$releaseDir  = Join-Path $SG.Releases $tagName
$beDir       = Join-Path $releaseDir 'backend'
$feDir       = Join-Path $releaseDir 'frontend'
$tmp         = Join-Path $SG.State 'dl'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $releaseDir, $tmp -Force | Out-Null

$doBackend  = -not $FrontendOnly
$doFrontend = -not $BackendOnly

# ── Backend ──────────────────────────────────────────────────────────────────
if ($doBackend) {
    Write-Step "Fetching backend"
    $a = Find-Asset $rel.Assets 'backend-'
    $zip = Join-Path $tmp $a.Name
    Save-File $a.Url $zip
    Expand-Zip $zip $beDir
    Copy-Item (Join-Path $SG.Shared '.env') (Join-Path $beDir '.env') -Force
    Initialize-Backend $beDir
} else {
    Write-Step "Reusing current backend"
    Copy-Item (Join-Path $SG.Current 'backend') $beDir -Recurse -Force
    Write-Ok "copied backend from active release"
}

# ── Frontend ─────────────────────────────────────────────────────────────────
if ($doFrontend) {
    Write-Step "Fetching frontend"
    $a = Find-Asset $rel.Assets 'frontend-'
    $zip = Join-Path $tmp $a.Name
    Save-File $a.Url $zip
    Expand-Zip $zip $feDir   # yields <feDir>\web\...
    if (-not (Test-Path (Join-Path $feDir 'web\index.html'))) {
        throw "frontend zip did not contain web\index.html"
    }
} else {
    Write-Step "Reusing current frontend"
    Copy-Item (Join-Path $SG.Current 'frontend') $feDir -Recurse -Force
    Write-Ok "copied frontend from active release"
}

# ── Activate ─────────────────────────────────────────────────────────────────
Write-Step "Activating $tagName"
$prevTarget = $null
if (Test-Path $SG.Current) {
    $prevTarget = (Get-Item $SG.Current).Target | Select-Object -First 1
}
Set-CurrentJunction $releaseDir
Restart-Svc $SG.Svc.Backend
# Caddy serves static via the junction; a reload refreshes its file cache.
Restart-Svc $SG.Svc.Caddy

Write-Step "Verifying"
if (Test-Health) {
    if ($activeTag) { Set-StateValue 'previous_tag' $activeTag }
    Set-StateValue 'current_tag' $tagName
    Write-Ok "deploy OK — $($SG.Domain) healthy on $tagName"
} else {
    Write-Err "health check failed — rolling back"
    if ($prevTarget) {
        Set-CurrentJunction $prevTarget
        Restart-Svc $SG.Svc.Backend
        Restart-Svc $SG.Svc.Caddy
        Write-Warn "rolled back to $prevTarget"
    } else {
        Write-Err "no previous release to roll back to. Inspect logs in $($SG.Logs)."
    }
    throw "Deploy of $tagName failed health check."
}
