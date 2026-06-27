# Deploy a frontend (Flutter web) change

The frontend is a static Flutter web build. Its API URL is **baked in at build
time** (`--dart-define=API_BASE_URL`), so it is built on your local machine and
shipped as a GitHub Release asset.

## On your local machine

1. Make + test your Flutter changes under `Frontend/shah_grid`.
2. Commit/push as usual.
3. Build + publish a release (frontend only):
   ```bash
   # macOS / Linux:
   ./deploy/windows/release.sh -t v1.2.1 --skip-backend -n "UI: <what changed>"
   ```
   ```powershell
   # Windows:
   pwsh ./deploy/windows/release.ps1 -Tag v1.2.1 -SkipBackend -Notes "UI: <what changed>"
   ```
   This runs `flutter build web --release --dart-define=API_BASE_URL=https://app.shahgrid.com/api/v1`,
   zips `build/web` into `frontend-v1.2.1.zip`, and attaches it to GitHub Release
   `v1.2.1`.

> Always bump `-Tag`. The server pulls the **latest** release, and a release tag
> must be unique.

## On the server

```powershell
cd E:\apps\shahgrid-repo\deploy\windows
.\update.ps1 -FrontendOnly
```

`update.ps1` downloads the frontend zip, extracts it into the new release
folder, reuses the current backend, flips the `current` junction, reloads Caddy,
and verifies `/health`. On a failed health check it auto-rolls-back.

## Verify

```powershell
Invoke-WebRequest https://app.shahgrid.com/ -UseBasicParsing | Select-Object -Expand Content | Select-String flutter
```
Then hard-refresh the browser (Flutter web ships a service worker; Ctrl-Shift-R
or clear site data if you see a stale build).

## Notes

- No server-side build tools are used — the server only unzips static files.
- If you changed the API URL/domain, you must rebuild (the URL is compiled in)
  and also update backend `.env` / Google OAuth — see
  [ip-change.md](ip-change.md) "Only if you also change the DOMAIN".
