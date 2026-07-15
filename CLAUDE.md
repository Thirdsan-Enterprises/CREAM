# CLAUDE.md — Cream POS (Cream Restaurant & Catering Services)

## 0. Project Summary

Build a **custom, purpose-built POS and stock management system** for **Cream Restaurant & Catering Services** ("we serve beyond your desire"), a Kampala-based restaurant operating three outlets: **Kira (Main/Warehouse)**, **Lugogo**, and **Town**. The system must support adding future outlets without code changes.

This is a **bespoke build**, not a generic POS template. Every feature below is modeled directly on how Cream actually operates today (previously tracked manually / in spreadsheets). Client is a Thirdsan Enterprises custom software client — the deliverable should look and feel tailor-made to Cream, not like a configured off-the-shelf product.

**Deliverables for this phase:**
1. Laravel API backend (single tenant, no multi-tenant abstraction needed)
2. One Flutter codebase → Android + iOS, with role-based experience (Back Office vs Outlet Terminal)
3. No web/desktop frontend in this phase (confirmed with client — desktop comes later)

---

## 1. Business Model Cream Runs (read this before building anything)

- **Kira is the main store.** All purchasing ("Stock In") of food/non-drink stock happens at Kira only.
- Stock is **transferred** from Kira to Lugogo and Town as needed. A transfer has a dispatch step (from Kira) and a confirmation step (at the receiving outlet) — this catches shortages/losses in transit.
- **Drinks are the exception to the Kira-only rule**: each store stocks and buys its own drinks locally (not transferred from Kira) — Stock In for a drink item is allowed directly at any active store, not just Kira.
- Each outlet consumes its own stock daily ("Stock Out") and has its own running **Stock Balance**.
- Each item has a **safety stock** threshold per store. When balance falls at/below it, status = "Re-Order"; otherwise "Stock Sufficient" — mirrors the client's existing Excel tracker exactly, just automated.
- **Daily plate sales**: every outlet sells a standard plate at a fixed price (default **UGX 25,000**, must be editable by Admin, never hardcoded). A **drink is optional and priced separately** — treat drinks as their own priced, stocked items, not bundled into the plate price. Confirmed drink lineup and prices: Passion Juice UGX 5,000, Mocktail UGX 5,000, Bushera UGX 5,000, Eshande UGX 5,000, Soda UGX 2,000, Water UGX 2,000. A single sale can include a plate plus zero or more drinks, each drink tracked and priced individually.
- **Outside catering** is a completely separate revenue stream from daily plate sales — must never mix in reports. Catering has tiered per-plate packages (default UGX 34,000 / 38,000 / 45,000 — configurable, not hardcoded) for events like weddings, graduations, conferences, baby showers, get-togethers. Catering is order/event-based: quote → confirm → deliver → settle, with deposits tracked against a total.
- **Customer accounts**: two account types sharing one ledger mechanism —
  - **Prepaid**: customer deposits money, balance goes up; every meal deducts from balance. Balance cannot go below zero.
  - **Credit**: customer eats now, balance goes negative, settles later. Admin sets a per-customer credit limit; balance cannot exceed that limit (in the negative direction).
- All sales, transfers, and account activity must be attributable to a user, a store, and a timestamp — full audit trail is a core selling point, not an afterthought.

---

## 2. Brand Identity

- **Name:** Cream Restaurant & Catering Services
- **Tagline:** "we serve beyond your desire"
- **Logo mark:** chef's hat crossed with a fork and spoon, "CSC" monogram beneath
- **Palette:** near-black / charcoal background (`#1A1A1A`–`#000000`), warm off-white/cream surfaces (`#F7F3EC` / `#EFE7D8`), gold/champagne accent for CTAs and highlights (`#C9A15C`–`#D4AF6A`), white and black text depending on surface
- **Typography:** clean serif or serif-adjacent for headings (elegance, matches the ribbon/cutlery styling of the brand materials), clean sans-serif for body/UI text and numerals (POS screens need instant legibility)
- **Tone:** premium/elegant but functional — this is a hospitality brand, not a generic dashboard. Login screen and Back Office dashboard should carry the brand; Outlet Terminal sell screen should prioritize speed and legibility over decoration.

Brand assets (logo, reference photos) are provided separately by Thirdsan and should be dropped into `assets/branding/` before UI work begins.

---

## 3. Roles & Access

