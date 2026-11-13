# Deploying AgroBenta to one server

This runs the whole stack on a single Linux server (for example AWS EC2) with
Docker Compose. Code arrives with `git pull`; secrets are copied once by hand.

```
Internet ──► Caddy :80/:443 (HTTPS)
               ├─ /api, /broadcasting, /storage ──► nginx ──► PHP-FPM (Laravel)
               ├─ /app (WebSockets) ─────────────► Reverb
               └─ everything else ───────────────► frontend/dist (Admin Web)
            MySQL, Redis, ml-service, queue: internal network only
```

Files: `compose.prod.yaml` (production overrides on top of `compose.yaml`),
`docker/caddy/Caddyfile`, `deploy.sh`.

## Server requirements

- At least **4 GB RAM** (MySQL is killed for lack of memory on 1 GB).
- Docker Engine with the Compose plugin (`curl -fsSL https://get.docker.com | sudo sh`).
- Firewall / security group inbound: **22** (your IP only), **80**, **443**.
  Nothing else; MySQL, nginx and Reverb publish no ports in production.
- A DNS `A` record for the domain pointing at the server.

## First deployment

1. Clone: `git clone https://github.com/roxcy1/AgroBenta.git && cd AgroBenta`
2. Create the two env files from their examples (never commit them):
   - `.env`: `DB_*` passwords and `SITE_DOMAIN` (for example `agrobenta.com`).
   - `backend/.env`: `APP_ENV=production`, `APP_DEBUG=false`,
     `APP_URL=https://<domain>`, the same `DB_PASSWORD`, real `REVERB_APP_*`
     values, `QUEUE_CONNECTION=redis`, mail (SMTP), `ADMIN_*`,
     `GOOGLE_CLIENT_ID`, `FCM_CREDENTIALS`.
3. Copy the Firebase service account key to `backend/storage/app/firebase/`
   (for example with `scp`).
4. Run `./deploy.sh`. On first run Caddy obtains the HTTPS certificate, which
   needs the DNS record to point at the server already.
5. Create the administrator and default settings, once:

   ```sh
   C="docker compose -f compose.yaml -f compose.prod.yaml"
   $C exec -u www-data php php artisan optimize:clear
   $C exec -u www-data php php artisan db:seed --class=AdminSeeder --force
   $C exec -u www-data php php artisan db:seed --class=SettingsSeeder --force
   $C exec -u www-data php php artisan optimize
   ```

   Clear the cache first: with cached config the seeder cannot read
   `ADMIN_EMAIL`/`ADMIN_PASSWORD`. Do not run plain `db:seed` or the demo
   seeders on a real server.

## Updating

```sh
cd ~/AgroBenta
git pull origin main && ./deploy.sh
```

`deploy.sh` builds the images, installs PHP packages without dev tools,
migrates, caches Laravel, builds the Admin Web for `https://SITE_DOMAIN`, and
restarts the queue worker and Reverb. After changing `backend/.env`, run it
again (or `artisan optimize`), because the cached config ignores `.env`.

## Publishing the mobile app

The home page's Download button and the app's Profile → App Update read the
latest release from `GET /api/app-release`. To publish a build (see
`mobile/README.md`, "Release builds and app updates", for building it):

```sh
# On your PC: copy the APK to the server.
scp -i <key.pem> mobile/build/app/outputs/flutter-apk/app-release.apk ubuntu@<server>:/tmp/

# On the server: hand it to Laravel and publish it.
cd ~/AgroBenta
C="docker compose -f compose.yaml -f compose.prod.yaml"
$C cp /tmp/app-release.apk php:/tmp/app-release.apk
$C exec -u www-data php php artisan app:publish-release /tmp/app-release.apk \
    --version-name=1.0.1 --version-code=2 --notes="What changed, in one line."
$C exec php rm /tmp/app-release.apk && rm /tmp/app-release.apk
```

The name and code must match `version:` in `mobile/pubspec.yaml` (`1.0.1+2`).
The command refuses a file that is not an APK and a code that is not higher
than the current release. The APK is stored in
`backend/storage/app/public/releases/` and served at
`https://<domain>/storage/releases/...`; older files are kept for rollback.

## Cloudflare

Start with the DNS records as **DNS only** (grey cloud) so Caddy can get its
certificate. Once `https://<domain>` works, switch them to **Proxied** and set
**SSL/TLS** to **Full (strict)**. Never use Flexible: it causes a redirect
loop. Caddy already reads the visitor's IP from `CF-Connecting-IP`, trusting
only Cloudflare's address ranges.

## Running commands

Run artisan as `www-data` so the files it creates stay writable by PHP:

```sh
docker compose -f compose.yaml -f compose.prod.yaml exec -u www-data php php artisan <command>
docker compose -f compose.yaml -f compose.prod.yaml logs -f php queue caddy
```

The mobile app must be built against `https://<domain>/api` and
`wss://<domain>` (port 443).
