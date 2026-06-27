# ShahGrid - shared helpers for setup.ps1 / update.ps1
# Dot-source this file:  . "$PSScriptRoot\lib\common.ps1"
#
# Pure Windows PowerShell 5.1+ / PowerShell 7+. No external modules required.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Constants ----------------------------------------------------------------
$Global:SG = [ordered]@{
    Repo        = 'jeswanisumit1999/ShahGrid'   # public GitHub repo (owner/name)
    Domain      = 'app.shahgrid.com'
    Root        = 'E:\apps\shahgrid'             # all server state lives here
    NvmHome     = 'E:\apps\nvm'                  # nvm-windows install dir
    PgBin       = 'E:\apps\PostgreSQL\16\bin'    # psql.exe / pg_dump.exe live here
    CaddyExe    = 'E:\apps\Caddy\caddy_windows_amd64_custom.exe'
    PgBouncerExe= 'E:\apps\PgBouncer\bin\pgbouncer.exe'
    NssmExe     = 'E:\apps\shahgrid\tools\nssm.exe'
    BackendPort = 3000
    PgPort      = 5432
    PgBouncerPort = 6432
}
$Global:SG.Releases = Join-Path $SG.Root 'releases'
$Global:SG.Current  = Join-Path $SG.Root 'current'
$Global:SG.Shared   = Join-Path $SG.Root 'shared'
$Global:SG.Logs     = Join-Path $SG.Root 'logs'
$Global:SG.State    = Join-Path $SG.Root 'state'
$Global:SG.Tools    = Join-Path $SG.Root 'tools'

# Service names registered with NSSM (run as LocalSystem -> start at boot, no login).
$Global:SG.Svc = [ordered]@{
    Backend    = 'shahgrid-backend'
    Caddy      = 'shahgrid-caddy'
    PgBouncer  = 'shahgrid-pgbouncer'
}