| Role | Scope | Can do |
|---|---|---|
| **Admin** (Owner) | All stores | Everything: stock, transfers, sales oversight, catering, customer accounts, reports, settings (stores/users/items/prices/packages) |
| **Store Manager** | Assigned store | Confirm incoming transfers, record store consumption, view own store's sales & reports, manage own store's customer interactions |
| **Cashier** | Assigned store | Ring up plate sales, charge to customer accounts, take deposits, view own shift summary. Cannot edit stock, prices, or packages |
| **Storekeeper** (Kira only, optional — can be folded into Store Manager at Kira) | Kira | Record purchases (Stock In), dispatch transfers to outlets |

A single Flutter app; after login, the UI adapts based on role + assigned store. Admin gets a store switcher; everyone else is locked to their own store.

---

## 4. Database Schema (Laravel migrations)

```
stores
  id, name, code, is_main (bool), address, phone, is_active, timestamps

users
  id, name, phone, email (nullable), password, role (enum: admin, store_manager, cashier, storekeeper),
  store_id (nullable for admin), is_active, timestamps

items
  id, name, unit (e.g. kg, litre, piece, crate, bottle), category (nullable), is_drink (bool, default false), is_active, timestamps
  -- items flagged is_drink = true are sellable at the counter (linked from drink_prices) AND stocked/tracked
  -- like any other item via item_store_settings + stock_movements

item_store_settings
  id, item_id, store_id, safety_stock, timestamps
  -- one row per item per store; drives Re-Order status

stock_movements
  id, item_id, store_id, type (enum: purchase, transfer_out, transfer_in, consumption, adjustment),
  qty (decimal, signed: positive for in, negative for out — or use unsigned qty + type direction, pick one convention and be consistent),
  related_transfer_id (nullable, FK to stock_transfers),
  note (nullable), user_id, occurred_at, timestamps
  -- balance per item per store = SUM(qty) WHERE item_id=? AND store_id=? filtered/signed by type
  -- this single table is the source of truth for Stock In / Stock Out / Balance views

stock_transfers
  id, from_store_id (Kira), to_store_id, status (enum: dispatched, confirmed, discrepancy),
  dispatched_by (user_id), dispatched_at,
  confirmed_by (user_id, nullable), confirmed_at (nullable),
  timestamps

stock_transfer_items
  id, stock_transfer_id, item_id, qty_dispatched, qty_received (nullable until confirmed), timestamps

plate_prices
  id, store_id (nullable = applies to all stores unless overridden), price, effective_from, is_active, timestamps
  -- default 25,000, editable by Admin

drink_prices
  id, item_id (FK to items, item must be flagged is_drink = true), store_id (nullable = all stores unless overridden),
  price, effective_from, is_active, timestamps
  -- each drink (soda, water, juice, etc.) is its own item with its own price and its own stock tracking via stock_movements

sales
  id, store_id, sold_by (user_id), 
  payment_method (enum: cash, momo, airtel, account), customer_id (nullable, required if payment_method = account),
  total (computed = SUM of sale_items.line_total), sold_at, timestamps

sale_items
  id, sale_id, item_type (enum: plate, drink), item_id (nullable for plate, required FK to items for drink),
  qty, unit_price (snapshot at time of sale), line_total (computed), timestamps
  -- a sale is now one or more lines: e.g. 1x plate (25,000) + 1x soda (3,000) = total 28,000
  -- a drink sale_item also generates a matching stock_movements row (type: consumption) for that item/store

catering_packages
  id, name (e.g. "Standard", "Premium", "Deluxe"), price_per_plate, description, is_active, timestamps
  -- default seed: 34,000 / 38,000 / 45,000, editable by Admin

catering_orders
  id, client_name, client_phone, event_name (nullable, e.g. "Wedding", "Graduation"), event_date,
  catering_package_id, number_of_plates, total_amount (computed), 
  status (enum: quoted, confirmed, delivered, settled, cancelled),
  created_by (user_id), timestamps

catering_payments
  id, catering_order_id, amount, payment_method (enum: cash, momo, airtel, bank),
  paid_at, recorded_by (user_id), timestamps
  -- balance due = catering_orders.total_amount - SUM(catering_payments.amount)

customers
  id, name, phone, account_type (enum: prepaid, credit), credit_limit (default 0, only relevant if credit),
  is_active, created_by (user_id), timestamps

ledger_entries
  id, customer_id, type (enum: deposit, sale_debit, adjustment), amount (signed: +deposit, -debit),
  related_sale_id (nullable), note (nullable), recorded_by (user_id), occurred_at, timestamps
  -- customer balance = SUM(amount) WHERE customer_id = ?
```

