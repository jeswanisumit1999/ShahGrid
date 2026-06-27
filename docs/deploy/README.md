# ShahGrid — Windows Server Deployment (native, no Docker / no nginx)

This is the production runbook for the Windows box that serves
**https://app.shahgrid.com**. Everything runs as native Windows services that
auto-start at boot and restart on crash — **no Docker, no nginx, no certbot**.

## Stack

| Layer | What | Where | Port |
|---|---|---|---|
| Edge / TLS | **Caddy** (custom build w/ `caddy-ratelimit`) | `E:\apps\Caddy\caddy_windows_amd64_custom.exe` | 80, 443 |
| Frontend | Flutter **web build** (static), served by Caddy | `E:\apps\shahgrid\current\frontend\web` | (via 443) |
| Backend | **Node/Express** (`dist\server.js`) | `E:\apps\shahgrid\current\backend` | 3000 (localhost) |
| Pooler | **pgBouncer** (transaction mode) | `E:\apps\PgBouncer\bin\pgbouncer.exe` | 6432 (localhost) |
| Database | **PostgreSQL 16** | `E:\apps\PostgreSQL\16` | 5432 (localhost) |
| Node mgr | **nvm-windows** (LTS) | `E:\apps\nvm` | — |

```
Internet ──443/80──> Caddy (auto-TLS + 500 req/min/IP)
                       ├── /api/*, /health, /api-docs  ──> 127.0.0.1:3000  (Node)
                       └── /*  (Flutter SPA static files)
                                                Node ──> 127.0.0.1:6432 (pgBouncer) ──> 127.0.0.1:5432 (Postgres)
```

Postgres and pgBouncer listen on **localhost only** — nothing DB-related is
reachable from the network.

## Why the `current` junction

Build tools (Flutter, tsc) are **not** installed on the server. You build on
your local machine (`release.sh` on macOS/Linux, `release.ps1` on Windows),
publish a **GitHub Release**, and the server pulls it.

Each release is extracted to `E:\apps\shahgrid\releases\<tag>\`. A Windows
**junction** `E:\apps\shahgrid\current` points at the active release. Caddy's web
root and the backend service's working dir both reference `current\...`, so the
host path never changes even though each release lives in its own folder. Swaps
are atomic and reversible (`update.ps1` rolls back on a failed health check).

## Layout on the server

```
E:\apps\shahgrid\
  current\               -> junction to releases\<active tag>
  releases\<tag>\
    backend\   (dist, prisma, package.json, node_modules, .env)
    frontend\web\  (flutter static)
  shared\
    .env             <- the ONLY place you keep real secrets; survives swaps
    Caddyfile
    pgbouncer.ini
    userlist.txt
  logs\    (backend.*.log, caddy.*.log, pgbouncer.*.log)
  state\   (current_tag.txt, previous_tag.txt)
  tools\   (nssm.exe)
```

## Services (NSSM, run as LocalSystem)

| Service | Command |
|---|---|
| `postgresql-x64-16` | installed by the Postgres installer |
| `shahgrid-pgbouncer` | `pgbouncer.exe shared\pgbouncer.ini` |
| `shahgrid-backend` | `node dist\server.js` (cwd `current\backend`) |
| `shahgrid-caddy` | `caddy run --config shared\Caddyfile` |

LocalSystem services **start at boot with no user logged in** and **restart on
crash** (NSSM `AppExit Default Restart`). Manage them:

```powershell
Get-Service shahgrid-*
Restart-Service shahgrid-backend
```

## First-time setup

1. Install prerequisites on the server (one time, manual):
   - nvm-windows at `E:\apps\nvm`
   - PostgreSQL 16 at `E:\apps\PostgreSQL\16` (superuser `postgres` / `StrongPassword@9`)
   - Caddy custom build at `E:\apps\Caddy\caddy_windows_amd64_custom.exe`
   - pgBouncer Windows build at `E:\apps\PgBouncer\bin\pgbouncer.exe`
   - Point DNS **A record** `app.shahgrid.com -> 45.251.14.22`, and forward
     router ports **80 + 443** to this server.
2. Get the repo on the server (public, no login needed):
   ```powershell
   git clone https://github.com/jeswanisumit1999/ShahGrid.git E:\apps\shahgrid-repo
   ```
3. From an **elevated** PowerShell:
   ```powershell
   cd E:\apps\shahgrid-repo\deploy\windows
   .\setup.ps1
   ```
4. If `setup.ps1` reports it created `shared\.env` from the template, **edit
   `E:\apps\shahgrid\shared\.env`** (fill JWT + Google secrets) and re-run
   `.\setup.ps1`. The setup ends with a PASS/FAIL verification table.

> First TLS issuance takes ~30–60s. If only the `https` checks fail on the first
> run, wait a minute and re-run `.\setup.ps1` (idempotent).

## Day-to-day

| Task | Doc |
|---|---|
| Ship a frontend change | [deploy-frontend.md](deploy-frontend.md) |
| Ship a backend change | [deploy-backend.md](deploy-backend.md) |
| Change DB schema (Prisma migration) | [db-structure-change.md](db-structure-change.md) |
| Server public IP changed | [ip-change.md](ip-change.md) |
| Back up / restore Postgres | [backup-restore.md](backup-restore.md) |
| Something is broken | [troubleshooting.md](troubleshooting.md) |

Pull latest release on the server any time:

```powershell
cd E:\apps\shahgrid-repo\deploy\windows
.\update.ps1                 # full (frontend + backend + migrations)
.\update.ps1 -FrontendOnly   # frontend only
.\update.ps1 -BackendOnly    # backend only (runs migrations)
```
