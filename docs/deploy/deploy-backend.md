# Deploy a backend (Node/TypeScript) change

The backend ships as a compiled `dist/` plus `prisma/` and the package manifest.
The server runs `npm ci` + `prisma generate` + `prisma migrate deploy` on pull,
so it needs Node (it has nvm LTS) but **no TypeScript/build toolchain**.

## On your local machine

1. Make + test changes under `Backend/`.
2. If you changed the Prisma schema, first follow
   [db-structure-change.md](db-structure-change.md) to create the migration.
3. Commit/push, then build + publish (backend only):
   ```bash
   # macOS / Linux:
   ./deploy/windows/release.sh -t v1.2.2 --skip-frontend -n "API: <what changed>"
   ```
   ```powershell
   # Windows:
   pwsh ./deploy/windows/release.ps1 -Tag v1.2.2 -SkipFrontend -Notes "API: <what changed>"
   ```
   This runs `npm ci` + `npm run build` (tsc) and zips `dist/ + prisma/ +
   package.json + package-lock.json` into `backend-v1.2.2.zip`.
   `node_modules` is **not** shipped — the server installs it.

## On the server

```powershell
cd E:\apps\shahgrid-repo\deploy\windows
.\update.ps1 -BackendOnly
```

This downloads + extracts the backend, copies `shared\.env` into it, runs
`npm ci` → `prisma generate` → `prisma migrate deploy`, flips `current`, restarts
`shahgrid-backend`, and verifies `/health`. Failed health check → auto-rollback.

## Verify

```powershell
Invoke-RestMethod https://app.shahgrid.com/health        # { status = ok }
Get-Content E:\apps\shahgrid\logs\backend.err.log -Tail 40
```

## Notes

- The backend listens on `127.0.0.1:3000`; only Caddy reaches it. Test the public
  surface via `https://app.shahgrid.com/api/v1/...`.
- Secrets live only in `E:\apps\shahgrid\shared\.env`; releases never contain it.
- `npm ci` needs internet (npm registry + Prisma engine download). No compiler
  is required.
