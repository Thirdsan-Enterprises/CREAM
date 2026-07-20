# Cream POS

Custom point-of-sale and stock management system for **Cream Restaurant & Catering Services** — *"we serve beyond your desire"* — a Kampala-based restaurant operating three outlets: **Kira (Main/Warehouse)**, **Lugogo**, and **Town**.

Built by [Thirdsan Enterprises](https://github.com/Thirdsan-Enterprises) as a bespoke system modeled directly on how Cream operates, not a configured off-the-shelf product. See [`CLAUDE.md`](./CLAUDE.md) for the full product/business specification this build follows.

## What this system does

- **Stock**: purchasing at Kira, transfers to outlets with a dispatch/confirm workflow, per-store safety stock and re-order status, drinks stocked locally at every outlet.
- **Sales**: daily plate sales (fixed price, editable) plus optional priced drinks, cash/MoMo/Airtel/account payment.
- **Catering**: a fully separate revenue stream — tiered packages, quote → confirm → deliver → settle, deposits tracked against a total.
- **Customer accounts**: prepaid (top up, deduct) and credit (spend now, settle later against a limit) on one ledger mechanism.
- **Reports**: cross-store dashboard, stock status, outstanding credit, catering pipeline.
- **Roles**: Admin (all stores), Store Manager, Cashier, Storekeeper — enforced server-side, not just in the UI.

## Repository layout

```
backend/    Laravel API (PHP 8.4, MySQL, Sanctum token auth)
mobile/     Flutter app, single codebase for Android + iOS (Riverpod, dio)
CLAUDE.md   Full product specification and build order
```

## Backend

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan serve
```

Run tests: `php artisan test`

### Docker

The backend ships with a `Dockerfile` and `docker-compose.yml` for VPS deployment (nginx + php-fpm behind Supervisor in one image, MySQL as a sidecar service). See `backend/docker/` for the nginx/supervisor config and `backend/docker-compose.yml` for the service definitions.

## Mobile

```bash
cd mobile
flutter pub get
flutter run
```

A single Flutter app: after login, the UI adapts based on role and assigned store — Admin gets a Back Office experience with a store switcher, everyone else is locked to their own store's Outlet Terminal.

## CI/CD

GitHub Actions workflows live in [`.github/workflows`](./.github/workflows):

| Workflow | Trigger | What it does |
|---|---|---|
| `backend-tests.yml` | push/PR touching `backend/**` | Runs the Laravel test suite on PHP 8.4 and 8.5 |
| `backend-deploy.yml` | push to `main` touching `backend/**` | Builds the backend Docker image, pushes to GHCR, deploys to the VPS over SSH |
| `flutter-build.yml` | push/PR touching `mobile/**` | Builds a signed, split-per-ABI release APK and uploads it as a workflow artifact for direct install/testing |

The backend is deployed at `cream.thirdsan.com`, proxied by the VPS's own nginx to the app container on `127.0.0.1:9080`.

## Tech stack

- **Backend**: Laravel (latest LTS), MySQL, Sanctum, Docker, Nginx, GitHub Actions
- **Mobile**: Flutter (stable channel), Riverpod, `dio`, `flutter_secure_storage`
- **Scope for this phase**: online-first with short-blip tolerance (queued retry on brief network drops), not full offline-first sync — see `CLAUDE.md` §7 and §9 for what's explicitly out of scope.

## Status

All nine build-order milestones in `CLAUDE.md` §10 are implemented: backend auth/stock/transfers/sales/catering/customers/reports, and the mobile Outlet Terminal + Back Office. See commit history for the milestone-by-milestone build.
