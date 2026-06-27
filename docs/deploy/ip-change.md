# When the server's public IP changes

The whole stack is addressed by the **domain** `app.shahgrid.com`, never by a
hardcoded IP. The TLS cert, the API URL baked into the frontend, the Google
OAuth callback, and CORS are all domain-based. So an IP change needs **no app or
cert change** — only DNS and the router.

Current values: domain `app.shahgrid.com`, old IP `45.251.14.22`.

## Steps

1. **Update the DNS A record** at your domain registrar / DNS provider:
   - `app.shahgrid.com  A  <NEW_IP>`
   - Lower the TTL beforehand (e.g. 300s) if you know a change is coming, so it
     propagates fast.

2. **Re-point the router / firewall** at the new server (if the box itself moved
   or its LAN IP changed): forward inbound **TCP 80 and 443** to the server.
   Port 80 is needed for Let's Encrypt renewal (HTTP-01) and the HTTP→HTTPS
   redirect; 443 for traffic.

3. **Verify propagation**, then confirm:
   ```powershell
   Resolve-DnsName app.shahgrid.com          # should show <NEW_IP>
   Invoke-RestMethod https://app.shahgrid.com/health   # { status = ok }
   ```

That's it. Caddy keeps the existing certificate and will auto-renew as long as
port 80/443 reach the server on the new IP.

## What you do NOT need to touch

- `.env` — no IP in it (all `https://app.shahgrid.com/...`).
- The frontend build — API URL is the domain.
- Google OAuth — callback is `https://app.shahgrid.com/api/v1/auth/google/callback`.
- The TLS certificate — tied to the domain, not the IP.

## Only if you also change the DOMAIN (not just IP)

That is a bigger change (new cert + rebuilds). You would:
1. Update DNS for the new domain → server IP.
2. Edit `shared\Caddyfile` (site name + log) and `Restart-Service shahgrid-caddy`
   (Caddy issues a fresh cert automatically).
3. Edit `shared\.env`: `FRONTEND_URL`, `GOOGLE_CALLBACK_URL`; update the Google
   Cloud OAuth authorized redirect URI.
4. Rebuild the frontend with the new API URL and release:
   `release.ps1 -Tag <new> -ApiBaseUrl https://<new-domain>/api/v1`, then
   `update.ps1` on the server.