**Business rule constraints to enforce server-side (not just UI):**
- Prepaid customer: reject a debit that would push balance below 0.
- Credit customer: reject a debit that would push balance below `-credit_limit`.
- `stock_transfer_items.qty_received` can only be set once, by a user at `to_store_id`, and locks the transfer line.
- `sales.payment_method = account` requires `customer_id` and creates a matching `ledger_entries` row atomically (DB transaction).
- Every `sale_items` row with `item_type = drink` must atomically create a matching `stock_movements` row (type: consumption, qty = sale_items.qty) at the same store — selling a drink deducts it from that outlet's drink stock in the same transaction as the sale.
- Catering revenue must never be joined into daily outlet sales reports — keep `sales` and `catering_orders` fully separate tables and separate report endpoints.

---

## 5. API Endpoints (Laravel, Sanctum token auth, JSON)

```
POST   /api/auth/login
POST   /api/auth/logout
GET    /api/auth/me

GET    /api/stores
POST   /api/stores                (admin)
PATCH  /api/stores/{id}           (admin)

GET    /api/users                 (admin)
POST   /api/users                 (admin)
PATCH  /api/users/{id}            (admin)

GET    /api/items
POST   /api/items                 (admin)
PATCH  /api/items/{id}            (admin)
GET    /api/items/{id}/balances   (per-store balance + safety stock + status)

POST   /api/stock/purchase        (Kira only — Stock In)
GET    /api/stock/movements       (filterable: store_id, item_id, type, date range)
POST   /api/stock/consumption     (Stock Out at an outlet)
POST   /api/stock/adjustment      (admin/manager — corrections, spoilage)

POST   /api/transfers                       (dispatch, Kira -> outlet)
GET    /api/transfers                       (filterable by store, status)
GET    /api/transfers/{id}
POST   /api/transfers/{id}/confirm          (receiving store confirms qty per item)

GET    /api/plate-price                     (current, per store or global)
PATCH  /api/plate-price                     (admin)

GET    /api/drinks                          (list drink items with current prices)
POST   /api/drinks                          (admin — create a new drink item + price)
PATCH  /api/drinks/{item_id}                (admin — update drink price/details)

POST   /api/sales                           (ring up a sale — payload is one or more lines: plate qty + optional drink lines, each with item_id + qty)
GET    /api/sales                           (filterable: store_id, date range, payment_method)
GET    /api/sales/summary                   (per-store daily/weekly/monthly totals, plate revenue vs drink revenue broken out)

GET    /api/catering-packages
POST   /api/catering-packages                (admin)
PATCH  /api/catering-packages/{id}           (admin)

POST   /api/catering-orders
GET    /api/catering-orders                  (filterable by status, date range)
GET    /api/catering-orders/{id}
PATCH  /api/catering-orders/{id}             (status updates, edits)
POST   /api/catering-orders/{id}/payments    (record a deposit/payment)

POST   /api/customers
GET    /api/customers                        (search by name/phone)
GET    /api/customers/{id}
GET    /api/customers/{id}/statement         (ledger history)
POST   /api/customers/{id}/deposit
GET    /api/customers/{id}/balance

GET    /api/reports/dashboard                (admin — all stores today: sales, low stock, upcoming catering, total credit outstanding)
GET    /api/reports/stock-status             (per store: Sufficient / Re-Order)
GET    /api/reports/outstanding-credit        (customers with negative balance, aging)
GET    /api/reports/catering-pipeline
```

