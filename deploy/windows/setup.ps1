<#
.SYNOPSIS
  One-time ShahGrid server bootstrap (Windows, native - no Docker, no nginx).

.DESCRIPTION
  Idempotent. Safe to re-run. Steps:
    1. Preflight checks (admin, required binaries, paths, ports).
    2. Tooling: nvm install/use LTS node; fetch NSSM if missing.
    3. Lay down config in E:\apps\shahgrid\shared (Caddyfile, pgbouncer.ini,
       userlist.txt, .env).
    4. Postgres: create role+db, lock to localhost, restart.
    5. pgBouncer service (6432 -> 5432).
    6. First release pull (backend+frontend) + junction `current`.
    7. Register backend + Caddy as auto-start services (LocalSystem -> run with
       no user logged in).
    8. Open firewall 80/443, then a full verification pass (PASS/FAIL table).

.PARAMETER DbPassword
  Password for the app's Postgres role 'shahgrid'. Must match .env.

.PARAMETER PgSuperPassword
  Password for the Postgres superuser 'postgres' (installer value).

.EXAMPLE
  # From an elevated PowerShell, inside the repo's deploy\windows folder:
  .\setup.ps1
#>
[CmdletBinding()]
param(
    [string]$DbPassword      = 'djsfklasjdfksdajf',
    [string]$PgSuperPassword = 'StrongPassword@9'
)

. "$PSScriptRoot\lib\common.ps1"
Assert-Admin
New-Dirs

$ScriptDir = $PSScriptRoot   # repo deploy\windows (source of config templates)

# -- 1. Preflight -------------------------------------------------------------
Write-Step "Preflight checks"
$fatal = @()
if (-not (Test-Path $SG.NvmHome))  { $fatal += "nvm not found at $($SG.NvmHome)" }
if (-not (Test-Path $SG.PgBin))    { $fatal += "Postgres bin not found at $($SG.PgBin)" }
if (-not (Test-Path $SG.CaddyExe)) { $fatal += "Caddy exe not found at $($SG.CaddyExe)" }
if (-not (Test-Path $SG.PgBouncerExe)) {
    $fatal += "pgBouncer not found at $($SG.PgBouncerExe). Download the Windows build, place pgbouncer.exe (and its DLLs) there. https://www.pgbouncer.org/downloads/"
}
if ($fatal.Count) { $fatal | ForEach-Object { Write-Err $_ }; throw "Fix the above and re-run." }
Write-Ok "required binaries present"

# DNS sanity (non-fatal).
try {
    $ips = [System.Net.Dns]::GetHostAddresses($SG.Domain) | ForEach-Object { $_.IPAddressToString }
    Write-Info "$($SG.Domain) resolves to: $($ips -join ', ')"
} catch { Write-Warn "could not resolve $($SG.Domain) - DNS must point at this server for TLS to issue." }

# -- 2. Tooling: node (nvm) + NSSM --------------------------------------------
Write-Step "Node via nvm (LTS)"
$nvm = Join-Path $SG.NvmHome 'nvm.exe'
& $nvm install lts | Write-Info
& $nvm use lts | Write-Info

$env:Path = $SG.NvmHome + ";" + $env:Path
$nodeExe = Get-NodeExe
# Put the resolved node dir (where npm.cmd/npx.cmd also live) first on PATH.
$env:Path = (Split-Path $nodeExe) + ";" + $env:Path
$nodeVer = & $nodeExe -v
Write-Ok "node: $nodeExe ($nodeVer)"

Write-Step "NSSM"
if (-not (Test-Path $SG.NssmExe)) {
    $zip = Join-Path $SG.Tools 'nssm.zip'
    Save-File 'https://nssm.cc/release/nssm-2.24.zip' $zip
    Expand-Archive -Path $zip -DestinationPath $SG.Tools -Force
    Copy-Item (Join-Path $SG.Tools 'nssm-2.24\win64\nssm.exe') $SG.NssmExe -Force
}
Write-Ok "nssm: $($SG.NssmExe)"

