# Clearing trial data before go-live

While the system is being tried out, people make sales, buy stock, send transfers and
create customers. Before the client starts trading for real, clear all of that so the
reports and stock balances start clean.

## What is deleted and what is kept

| Deleted | Kept |
|---|---|
| Sales and their lines (including voided ones) | Branches |
| Account ledger entries (top-ups, meals charged) | The menu, with each branch's prices and packing price |
| Stock movements, so **every stock balance returns to 0** (purchases, today's plates, drinks) | Kitchen stock items, their headings and re-order levels |
| Purchases ledger (it is made from the purchases) | Plate price and catering packages |
| Stock transfers and branch stock requests | The owner (admin) account |
| Expenses | Staff accounts (unless `--users`) |
| Catering orders and their payments | Customer accounts (unless `--customers`) |
| The Changes log (trial voids and edits) | Everyone stays signed in |
| *With `--customers`:* all customer accounts | |
| *With `--users`:* all staff accounts except owners | |

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

# Updates after the first load

Deploying runs `migrate`, which brings the menu in line with each update
(for example, moving the silver plate to Packing and breakfast to Town
only). There is no command to run by hand unless the release notes say so.

# Loading the Town and Kira menu (once)

The breakfast and lunch menu Cream sent in November 2026 (Beef 10,000, Fish
12,000, Milk Tea 3,000, ...) is loaded with one command on the server, after
the update that adds menus per branch has been deployed:

```
php artisan migrate --force
php artisan cream:load-menu
```

- It puts the dishes on the menu at **Town** and **Kira**, at the prices in
  the document, except that **every lunch at Kira is UGX 25,000**.
- **Lugogo** gets its own two lunches: *Beef* (15,000) and *Beans*
  (10,000), kept apart from Town and Kira's dishes. Add more, rename or
  reprice them in Settings > Prices & menu (tick only Lugogo under *Sold at*).
  If an earlier load named them *Full plate* / *Small plate*, running the
  command again renames them; once Lugogo has its own lunches the command
  leaves them as the owner set them.
- **Silver plate** (the aluminium plate food is packed in) is not a tile on
  the Sell screen: it is the **Takeaway** switch on the order, one silver
  plate per lunch plate by default (change the count there). Its price is
  under the *Packing* heading in Settings > Prices & menu.
- **Breakfast is Town's only.** Kira and Lugogo sell lunch and drinks.
- **Counted each morning:**
  - *Lunch plates* for every branch are set by **procurement or the owner**
    in Stocking > *Today's plates* (choose the branch, type e.g. 40 Beef).
    Branch staff see the counts but cannot change them.
  - *Town's breakfast* (chapatis, mandazi, samosas...) is counted by Town
    itself: *Plates* on the Sell screen. Tea, Rolex and Omelette are made
    to order and not counted.
  - Each sale takes one off; the next day starts from nothing. Made against
    sold shows what was left over.
- Water and Soda are set to UGX 1,500 at Town and Kira; other branches keep
  their prices.
- It is safe to run again: it does not duplicate items and does not overwrite
  prices the owner has changed since (add `--update-prices` to reset them).
- Other branch codes: `php artisan cream:load-menu --branches=TOWN,KIRA,NTINDA`.

# Loading the procurement list (once)

Cream's handwritten procurement list (sugar, serviettes, charcoal, Royco...)
is loaded under headings (Food, Spices & seasoning, Packaging & disposables,
Cleaning, Fuel) with:

```
php artisan cream:load-procurement-items
```

Safe to run again. After that, procurement and the owner add, rename or
remove items in the app (Stocking > Items, or Settings > Kitchen stock).
Run it after `cream:load-menu`.

*Mineral water* is not on the list: it is the bottled **Water** drink. Each
branch buys it as a drink (Stocking > Purchase lists drinks too) and sells it
from the Drinks heading. An older *Mineral water* kitchen item is deleted, or
hidden if it already has history.

Store managers see their branch's kitchen stock (Stock > Balances) and
confirm what procurement sends; only procurement and the owner add or remove
kitchen items.

# Customer accounts and LPOs

Opening an account asks for its money up front:

- **Prepaid:** the amount paid now and how (cash, MoMo, Airtel, bank). Each
  meal comes off it.
- **Credit:** the owner sets the credit limit.
- **LPO** (a company whose staff eat on a purchase order): the LPO number,
  its amount, how many lunch plates it pays for (optional) and what it
  covers (Lunch, Breakfast, Drinks).

Selling on an LPO: choose **LPO** under *Paid by*, then the company. The
sale is refused if the LPO does not cover something in the order (take
payment for that separately), if its plates are used up, or if its amount
is used up. Packing for takeaway is always allowed. When the company sends
its next LPO, open the account and tap **New LPO**; what was left on the
account carries on.
