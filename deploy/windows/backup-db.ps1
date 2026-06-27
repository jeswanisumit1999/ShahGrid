<#
.SYNOPSIS
  Back up the ShahGrid Postgres database to a compressed dump, with retention.

.DESCRIPTION
  Uses pg_dump custom format (-Fc) against the DIRECT Postgres port (5432).
  Writes to E:\apps\shahgrid\backups\shahgrid-<timestamp>.dump and prunes dumps
  older than -KeepDays. Intended to run from a Scheduled Task (see
  docs/deploy/backup-restore.md) or by hand.

.PARAMETER KeepDays
  Delete dumps older than this many days. Default 14.

.PARAMETER DbPassword
  Password for role 'shahgrid'. Default matches setup.ps1.

.EXAMPLE
  .\backup-db.ps1
  .\backup-db.ps1 -KeepDays 30
#>
[CmdletBinding()]
param(
    [int]$KeepDays = 14,
    [string]$DbPassword = 'djsfklasjdfksdajf'
)

. "$PSScriptRoot\lib\common.ps1"

$backupDir = Join-Path $SG.Root 'backups'
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

$pgDump = Join-Path $SG.PgBin 'pg_dump.exe'
if (-not (Test-Path $pgDump)) { throw "pg_dump not found at $pgDump" }

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$out   = Join-Path $backupDir "shahgrid-$stamp.dump"

Write-Step "Backing up shahgrid -> $out"
$env:PGPASSWORD = $DbPassword
try {
    & $pgDump -h 127.0.0.1 -p $SG.PgPort -U shahgrid -d shahgrid -Fc -f $out
    if ($LASTEXITCODE -ne 0) { throw "pg_dump exited $LASTEXITCODE" }
} finally {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}
$sizeMB = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Ok "backup complete ($sizeMB MB)"

Write-Step "Pruning dumps older than $KeepDays days"
$cut = (Get-Date).AddDays(-$KeepDays)
Get-ChildItem $backupDir -Filter 'shahgrid-*.dump' |
    Where-Object { $_.LastWriteTime -lt $cut } |
    ForEach-Object { Remove-Item $_.FullName -Force; Write-Info "removed $($_.Name)" }
Write-Ok "retention applied"
