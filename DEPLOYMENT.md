# Deploying Cream POS

## Backend: cream.thirdsan.com on the Contabo VPS

### One-time VPS setup

1. **DNS** — create an A record: `cream.thirdsan.com` → the VPS's public IP.
2. **Clone the repo** on the VPS somewhere stable, e.g. `/srv/cream`:
   ```
   git clone <repo-url> /srv/cream
   cd /srv/cream/backend
   ```
3. **Create `backend/.env`** on the VPS (never committed — copy `.env.example` as
   a starting point and fill in real values):
   ```
   APP_ENV=production
   APP_DEBUG=false
   APP_URL=https://cream.thirdsan.com
   APP_KEY=            # fill in after first boot, see below

   DB_CONNECTION=mysql
   DB_HOST=db
   DB_PORT=3306
   DB_DATABASE=cream
   DB_USERNAME=cream
   DB_PASSWORD=<strong password>
   DB_ROOT_PASSWORD=<different strong password>   # mysql container root password, compose-only
   ```
4. **First boot**:
   ```
   docker compose build
   docker compose up -d
   docker compose exec app php artisan key:generate
   docker compose exec app php artisan migrate --force
   docker compose exec app php artisan db:seed --force   # ONE TIME ONLY — see warning below
   ```
5. **Host Nginx + TLS** — copy `backend/docker/host-nginx-cream.thirdsan.com.conf`
   to `/etc/nginx/sites-available/cream.thirdsan.com` on the VPS, symlink it
   into `sites-enabled`, then:
   ```
   certbot --nginx -d cream.thirdsan.com
   nginx -t && systemctl reload nginx
   ```

**⚠️ Never re-run `db:seed` against production after go-live.** The seeder
creates the stores, the admin user, and the drink/catering catalog — running
it again would duplicate or reset that data. Real stock balances come only
from actual purchase/transfer/consumption entries made through the app, never
from seeding. After the initial seed, ongoing deploys only run `migrate`.

### Ongoing deploys

Handled by `.github/workflows/backend.yml`: every push to `main` that touches
`backend/**` runs the test suite, and on success SSHes into the VPS to
`git reset --hard origin/main`, rebuild the `app` container, and run
`migrate --force` (no seeding). Required GitHub repo secrets:

| Secret | Value |
|---|---|
| `VPS_HOST` | VPS IP or hostname |
| `VPS_USER` | SSH user with docker access |
| `VPS_SSH_KEY` | Private key for that user (add the matching public key to the VPS's `authorized_keys`) |
| `VPS_APP_PATH` | e.g. `/srv/cream` |

The VPS clone is deploy-only — nobody should hand-edit files there, since
each deploy hard-resets it to match `origin/main`.

## Mobile: Android test artifacts

`.github/workflows/mobile-android.yml` builds a release APK on every push
that touches `mobile/**` (and can be triggered manually via "Run workflow"
in the Actions tab, with a custom API URL if you want to point at a
non-default backend). It's signed with Flutter's default debug key, which is
fine for sideloading onto a test device but is **not** a Play Store-ready
build — a real release keystore is a separate step for when the app is
ready to publish.

To get a build: open the workflow run in GitHub Actions → **Artifacts** →
download `cream-pos-android-<run number>`, unzip, and install the APK on a
test device (`adb install app-release.apk`, or transfer it and allow
"install unknown apps").

## Why the mobile app doesn't need a "seed data" step

The Flutter app has no local database or bundled mock data — the only thing
it persists on-device is the auth token (`flutter_secure_storage`). Every
screen fetches its data live from the Laravel API on load
(`ref.read(...Repository()).fetch()`), so a freshly installed app is a blank
shell until it logs in and pulls real data from `cream.thirdsan.com`. There is
nothing to keep in sync between the app and the backend by design — the API
is the only source of truth, always. The one thing to build at build time is
`API_BASE_URL` (via `--dart-define`), which both workflows above already set
to the production subdomain by default.