All list endpoints support pagination. All write endpoints validate role + store scope server-side (a cashier token must not be able to hit another store's data even if store_id is passed manually).

---

## 6. Flutter App — Structure & Screens

Single Flutter project, single codebase, Android + iOS. Suggested structure:

```
lib/
  core/            # api client, auth/session, role-based routing, theme (brand tokens)
  features/
    auth/
    dashboard/           # Back Office only
    stock/               # stock in, transfers, balances, reorder status
    sales/               # outlet sell screen, shift summary
    catering/            # orders, packages, payments, pipeline
    customers/           # accounts, deposits, statements
    reports/
  shared/          # widgets, formatters (currency, dates), constants
```

### Outlet Terminal (Cashier / Store Manager, scoped to their store)

- **Sell** (home/default screen): plate quantity stepper, optional drink selector (tap to add a drink line — soda, water, juice, etc., each at its own price), running total across plate + drink lines, payment method selector (Cash / MoMo / Airtel / Account), "Charge to Account" opens customer search → confirm → done. Optimized for large touch targets and completing a sale in seconds.
- **Stock**: today's balance per item with Sufficient/Re-Order badge (color-coded, gold/red against the brand palette); log consumption; **Incoming Transfers** tab — see what Kira dispatched, confirm received quantity per item (flag discrepancy if different).
- **Accounts**: search customer, view balance, record a deposit, view a simple statement.
- **My Day**: today's sales total, plate count, breakdown by payment method — shift close/reconciliation view.

### Back Office (Admin)

- **Dashboard**: today across all 3 stores — sales total, plates sold per store, low-stock alerts, upcoming catering events (next 7 days), total outstanding credit.
- **Stocking**: record purchases at Kira; dispatch transfers to Lugogo/Town (select items + qty); full movement history with filters.
- **Sales**: cross-store sales log and summaries, date range filters.
- **Catering**: create/edit orders, manage packages & pricing, record payments, pipeline view (quoted/confirmed/delivered/settled), filter by upcoming date.
- **Customers**: create accounts (prepaid/credit), set credit limits, view/search all customers, statements.
- **Reports**: stock status across stores, outstanding credit + aging, catering pipeline, sales summaries — exportable views if time allows (CSV first, PDF later).
- **Settings**: manage stores, users & roles, items & safety stock per store, plate price, catering packages.

Store Manager gets a reduced version of the above scoped to their own store (no cross-store dashboard, no user/store settings).

### Design notes for build

- Login screen: full brand treatment — dark background, gold accent, chef's-hat mark, tagline.
- Outlet Terminal sell screen: cream/white surface, minimal chrome, numerals large and legible — this screen is used under lunch-rush pressure.
- Back Office: can carry more of the elegant dark/gold brand identity since it's used deliberately, not under time pressure.
- Currency formatting throughout: UGX with thousands separators (e.g. "UGX 25,000").

---

## 7. Connectivity Strategy (v1)

**Online-first with short-blip tolerance** — not full offline-first sync (descoped for this phase, can be a Phase 2 item if the client requests it):
- Cache catalog, prices, and last-known stock balances locally so screens load instantly.
- If a sale is submitted during a brief network blip, queue locally and retry automatically; surface a clear "pending sync" indicator, never a silent failure.
- Full bidirectional offline sync (multi-day offline operation) is explicitly out of scope for v1.

---

## 8. Tech Stack

- **Backend:** Laravel (latest LTS), MySQL, Sanctum auth, Dockerized, deployed on Contabo VPS behind Nginx (same infra pattern as ThirdPOS / other Thirdsan production apps), GitHub Actions CI/CD.
- **Mobile:** Flutter (latest stable), single codebase for Android + iOS. State management: Riverpod or Bloc (pick one and stay consistent — Riverpod recommended for this size of app). `dio` for API client, `flutter_secure_storage` for auth tokens.
- **No web/desktop app in this phase.**

---

## 9. Explicitly Out of Scope for v1 (confirm before building)

- Full offline-first multi-day sync
- Live MoMo/Airtel Money collection API integration (record payment method only for now; real collection integration is a natural Phase 2 add-on)
- SMS notifications to customers (e.g. balance alerts) — flagged as a strong Phase 2 candidate (ThirdText integration)
- Web/desktop admin panel
- PDF export of reports (start with in-app views / CSV, add PDF later if needed)

**Pending from client (do not seed as final — placeholders only until confirmed):**
- Drink sale prices are confirmed and seeded: Passion Juice UGX 5,000, Mocktail UGX 5,000, Bushera UGX 5,000, Eshande UGX 5,000, Soda UGX 2,000, Water UGX 2,000.
- Exact stocking cost (COGS) for drinks and possibly other items is still pending — client is sending these.
- Per-store safety stock thresholds for drinks are seeded at a placeholder value (10) pending client confirmation of real reorder levels.

---

## 10. Build Order (suggested milestones)

1. Laravel API: auth, stores, users, items, stock movements, transfers — with tests for the balance/reorder logic and transfer confirm flow.
2. Laravel API: sales, plate pricing.
3. Laravel API: catering packages, orders, payments.
4. Laravel API: customers, ledger entries, prepaid/credit constraint enforcement.
5. Laravel API: report endpoints.
6. Flutter: auth + role-based routing + theme/brand setup.
7. Flutter: Outlet Terminal — Sell screen first (highest daily-use value), then Stock, then Accounts, then My Day.
8. Flutter: Back Office — Dashboard, Stocking, Catering, Customers, Reports, Settings.
9. End-to-end pass: create items → purchase at Kira → transfer to Lugogo → confirm → sell plates → charge one sale to a credit account → create a catering order with a deposit → check dashboard reflects all of it correctly.
