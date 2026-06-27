# Troubleshooting

## First, look here

```powershell
Get-Service shahgrid-*, postgresql-x64-16          # are they Running?
Get-Content E:\apps\shahgrid\logs\backend.err.log -Tail 50
Get-Content E:\apps\shahgrid\logs\caddy.err.log    -Tail 50
Get-Content E:\apps\shahgrid\logs\pgbouncer.err.log -Tail 50
Invoke-RestMethod https://app.shahgrid.com/health
```

Active release + ports:
```powershell
Get-Content E:\apps\shahgrid\state\current_tag.txt
Get-NetTCPConnection -LocalPort 3000,5432,6432,443 -State Listen | Format-Table LocalAddress,LocalPort,State
```

## Symptoms

### Site won't load / TLS error
- Caddy needs ports **80 and 443** reachable to issue/renew the cert. Check the
  router forward and the firewall rules (`Get-NetFirewallRule -DisplayName "ShahGrid*"`).
- DNS must point at this server: `Resolve-DnsName app.shahgrid.com`.
- First issuance takes ~30–60s. Watch: `Get-Content ...\logs\caddy.err.log -Tail 50 -Wait`.
- Restart edge: `Restart-Service shahgrid-caddy`.

### 502 / API calls fail, site loads
- Backend down or unhealthy: `Get-Service shahgrid-backend`,
  `...\logs\backend.err.log`.
- Common cause: bad `.env` (env validation `process.exit(1)` on startup — the
  log prints which field). Fix `E:\apps\shahgrid\shared\.env`, then
  `Restart-Service shahgrid-backend`.

### Backend won't start — database errors
- pgBouncer down: `Get-Service shahgrid-pgbouncer`, `...\logs\pgbouncer.err.log`.
- Check the chain directly:
  ```powershell
  $env:PGPASSWORD='djsfklasjdfksdajf'; $bin='E:\apps\PostgreSQL\16\bin'
  & "$bin\psql.exe" -h 127.0.0.1 -p 6432 -U shahgrid -d shahgrid -c "select 1"   # via pgBouncer
  & "$bin\psql.exe" -h 127.0.0.1 -p 5432 -U shahgrid -d shahgrid -c "select 1"   # direct
  Remove-Item Env:\PGPASSWORD
  ```
- `prepared statement already exists` / odd Prisma errors → ensure
  `DATABASE_URL` ends with `?pgbouncer=true` (it disables prepared statements in
  transaction pooling).
- Migrations must use the **direct** URL: `DIRECT_DATABASE_URL` on 5432.

### "Too many requests" (429)
- Edge limit is **500 req/min/IP** in `shared\Caddyfile` (`rate_limit` block).
  Adjust `events` / `window`, then `Restart-Service shahgrid-caddy`.
- The in-app limiter is a looser safety net (1000/min) in `Backend/src/app.ts`.

### Deploy failed / rolled back
- `update.ps1` rolls the `current` junction back on a failed `/health`. Inspect
  `backend.err.log`, fix, re-run `.\update.ps1 -Force`.
- Manual rollback to the previous release:
  ```powershell
  $prev = Get-Content E:\apps\shahgrid\state\previous_tag.txt
  # repoint junction by hand:
  cmd /c rmdir E:\apps\shahgrid\current
  New-Item -ItemType Junction -Path E:\apps\shahgrid\current -Target "E:\apps\shahgrid\releases\$prev"
  Restart-Service shahgrid-backend, shahgrid-caddy
  ```

### Postgres reachable from the network (it must NOT be)
```powershell
Get-NetTCPConnection -LocalPort 5432 -State Listen | Select LocalAddress
```
LocalAddress must be `127.0.0.1` / `::1`, never `0.0.0.0`. If wrong, re-run
`setup.ps1` (it sets `listen_addresses='localhost'` + restarts Postgres).

## Service control cheatsheet

```powershell
Restart-Service shahgrid-backend
Restart-Service shahgrid-caddy
Restart-Service shahgrid-pgbouncer
Restart-Service postgresql-x64-16

# Reconfigure a service (paths/args): re-run setup.ps1, or use nssm directly:
E:\apps\shahgrid\tools\nssm.exe edit shahgrid-backend
```