# -- Pretty logging -----------------------------------------------------------
function Write-Step([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok  ([string]$m) { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Err ([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Info([string]$m) { Write-Host "  $m" -ForegroundColor Gray }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated (Administrator) PowerShell."
    }
}

function New-Dirs {
    foreach ($d in @($SG.Root, $SG.Releases, $SG.Shared, $SG.Logs, $SG.State, $SG.Tools)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# -- Resolve the real (non-symlink) node.exe so the service path is stable -----
function Get-NodeExe {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "node not found on PATH. Run 'nvm use lts' first (see setup.ps1)." }
    $ver = (& node -v).Trim()                       # e.g. v20.17.0
    $real = Join-Path $SG.NvmHome "$ver\node.exe"   # nvm-windows layout
    if (Test-Path $real) { return $real }
    return $cmd.Source                              # fallback: whatever PATH resolved
}

# -- GitHub public release helpers (no auth - repo is public) -----------------
function Get-LatestRelease {
    $url = "https://api.github.com/repos/$($SG.Repo)/releases/latest"
    $headers = @{ 'User-Agent' = 'shahgrid-deploy'; 'Accept' = 'application/vnd.github+json' }
    $r = Invoke-RestMethod -Uri $url -Headers $headers
    $assets = @{}
    foreach ($a in $r.assets) { $assets[$a.name] = $a.browser_download_url }
    return [pscustomobject]@{ Tag = $r.tag_name; Assets = $assets }
}

# Pick the single asset whose name starts with a prefix (backend- / frontend-).
function Find-Asset([hashtable]$assets, [string]$prefix) {
    $name = $assets.Keys | Where-Object { $_ -like "$prefix*" } | Select-Object -First 1
    if (-not $name) { throw "No release asset starting with '$prefix' found." }
    return [pscustomobject]@{ Name = $name; Url = $assets[$name] }
}

function Save-File([string]$url, [string]$dest) {
    Write-Info "downloading $(Split-Path $dest -Leaf) ..."
    $headers = @{ 'User-Agent' = 'shahgrid-deploy' }
    Invoke-WebRequest -Uri $url -OutFile $dest -Headers $headers -UseBasicParsing
}

function Expand-Zip([string]$zip, [string]$dest) {
    if (Test-Path $dest) {
        $retry = 0
        while ($retry -lt 5) {
            try {
                Remove-Item $dest -Recurse -Force -ErrorAction Stop
                break
            } catch {
                $retry++
                if ($retry -eq 5) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dest -Force
}

# -- `current` junction management (solves "host folder changes per release") --
function Set-CurrentJunction([string]$targetReleaseDir) {
    if (Test-Path $SG.Current) {
        # Remove existing junction without touching its target contents.
        cmd /c rmdir "$($SG.Current)" | Out-Null
    }
    New-Item -ItemType Junction -Path $SG.Current -Target $targetReleaseDir | Out-Null
    Write-Ok "current -> $targetReleaseDir"
}

function Get-StateValue([string]$name) {
    $f = Join-Path $SG.State "$name.txt"
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return $null
}
function Set-StateValue([string]$name, [string]$value) {
    Set-Content -Path (Join-Path $SG.State "$name.txt") -Value $value -NoNewline
}

# -- Service helpers ----------------------------------------------------------
function Test-ServiceExists([string]$name) {
    return [bool](Get-Service -Name $name -ErrorAction SilentlyContinue)
}

function Install-NssmService {
    param(
        [string]$Name, [string]$Exe, [string]$AppArgs, [string]$WorkDir,
        [string]$StdoutLog, [string]$StderrLog
    )
    $nssm = $SG.NssmExe
    if (-not (Test-Path $nssm)) { throw "nssm.exe missing at $nssm" }
    if (Test-ServiceExists $Name) {
        & $nssm stop $Name confirm 2>$null | Out-Null
        
        # If it's pgbouncer, forcefully kill any zombie instances tying up port 6432
        if ($Name -eq $SG.Svc.PgBouncer) {
            Stop-Process -Name "pgbouncer" -Force -ErrorAction SilentlyContinue
        }

        & $nssm remove $Name confirm | Out-Null
        Start-Sleep -Milliseconds 500
    }
    & $nssm install $Name $Exe | Out-Null
    if ($AppArgs) {
        & $nssm set $Name AppParameters $AppArgs | Out-Null
    }
    & $nssm set $Name AppDirectory $WorkDir | Out-Null
    & $nssm set $Name AppStdout $StdoutLog | Out-Null
    & $nssm set $Name AppStderr $StderrLog | Out-Null
    & $nssm set $Name AppRotateFiles 1 | Out-Null
    & $nssm set $Name AppRotateBytes 10485760 | Out-Null
    & $nssm set $Name Start SERVICE_AUTO_START | Out-Null
    # Restart on crash (no human, no login required - LocalSystem).
    & $nssm set $Name AppExit Default Restart | Out-Null
    & $nssm set $Name AppRestartDelay 5000 | Out-Null
    Write-Ok "service '$Name' installed (auto-start, restart-on-crash)"
}

function Restart-Svc([string]$name) {
    if (Test-ServiceExists $name) {
        Restart-Service -Name $name -Force
        Write-Ok "restarted $name"
    } else { Write-Warn "service $name not installed yet" }
}

# -- Health probe -------------------------------------------------------------
function Test-Health([int]$retries = 10, [int]$delaySec = 3) {
    $url = "https://$($SG.Domain)/health"
    for ($i = 1; $i -le $retries; $i++) {
        try {
            $r = Invoke-RestMethod -Uri $url -TimeoutSec 10
            if ($r.status -eq 'ok') { return $true }
        } catch { }
        Start-Sleep -Seconds $delaySec
    }
    return $false
}

# Run npm ci + prisma generate + migrate deploy inside a backend release dir.
function Initialize-Backend([string]$backendDir, [switch]$Seed) {
    Push-Location $backendDir
    try {
        Write-Info "npm ci (installs prisma CLI + runtime deps) ..."
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
        Write-Info "prisma generate ..."
        & npx prisma generate
        if ($LASTEXITCODE -ne 0) { throw "prisma generate failed" }
        Write-Info "prisma migrate deploy ..."
        & npx prisma migrate deploy
        if ($LASTEXITCODE -ne 0) { throw "prisma migrate deploy failed" }
        
        if ($Seed) {
            Write-Info "prisma db seed ..."
            & npx prisma db seed
            if ($LASTEXITCODE -ne 0) { throw "prisma db seed failed" }
        }

        Write-Ok "backend deps + migrations applied"
    } finally { Pop-Location }
}