# -- 3. Config files into shared\ ---------------------------------------------
Write-Step "Config"
Copy-Item (Join-Path $ScriptDir 'Caddyfile')     (Join-Path $SG.Shared 'Caddyfile')     -Force
Copy-Item (Join-Path $ScriptDir 'pgbouncer.ini') (Join-Path $SG.Shared 'pgbouncer.ini') -Force
Write-Ok "Caddyfile + pgbouncer.ini copied to $($SG.Shared)"

# userlist.txt (plaintext password - restrict ACL to SYSTEM/Administrators).
$userlist = Join-Path $SG.Shared 'userlist.txt'
Set-Content -Path $userlist -Value "`"shahgrid`" `"$DbPassword`""
icacls $userlist /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Ok "userlist.txt written + locked down"

# .env - keep an existing one (it has real secrets); otherwise seed from example.
$envFile = Join-Path $SG.Shared '.env'
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $ScriptDir 'env.server.example') $envFile -Force
    Write-Warn ".env created from template at $envFile - EDIT IT and fill JWT/Google secrets, then re-run."
} else {
    Write-Ok ".env already present (left untouched)"
}

# -- 4. Postgres: role + db + localhost lockdown ------------------------------
Write-Step "Postgres"
$psql = Join-Path $SG.PgBin 'psql.exe'
$pgSvc = (Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $pgSvc) { throw "Postgres service not found (expected name like postgresql-x64-16)." }

$env:PGPASSWORD = $PgSuperPassword
$createRole = @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='shahgrid') THEN
    CREATE ROLE shahgrid LOGIN PASSWORD '$DbPassword';
  ELSE
    ALTER ROLE shahgrid LOGIN PASSWORD '$DbPassword';
  END IF;
