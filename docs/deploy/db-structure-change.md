# Changing the database structure (Prisma migrations)

ShahGrid uses Prisma. Schema lives at `Backend/prisma/schema.prisma`; migrations
in `Backend/prisma/migrations/`. **Always create migrations locally**, commit
them, and let the server apply them with `migrate deploy` (never `migrate dev` on
the server).

## Why two database URLs

pgBouncer runs in **transaction pooling** mode, which can't run schema
migrations or prepared statements. So `schema.prisma` has:

```prisma
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")          // pooled 6432 (app runtime, ?pgbouncer=true)
  directUrl = env("DIRECT_DATABASE_URL")   // direct 5432 (migrations / generate)
}
```

`prisma migrate` and `prisma generate` use `DIRECT_DATABASE_URL` (5432); the
running app uses the pooled `DATABASE_URL` (6432). Both are set in
`shared\.env`.

## On your local machine

1. Edit `Backend/prisma/schema.prisma`.
2. Create the migration against your local/dev DB:
   ```bash
   cd Backend
   npx prisma migrate dev --name <change_description>
   ```
   This writes a new folder under `prisma/migrations/` and regenerates the client.
3. Review + **commit** the new migration folder (the SQL is what production runs).
4. Publish a backend release:
   ```bash
   # macOS / Linux:
   ./deploy/windows/release.sh -t v1.3.0 --skip-frontend -n "db: <change>"
   ```
   ```powershell
   # Windows:
   pwsh ./deploy/windows/release.ps1 -Tag v1.3.0 -SkipFrontend -Notes "db: <change>"
   ```

## On the server

```powershell
cd E:\apps\shahgrid-repo\deploy\windows
.\update.ps1 -BackendOnly
```

`update.ps1` runs `npx prisma migrate deploy`, which applies only the new,
committed migrations through the **direct** 5432 connection. It then restarts the
backend.

## Safety

- **Back up first** for destructive changes — see [backup-restore.md](backup-restore.md).
- `migrate deploy` never resets data; it applies pending migrations in order.
- Prefer additive, backward-compatible migrations (add column/table) so the old
  running backend keeps working until the new one starts. For renames/drops,
  do it in two releases (add new → migrate data → drop old) to avoid downtime.
- If a migration fails, `update.ps1`'s health check fails and the junction rolls
  back — but a partially-applied DDL is not auto-reverted. Check
  `npx prisma migrate status` (run from the release's backend dir) and the
  backup before retrying.
