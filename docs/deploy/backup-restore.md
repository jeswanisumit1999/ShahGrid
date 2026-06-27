# Backup & restore Postgres

Backups use `pg_dump` custom format (`-Fc`) — compressed, and restorable
selectively with `pg_restore`. Dumps go to `E:\apps\shahgrid\backups\`.

## Manual backup

```powershell
cd E:\apps\shahgrid-repo\deploy\windows
.\backup-db.ps1                 # -> backups\shahgrid-<timestamp>.dump, prunes >14 days
.\backup-db.ps1 -KeepDays 30    # keep a month
```

## Scheduled daily backup (runs without anyone logged in)

Register a Scheduled Task as SYSTEM, 2:30am daily:

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File E:\apps\shahgrid-repo\deploy\windows\backup-db.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 2:30am
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'ShahGrid-DB-Backup' -Action $action -Trigger $trigger -Principal $principal
```

Verify / run on demand:
```powershell
Get-ScheduledTask -TaskName 'ShahGrid-DB-Backup'
Start-ScheduledTask -TaskName 'ShahGrid-DB-Backup'
```

> Copy `E:\apps\shahgrid\backups\` off-box regularly (another drive / cloud).
> A backup on the same machine does not survive a disk failure.

## Restore

Stop the backend so nothing writes during restore:

```powershell
Stop-Service shahgrid-backend
```

### Restore into a fresh database (safest — verify, then switch)

```powershell
$env:PGPASSWORD = 'StrongPassword@9'      # postgres superuser
$bin = 'E:\apps\PostgreSQL\16\bin'
& "$bin\psql.exe"  -U postgres -h 127.0.0.1 -p 5432 -c "CREATE DATABASE shahgrid_restore OWNER shahgrid"
& "$bin\pg_restore.exe" -U postgres -h 127.0.0.1 -p 5432 -d shahgrid_restore --no-owner `
    "E:\apps\shahgrid\backups\shahgrid-<timestamp>.dump"
Remove-Item Env:\PGPASSWORD
```
Inspect `shahgrid_restore`; when happy, repoint the app (rename DBs) or restore
in place (below).

### Restore in place (overwrites current data)

```powershell
$env:PGPASSWORD = 'StrongPassword@9'
$bin = 'E:\apps\PostgreSQL\16\bin'
# --clean --if-exists drops existing objects before recreating them.
& "$bin\pg_restore.exe" -U postgres -h 127.0.0.1 -p 5432 -d shahgrid --clean --if-exists --no-owner `
    "E:\apps\shahgrid\backups\shahgrid-<timestamp>.dump"
Remove-Item Env:\PGPASSWORD
```

Then restart:
```powershell
Start-Service shahgrid-backend
Invoke-RestMethod https://app.shahgrid.com/health
```

## Notes

- Restores connect to the **direct** port 5432, not pgBouncer (6432).
- Take a fresh `backup-db.ps1` immediately **before** any in-place restore or
  destructive migration.
