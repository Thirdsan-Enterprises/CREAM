# Clearing trial data before go-live

While the system is being tried out, people make sales, buy stock, send transfers and
create customers. Before the client starts trading for real, clear all of that so the
reports and stock balances start clean.

## What is deleted and what is kept

| Deleted | Kept |
|---|---|
| Sales and their lines | Branches |
| Account ledger entries (top-ups, meals charged) | Items and their re-order levels |
| Stock movements, so **every stock balance returns to 0** | Plate and drink prices |
| Stock transfers | Catering packages |
| Catering orders and their payments | The owner (admin) account |
| *With `--customers`:* all customer accounts | Staff accounts (unless `--users`) |
| *With `--users`:* all staff accounts except owners | Everyone stays signed in |

Items, branches and staff added during the trial are **not** removed unless you use the
options above; remove or edit them in Settings (users can be switched off there).

## Steps

1. **Back up the database first.** In DirectAdmin open phpMyAdmin, select the Cream
   database, choose Export, and keep the file. Deletion cannot be undone.
2. Log in to the server over SSH and go to the app folder (the `DA_APP_DIR` used by the
   deploy), then use the same PHP the deploy uses (`DA_PHP_BIN`, PHP 8.4):

   ```
   cd <app folder>
   <php> artisan cream:reset-trial-data --customers
   ```

   With no `--force` it only lists what would be deleted. Check the numbers.
3. Run it for real. It asks for confirmation:

   ```
   <php> artisan cream:reset-trial-data --customers --force
   ```

   Add `--users` to also delete trial staff accounts (the owner is never deleted).
4. **Record the opening stock** (Stocking > Purchase at Kira, and each branch's drinks),
   so the Re-Order lists are true from day one.
5. Open the app: Branches and Dashboard should show UGX 0 and no sales.

Only run it on the live server once, deliberately, when the client has agreed that
everything entered so far is trial data.