END `$`$;
"@
& $psql -U postgres -h 127.0.0.1 -p $SG.PgPort -d postgres -v ON_ERROR_STOP=1 -c $createRole | Out-Null
$dbExists = (& $psql -U postgres -h 127.0.0.1 -p $SG.PgPort -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='shahgrid'") | Out-String
if ($dbExists.Trim() -ne '1') {
    & $psql -U postgres -h 127.0.0.1 -p $SG.PgPort -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE shahgrid OWNER shahgrid" | Out-Null
    Write-Ok "database 'shahgrid' created"
} else { Write-Ok "database 'shahgrid' exists" }

# Bind to localhost only, then restart so it takes effect.
& $psql -U postgres -h 127.0.0.1 -p $SG.PgPort -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET listen_addresses = 'localhost'" | Out-Null
Remove-Item Env:\PGPASSWORD
Restart-Service -Name $pgSvc.Name -Force
Write-Ok "Postgres bound to localhost + restarted ($($pgSvc.Name))"

# -- 5. pgBouncer service -----------------------------------------------------
Write-Step "pgBouncer service"
$pgBouncerIni = Join-Path $SG.Shared 'pgbouncer.ini'
Install-NssmService -Name $SG.Svc.PgBouncer -Exe $SG.PgBouncerExe `
    -Args "pgbouncer.ini" -WorkDir $SG.Shared `
    -StdoutLog (Join-Path $SG.Logs 'pgbouncer.out.log') -StderrLog (Join-Path $SG.Logs 'pgbouncer.err.log')
Start-Service $SG.Svc.PgBouncer
Write-Ok "pgBouncer up on 127.0.0.1:$($SG.PgBouncerPort)"

# -- 6. First release pull + junction -----------------------------------------
Write-Step "First release"
$rel = Get-LatestRelease
$tagName = $rel.Tag
Write-Ok "latest release: $tagName"
$releaseDir = Join-Path $SG.Releases $tagName
$beDir = Join-Path $releaseDir 'backend'
$feDir = Join-Path $releaseDir 'frontend'
$tmp = Join-Path $SG.State 'dl'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $releaseDir, $tmp -Force | Out-Null

$ba = Find-Asset $rel.Assets 'backend-';  $bz = Join-Path $tmp $ba.Name; Save-File $ba.Url $bz; Expand-Zip $bz $beDir
$fa = Find-Asset $rel.Assets 'frontend-'; $fz = Join-Path $tmp $fa.Name; Save-File $fa.Url $fz; Expand-Zip $fz $feDir
if (-not (Test-Path (Join-Path $feDir 'web\index.html'))) { throw "frontend zip missing web\index.html" }

Copy-Item $envFile (Join-Path $beDir '.env') -Force
Initialize-Backend $beDir
Set-CurrentJunction $releaseDir
Set-StateValue 'current_tag' $tagName

# -- 7. Backend + Caddy services ----------------------------------------------
Write-Step "App services"
Install-NssmService -Name $SG.Svc.Backend -Exe $nodeExe -Args 'dist\server.js' `
    -WorkDir (Join-Path $SG.Current 'backend') `
    -StdoutLog (Join-Path $SG.Logs 'backend.out.log') -StderrLog (Join-Path $SG.Logs 'backend.err.log')
Start-Service $SG.Svc.Backend

$caddyFile = Join-Path $SG.Shared 'Caddyfile'
Install-NssmService -Name $SG.Svc.Caddy -Exe $SG.CaddyExe `
    -Args "run --config Caddyfile --adapter caddyfile" -WorkDir $SG.Shared `
    -StdoutLog (Join-Path $SG.Logs 'caddy.out.log') -StderrLog (Join-Path $SG.Logs 'caddy.err.log')
Start-Service $SG.Svc.Caddy

# -- 8. Firewall + verification -----------------------------------------------
Write-Step "Firewall"
foreach ($p in 80, 443) {
    if (-not (Get-NetFirewallRule -DisplayName "ShahGrid HTTP $p" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "ShahGrid HTTP $p" -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $p | Out-Null
    }
}
Write-Ok "inbound 80 + 443 allowed"

Write-Step "Verification"
$checks = [ordered]@{}
$checks['postgres service']  = ((Get-Service $pgSvc.Name).Status -eq 'Running')
$checks['pgbouncer service'] = ((Get-Service $SG.Svc.PgBouncer).Status -eq 'Running')
$checks['backend service']   = ((Get-Service $SG.Svc.Backend).Status -eq 'Running')
$checks['caddy service']     = ((Get-Service $SG.Svc.Caddy).Status -eq 'Running')

function Test-LocalhostOnly([int]$port) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) { return $false }
    foreach ($c in $conns) {
        if ($c.LocalAddress -in @('0.0.0.0', '::')) { return $false }  # publicly bound = fail
    }
    return $true
}
$checks['postgres localhost-only (5432)']  = (Test-LocalhostOnly $SG.PgPort)
$checks['pgbouncer localhost-only (6432)'] = (Test-LocalhostOnly $SG.PgBouncerPort)
$checks['https /health == ok']             = (Test-Health 12 5)
try {
    $home = Invoke-WebRequest -Uri "https://$($SG.Domain)/" -TimeoutSec 15 -UseBasicParsing
    $checks['https / serves flutter app'] = ($home.Content -match 'flutter')
} catch { $checks['https / serves flutter app'] = $false }

Write-Host ""
Write-Host "  RESULT                               STATUS" -ForegroundColor White
Write-Host "  ------------------------------------ ------"
$allOk = $true
foreach ($k in $checks.Keys) {
    $ok = [bool]$checks[$k]
    if (-not $ok) { $allOk = $false }
    $label = $k.PadRight(36)
    $tag   = if ($ok) { 'PASS' } else { 'FAIL' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host "  $label $tag" -ForegroundColor $color
}
Write-Host ""
if ($allOk) {
    Write-Ok "ShahGrid is live: https://$($SG.Domain)  (release $tagName)"
} else {
    Write-Err "Some checks failed. See logs in $($SG.Logs). First TLS issuance can take ~1 min - re-run Verification if only the https checks failed."
}
