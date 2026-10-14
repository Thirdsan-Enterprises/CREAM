#!/usr/bin/env python3
"""Builds index.html, the Cream POS user manual.

Every step in here was run through the real app on a fresh system (see
docs/user-manual/README.md). If the app changes, rerun the walkthrough, retake
the screenshots, then run this script and render the PDF.
"""
from html import escape
from pathlib import Path

OUT = Path(__file__).parent / "index.html"


def fig(name, caption):
    return (
        f'<figure><img src="img/{name}.png" alt="{escape(caption)}">'
        f"<figcaption>{escape(caption)}</figcaption></figure>"
    )


def step(title, who, body, *figs):
    shots = "".join(fig(n, c) for n, c in figs)
    who_tag = f'<span class="who">{escape(who)}</span>' if who else ""
    return (
        f'<section class="step"><div class="txt"><h3>{title}{who_tag}</h3>{body}</div>'
        f'<div class="shots n{len(figs)}">{shots}</div></section>'
    )


def box(kind, text):
    labels = {"tip": "Good to know", "warn": "Careful", "note": "Note"}
    return f'<div class="box {kind}"><b>{labels[kind]}</b><p>{text}</p></div>'


CSS = """
@font-face{font-family:'Cormorant Garamond';font-weight:600;src:url(fonts/CormorantGaramond-600.ttf)}
@font-face{font-family:'Cormorant Garamond';font-weight:700;src:url(fonts/CormorantGaramond-700.ttf)}
@font-face{font-family:'Manrope';font-weight:400;src:url(fonts/Manrope-400.ttf)}
@font-face{font-family:'Manrope';font-weight:600;src:url(fonts/Manrope-600.ttf)}
@font-face{font-family:'Manrope';font-weight:800;src:url(fonts/Manrope-800.ttf)}
:root{--ink:#1a1a1a;--char:#121110;--cream:#f7f3ec;--cream2:#efe7d8;--gold:#b88a3e;--gold2:#d4af6a;--mute:#6b6254;--line:#ddd2bd;--red:#a33a25;--green:#2f7a4c}
@page{size:A4;margin:16mm 15mm 18mm}
@page :first{margin:0}
*{box-sizing:border-box}
html{font-family:'Manrope',sans-serif;font-size:10.2pt;line-height:1.5;color:var(--ink)}
body{margin:0}
h1,h2,h3{font-family:'Cormorant Garamond',serif;font-weight:700;line-height:1.1;margin:0}
h2{font-size:25pt;margin:0 0 4mm;padding-top:2mm;border-top:1.6pt solid var(--gold)}
h3{font-size:15pt;margin:0 0 2mm}
h4{font-size:9pt;letter-spacing:.12em;text-transform:uppercase;color:var(--gold);margin:5mm 0 1.5mm}
p{margin:0 0 2.4mm}
ol,ul{margin:0 0 2.6mm;padding-left:5mm}
li{margin-bottom:1.1mm}
b,strong{font-weight:800}
.chapter{break-before:page}
.cover{height:297mm;background:var(--char);color:var(--cream);padding:30mm 22mm;display:flex;flex-direction:column;justify-content:space-between;break-after:page}
.cover .mark{font-family:'Cormorant Garamond',serif;font-size:15pt;letter-spacing:.35em;color:var(--gold2)}
.cover h1{font-size:58pt;color:var(--cream);margin:0 0 6mm}
.cover h1 em{color:var(--gold2);font-style:normal}
.cover .sub{font-size:14pt;color:#cdbf9f;max-width:120mm}
.cover .tag{font-family:'Cormorant Garamond',serif;font-size:15pt;font-style:italic;color:var(--gold2)}
.cover .meta{font-size:9pt;color:#9d927f;line-height:1.7}
.cover .rule{width:30mm;height:1.6pt;background:var(--gold);margin:8mm 0}
.toc{columns:2;column-gap:10mm;margin-top:3mm}
.toc div{display:flex;gap:3mm;padding:1.1mm 0;border-bottom:.5pt solid var(--line);break-inside:avoid}
.toc b{color:var(--gold);width:7mm}
table{border-collapse:collapse;width:100%;margin:2mm 0 4mm;font-size:9.4pt}
th{background:var(--cream2);text-align:left;font-size:8.4pt;letter-spacing:.08em;text-transform:uppercase}
th,td{border:.5pt solid var(--line);padding:1.7mm 2.4mm;vertical-align:top}
.step{display:grid;grid-template-columns:1fr auto;gap:7mm;margin:0 0 6mm;padding-bottom:5mm;border-bottom:.5pt solid var(--line);break-inside:avoid}
.step:last-child{border-bottom:0}
.who{display:inline-block;font-family:'Manrope',sans-serif;font-size:7.4pt;font-weight:800;letter-spacing:.1em;text-transform:uppercase;background:var(--cream2);color:var(--gold);padding:.7mm 2.2mm;border-radius:2mm;margin-left:3mm;vertical-align:3pt}
.shots{display:flex;gap:3mm;align-items:flex-start}
figure{margin:0;width:44mm}
.shots.n1 figure{width:52mm}
.shots.n3 figure{width:56mm}
figure img{width:100%;display:block;border:.6pt solid #cbbfa8;border-radius:3mm;box-shadow:0 .6mm 2mm rgba(0,0,0,.18)}
figcaption{font-size:7.6pt;color:var(--mute);margin-top:1.4mm;line-height:1.3}
.step:has(.n3){grid-template-columns:1fr}
.step:has(.n3) .shots{justify-content:flex-start}
.box{border-left:2pt solid var(--gold);background:#faf6ec;padding:2.4mm 3.4mm;margin:2mm 0 3.4mm;break-inside:avoid;border-radius:0 2mm 2mm 0}
.box b{font-size:8pt;letter-spacing:.1em;text-transform:uppercase;color:var(--gold)}
.box p{margin:.8mm 0 0}
.box.warn{border-color:var(--red);background:#fbf1ee}
.box.warn b{color:var(--red)}
.flow{display:flex;gap:2mm;align-items:stretch;margin:3mm 0 5mm}
.flow div{flex:1;border:.8pt solid var(--line);border-radius:2.4mm;padding:2.6mm;background:#fff;font-size:9pt}
.flow div b{display:block;color:var(--gold);font-size:8pt;letter-spacing:.1em;text-transform:uppercase}
.flow span{align-self:center;color:var(--gold);font-weight:800}
.q{break-inside:avoid;margin-bottom:3.4mm}
.q h3{font-family:'Manrope',sans-serif;font-size:10.6pt;font-weight:800;margin-bottom:.8mm}
kbd,.ui{font-family:'Manrope',sans-serif;font-weight:800;color:#6b4d16;background:var(--cream2);padding:0 1.3mm;border-radius:1.2mm;white-space:nowrap}
.foot{font-size:8.6pt;color:var(--mute)}
"""

parts = []

# ---------------- cover ----------------
parts.append(
    """
<div class="cover">
  <div class="mark">CSC</div>
  <div>
    <h1>Cream <em>POS</em></h1>
    <div class="rule"></div>
    <div class="sub">User manual: stock, sales and branch reports for Cream Restaurant &amp; Catering Services</div>
  </div>
  <div>
    <div class="tag">we serve beyond your desire</div>
    <div class="meta">Edition 1 · October 2026<br>Prepared by Thirdsan Enterprises</div>
  </div>
</div>
"""
)

# ---------------- about ----------------
parts.append(
    """
<h2>About this manual</h2>
<p>Cream POS records stock and sales for each of your branches online, so the owner can see how every branch is trading without visiting it. This manual shows, step by step, how each person uses the app. Every step was carried out in the real app on a new, empty system before it was written down.</p>

<h4>What the system does</h4>
<ul>
<li><b>Stock.</b> Food is bought at Kira, sent to Lugogo and Town, and confirmed when it arrives. Each branch buys its own drinks.</li>
<li><b>Sales.</b> Cashiers record plates and drinks, and how the customer paid.</li>
<li><b>Customer accounts.</b> Prepaid and credit accounts that go down as meals are charged.</li>
<li><b>Monitoring.</b> The owner sees each branch's takings, staff, drinks and stock, and the items that need re-ordering.</li>
</ul>

<h4>What this edition does not cover</h4>
<ul>
<li><b>Online payment.</b> The app does not take money. MoMo, Airtel and LPO only record how the customer paid. Collect the money as you do today, then record the sale.</li>
<li><b>Catering orders and the Reports menu.</b> These are in the app but are not described in this edition.</li>
</ul>

<h4>Who does what</h4>
<table>
<tr><th>Role</th><th>Sees</th><th>Can do</th></tr>
<tr><td><b>Owner</b> (admin)</td><td>All branches</td><td>Everything: set up staff, branches, items and prices; buy and transfer stock; sell for any branch; watch every branch.</td></tr>
<tr><td><b>Store manager</b></td><td>Own branch</td><td>Sell, confirm deliveries, buy the branch's drinks, record stock used, take deposits, see the branch's report.</td></tr>
<tr><td><b>Cashier</b></td><td>Own branch</td><td>Sell, take deposits, see stock and "My Day". Cannot change prices or stock levels.</td></tr>
<tr><td><b>Storekeeper</b></td><td>Kira</td><td>Works at Kira. Sees <b>Stocking</b> (buy food, send it to the branches) and <b>Stock</b>. Does not sell.</td></tr>
</table>
<p class="foot">Menu names, buttons and messages are shown in <span class="ui">this style</span> exactly as they appear on screen.</p>
"""
)

# ---------------- contents ----------------
toc = [
    ("1", "Getting started"),
    ("2", "Set up your business (owner, once)"),
    ("3", "Stocking: how stock moves"),
    ("4", "Why does it say Re-Order?"),
    ("5", "Selling"),
    ("6", "Customer accounts"),
    ("7", "My Day"),
    ("8", "The owner's view of each branch"),
    ("9", "Problems and answers"),
    ("10", "Quick reference"),
]
parts.append(
    '<h2>Contents</h2><div class="toc">'
    + "".join(f"<div><b>{n}</b><span>{t}</span></div>" for n, t in toc)
    + "</div>"
)

# ---------------- 1 getting started ----------------
parts.append('<div class="chapter"><h2>1. Getting started</h2>')
parts.append(
    step(
        "Sign in",
        "Everyone",
        """<ol><li>Open the Cream app.</li>
<li>Type your <span class="ui">Phone number</span> and <span class="ui">Password</span>.</li>
<li>Tap <span class="ui">Sign in</span>.</li></ol>
<p>The owner lands on <span class="ui">Branches</span>. Managers and cashiers land on <span class="ui">Sell</span> for their own branch. A storekeeper lands on <span class="ui">Stocking</span>.</p>
<p>To sign out, tap the arrow icon at the top right.</p>""",
        ("01-sign-in", "The sign-in screen."),
        ("02-owner-home", "What the owner sees after signing in."),
    )
)
parts.append(
    box(
        "warn",
        "The first owner account is phone <b>0700000000</b> with password <b>password</b>. Everyone who has read this manual knows it. Change it before anything else (see 1.1).",
    )
)
parts.append(
    step(
        "1.1 Change a password",
        "Owner",
        """<p>The owner can set a new password for anyone, including themselves, and this is also how you help someone who has forgotten theirs.</p>
<ol><li>Open the menu (three lines, top left) and tap <span class="ui">Settings</span>.</li>
<li>Open the <span class="ui">Users</span> tab and tap the person.</li>
<li>Type a new password in <span class="ui">New password</span>. It needs at least 8 characters.</li>
<li>Tap <span class="ui">Save changes</span>.</li></ol>
<p>The person can sign in with the new password straight away.</p>""",
        ("03-menu", "The owner's menu."),
        ("38-edit-user", "Setting a new password."),
    )
)
parts.append("</div>")

# ---------------- 2 setup ----------------
parts.append('<div class="chapter"><h2>2. Set up your business (owner, once)</h2>')
parts.append(
    step(
        "2.1 Add your staff",
        "Owner",
        """<ol><li><span class="ui">Settings</span> &rarr; <span class="ui">Users</span> &rarr; <span class="ui">New user</span>.</li>
<li>Type the person's <span class="ui">Name</span>, <span class="ui">Phone</span> (they sign in with it) and a <span class="ui">Password</span> of at least 8 characters.</li>
<li>Choose their <span class="ui">Role</span> and their <span class="ui">Branch</span>.</li>
<li>Tap <span class="ui">Create user</span>.</li></ol>
<p>Make at least one <b>Cashier</b> and one <b>Store manager</b> for each branch. Give each person their own account so every sale and delivery shows who did it.</p>""",
        ("04-new-user", "Adding a store manager for Lugogo."),
        ("05-users-list", "The staff list."),
    )
)
parts.append(
    box(
        "tip",
        "The owner can sell for any branch (5.4), but give every cashier and manager their own account too. Each sale is recorded against the person who rang it up, which is what makes the staff report in chapter 8 useful.",
    )
)
parts.append(
    step(
        "2.2 Add a branch",
        "Owner",
        """<ol><li><span class="ui">Settings</span> &rarr; <span class="ui">Branches</span> &rarr; <span class="ui">New branch</span>.</li>
<li>Type a <span class="ui">Name</span> and a short <span class="ui">Code</span>, then tap <span class="ui">Create</span>.</li></ol>
<p>The new branch gets the full list of items automatically, each at 0 in stock. Then add its staff (2.1).</p>""",
        ("40-new-branch", "Adding a branch."),
    )
)
parts.append(
    step(
        "2.3 Set the plate price",
        "Owner",
        """<ol><li><span class="ui">Settings</span> &rarr; <span class="ui">Plate price</span>.</li>
<li>Type the <span class="ui">New price</span> and tap <span class="ui">Update price</span>.</li></ol>
<p>Cashiers see the new price on their next sale. Sales already recorded keep the price they were made at. Each drink has its own price, shown on the Sell screen.</p>""",
        ("39-plate-price", "Changing the plate price."),
    )
)
parts.append(
    step(
        "2.4 Set re-order levels",
        "Owner",
        """<p>The re-order level is the amount at which an item is flagged <span class="ui">Re-Order</span> (see chapter 4). Every item starts at 10, except items you add yourself, which start at 0 unless you type a level.</p>
<ol><li><span class="ui">Settings</span> &rarr; <span class="ui">Items</span>.</li>
<li>Tap <span class="ui">Re-order level</span> next to the item.</li>
<li>Choose the <span class="ui">Branch</span>, type the level, and tap <span class="ui">Save</span>.</li></ol>
<p>Each branch has its own level for each item. Set it to what you would want to be warned at: for rice it might be 25 kg, for water 20 bottles.</p>""",
        ("36-reorder-level", "Setting the level for Rice at Kira."),
    )
)
parts.append("</div>")

# ---------------- 3 stocking ----------------
parts.append('<div class="chapter"><h2>3. Stocking: how stock moves</h2>')
parts.append(
    """<div class="flow">
<div><b>1. Buy</b>The owner or the storekeeper records food bought at <b>Kira</b>.</div><span>&rarr;</span>
<div><b>2. Send</b>The owner or storekeeper sends items from Kira to Lugogo or Town with a <b>Transfer</b>. Kira's stock drops at once.</div><span>&rarr;</span>
<div><b>3. Confirm</b>The branch manager confirms what actually arrived. Only then does it count at the branch.</div>
</div>
<p><b>Drinks are different.</b> Each branch buys its own drinks, so the branch (or the owner on its behalf) records the purchase directly. Nothing is sent from Kira.</p>
<p><b>Using stock.</b> Selling a drink takes it off the branch's stock automatically, and a drink cannot be sold once the branch has none. For food, the manager records what the kitchen used (3.7).</p>"""
)
parts.append(
    step(
        "The storekeeper's screens",
        "Storekeeper",
        """<p>A storekeeper signs in to two tabs only: <span class="ui">Stocking</span> and <span class="ui">Stock</span>. The steps in 3.1 to 3.3 are done from <span class="ui">Stocking</span> exactly as the owner does them. There is no Sell tab, because a storekeeper does not sell.</p>
<p>The owner reaches the same screens from the menu: <span class="ui">Stocking</span>.</p>""",
        ("41-storekeeper-home", "The storekeeper's first screen."),
        ("42-storekeeper-transfer", "Sending Matooke to Town."),
    )
)
parts.append(
    step(
        "3.1 Buy food at Kira",
        "Owner · Storekeeper",
        """<ol><li>Open <span class="ui">Stocking</span> &rarr; <span class="ui">Purchase</span>.</li>
<li>Tap the <span class="ui">Item</span> box, type a few letters (for example <b>Ri</b>) and tap <b>Rice</b>.</li>
<li>Type the <span class="ui">Quantity purchased</span>, for example 100.</li>
<li>Tap <span class="ui">Record purchase</span>.</li></ol>
<p>A message at the bottom confirms the new stock, for example <i>Rice at Kira (Main/Warehouse): 100 kg in stock (Stock Sufficient)</i>. If an error message appears instead, the purchase was not recorded; read it and correct the entry.</p>""",
        ("06-stock-in", "Stocking, Purchase tab."),
        ("07-stock-in-filled", "Item and quantity filled in."),
        ("08-stock-in-done", "The confirmation message."),
    )
)
parts.append(
    step(
        "3.2 Add an item that is not on the list",
        "Owner · Storekeeper",
        """<ol><li>In <span class="ui">Purchase</span>, tap the <span class="ui">Item</span> box and tap <span class="ui">Add a new item</span>.</li>
<li>Type the <span class="ui">Item name</span>, its unit (kg, litre, piece) and, if you like, the <span class="ui">Re-order level</span>.</li>
<li>Tap <span class="ui">Add item</span>, then record the purchase as in 3.1.</li></ol>
<p>The new item appears at every branch straight away, at 0, so it can be bought, sent and tracked everywhere.</p>""",
        ("09-add-item", "Adding Sugar with a re-order level of 5."),
        ("10-new-item-stocked", "Sugar bought: 50 kg at Kira."),
    )
)
parts.append(
    step(
        "3.3 Send stock to a branch",
        "Owner · Storekeeper",
        """<ol><li><span class="ui">Stocking</span> &rarr; <span class="ui">Transfer</span>.</li>
<li>Choose <span class="ui">To branch</span>.</li>
<li>Choose an <span class="ui">Item</span>; the list shows only what Kira has, with the amount available. Type the <span class="ui">Qty</span>.</li>
<li>Tap <span class="ui">Add item</span> for each extra item.</li>
<li>Tap <span class="ui">Dispatch transfer</span>. The message <i>Transfer dispatched.</i> confirms it.</li></ol>
<p>You cannot send more than Kira has. The app says how much is available.</p>""",
        ("11-transfer", "Sending 40 kg of Rice and 20 kg of Sugar to Lugogo."),
        ("12-transfer-dispatched", "Transfer dispatched."),
    )
)
parts.append(
    step(
        "3.4 Confirm a delivery",
        "Store manager",
        """<ol><li>Open <span class="ui">Stock</span> &rarr; <span class="ui">Incoming Transfers</span>.</li>
<li>Each item shows what Kira sent. Under <span class="ui">Received</span>, leave the number if it matches what arrived, or type what you actually counted.</li>
<li>Tap <span class="ui">Confirm receipt</span>.</li></ol>
<p>Stock is added at your branch for exactly the amounts you entered. If a number differs from what was sent, the transfer is marked as a shortfall and the owner sees it under <span class="ui">Short on arrival</span> in the branch report. Be honest here: it is how losses on the road are found.</p>
<p>A delivery can only be confirmed once.</p>""",
        ("15-manager-stock", "Stock, Incoming Transfers."),
        ("16-confirm-receipt", "Rice counted as 38 of 40."),
        ("17-receipt-confirmed", "Transfer confirmed."),
    )
)
parts.append(
    step(
        "3.5 Buy drinks for a branch",
        "Store manager · Owner",
        """<p><b>The manager:</b></p>
<ol><li>Open <span class="ui">Stock</span> &rarr; <span class="ui">Balances</span> and type the drink in <span class="ui">Search items</span>.</li>
<li>Tap the cart icon (<span class="ui">Buy stock</span>) on that drink.</li>
<li>Type the <span class="ui">Quantity bought</span> and tap <span class="ui">Save</span>.</li></ol>
<p><b>The owner</b> can do the same for any branch: <span class="ui">Stocking</span> &rarr; <span class="ui">Purchase</span>, choose the drink, then choose <span class="ui">Bought for which branch</span>.</p>
<p>Food cannot be bought at a branch; the app will refuse. Food comes from Kira.</p>""",
        ("19-search-soda", "Finding Soda."),
        ("20-buy-drink", "Buying 24 bottles."),
        ("21-drink-bought", "Soda: 24 in stock."),
    )
)
parts.append(
    step(
        "3.6 Record what the kitchen used",
        "Store manager · Cashier",
        """<ol><li><span class="ui">Stock</span> &rarr; <span class="ui">Balances</span>. Find the item with <span class="ui">Search items</span> and tap its name.</li>
<li>Type the <span class="ui">Quantity used</span> and tap <span class="ui">Save</span>. <i>Consumption logged.</i> confirms it.</li></ol>
<p>Do this at the end of each day for the food that was cooked, so the balance stays true. Drinks do not need this: selling them takes them off the stock.</p>""",
        ("22a-log-use", "Rice used: 8 kg."),
    )
)
parts.append(
    step(
        "3.7 See the history",
        "Owner",
        """<p><span class="ui">Stocking</span> &rarr; <span class="ui">History</span> lists every movement, newest first: <b>Bought</b>, <b>Sent to a branch</b>, <b>Received from Kira</b>, <b>Used / sold</b> and <b>Corrected</b>, with the branch and time.</p>""",
        ("13-history", "Stock history."),
    )
)
parts.append("</div>")

# ---------------- 4 re-order ----------------
parts.append('<div class="chapter"><h2>4. Why does it say Re-Order?</h2>')
parts.append(
    """<p><b>An item shows Re-Order when the stock at that branch is at or below its re-order level.</b> That is all it means. It is worked out for each item at each branch separately, so there are four common reasons for a Re-Order that surprises people.</p>
<table>
<tr><th>You see</th><th>Why</th><th>What to do</th></tr>
<tr><td>Everything says Re-Order on a new system</td><td>Nothing has been bought yet. Every item is at 0, and the default level is 10.</td><td>Buy the items (3.1). Items you do not use can be left; they are only a list.</td></tr>
<tr><td>You bought rice at Kira, but Lugogo still says Re-Order</td><td>Buying fills <b>Kira</b> only. Each branch has its own stock.</td><td>Send it to Lugogo with a Transfer (3.3), and have the manager confirm it (3.4).</td></tr>
<tr><td>You sent a transfer, but the branch still says Re-Order</td><td>The branch has not confirmed it yet. Until then the stock is on its way, not at the branch.</td><td>Ask the manager to open <span class="ui">Stock</span> &rarr; <span class="ui">Incoming Transfers</span> and confirm.</td></tr>
<tr><td>You bought 5, and it still says Re-Order</td><td>5 is at or below the level of 10.</td><td>Buy more, or change the level (2.4).</td></tr>
</table>
<p>The Stock screen of a branch can show only the items that need re-ordering: tap the <span class="ui">Re-Order only</span> filter above the list. On the owner's <span class="ui">Dashboard</span>, the alerts are grouped by branch; tap a branch to see its items, the most depleted first.</p>"""
)
parts.append(
    box(
        "tip",
        "Screens show the figures as they were when you opened them. Open the screen again (or pull the list down to refresh) after someone else has bought or confirmed stock.",
    )
)
parts.append("</div>")

# ---------------- 5 selling ----------------
parts.append('<div class="chapter"><h2>5. Selling</h2>')
parts.append(
    step(
        "5.1 Ring up a sale",
        "Cashier · Store manager",
        """<ol><li>Open <span class="ui">Sell</span>. The plate price is at the top.</li>
<li>Use <span class="ui">+</span> and <span class="ui">&minus;</span> to set the number of plates.</li>
<li>Tap a drink to add one. Tap it again for each extra. The number on its corner shows how many. Tap the number to take one away. Under each drink the screen shows how many are <b>left</b> at your branch.</li>
<li>Check the <span class="ui">Total</span>. It and the <span class="ui">Complete sale</span> button stay at the bottom of the screen while you scroll.</li>
<li>Choose the <span class="ui">Payment method</span> (see the table below).</li>
<li>Tap <span class="ui">Complete sale</span>. <i>Sale completed.</i> confirms it.</li></ol>
<p>The screen resets to one plate for the next customer. A sale can be plates only, drinks only, or both.</p>""",
        ("22-sell", "The Sell screen."),
        ("23-sell-cart", "2 plates and 2 Sodas."),
        ("24-sale-done", "Sale completed."),
    )
)
parts.append(
    """<table>
<tr><th>Payment method</th><th>Use it when</th></tr>
<tr><td><b>Cash</b></td><td>The customer paid in cash.</td></tr>
<tr><td><b>MoMo</b> / <b>Airtel</b></td><td>The customer paid by mobile money. Confirm the money arrived on your phone first; the app only records the method.</td></tr>
<tr><td><b>Account</b></td><td>The meal is charged to a customer's prepaid, credit or LPO account (5.2).</td></tr>
<tr><td><b>LPO</b></td><td>A one-off sale covered by a purchase order.</td></tr>
</table>"""
)
parts.append(
    step(
        "5.2 Charge a sale to a customer account",
        "Cashier · Store manager",
        """<ol><li>Build the sale as in 5.1 and choose <span class="ui">Account</span> as the payment method.</li>
<li>Tap <span class="ui">Select customer</span>, type part of the name or phone number in <span class="ui">Search by name or phone</span>, and tap the customer.</li>
<li>The screen shows what they can spend, for example <i>Available: UGX 400,000</i>. If the total is more, it warns you before you try.</li>
<li>Tap <span class="ui">Complete sale</span>.</li></ol>
<p>A prepaid account cannot go below zero. A credit account cannot go past its limit. The app refuses a sale that would break either rule.</p>""",
        ("33-sell-account", "Customer chosen; balance shown."),
        ("34-sale-on-account", "Charged to the account."),
    )
)
parts.append(
    step(
        "5.3 A drink with none in stock cannot be sold",
        "Cashier · Store manager · Owner",
        """<p>A drink can only be sold while your branch has it. A drink with none shows <b>Out of stock</b>, and tapping it says <i>Water is out of stock. Record the purchase first.</i> If you ask for more than is left, the app says <i>Only 3 Soda in stock.</i></p>
<p>The fix is always the same: record the purchase (3.5), then sell. Plates do not need stock recorded; only drinks do.</p>""",
        ("23b-out-of-stock", "Water has none recorded; Soda has 24."),
    )
)
parts.append(
    step(
        "5.4 Sell as the owner",
        "Owner",
        """<ol><li>Open the menu and tap <span class="ui">Sell</span>.</li>
<li>Under <span class="ui">Selling for</span>, choose the branch.</li>
<li>Build the sale and tap <span class="ui">Complete sale</span> exactly as in 5.1.</li></ol>
<p>The sale, its drink stock and its takings belong to the branch you chose, and your name is recorded as the seller. Choose the branch before you start; switching branches clears the sale.</p>""",
        ("43-owner-pick-branch", "Choosing the branch."),
        ("44-owner-sell", "Selling for Town."),
        ("45-owner-sale-done", "Sale completed."),
    )
)
parts.append("</div>")

# ---------------- 6 accounts ----------------
parts.append('<div class="chapter"><h2>6. Customer accounts</h2>')
parts.append(
    """<table>
<tr><th>Type</th><th>How it works</th></tr>
<tr><td><b>Prepaid</b></td><td>The customer pays in advance. Each meal is deducted. The balance can never go below zero.</td></tr>
<tr><td><b>Credit</b></td><td>The customer eats now and pays later, up to a <b>credit limit</b> you set. The balance shows what they owe.</td></tr>
<tr><td><b>LPO</b></td><td>For organisations that pay against a purchase order. Top up with the LPO amount; meals draw it down.</td></tr>
</table>"""
)
parts.append(
    step(
        "6.1 Create an account",
        "Owner",
        """<ol><li>Open <span class="ui">Customers</span> &rarr; <span class="ui">New customer</span>.</li>
<li>Type the <span class="ui">Name</span> and <span class="ui">Phone</span>, and choose <span class="ui">Prepaid</span>, <span class="ui">Credit</span> or <span class="ui">LPO</span>. For Credit, type the <span class="ui">Credit limit</span>.</li>
<li>Tap <span class="ui">Create account</span>.</li></ol>
<p>The list can be filtered with the <span class="ui">All</span>, <span class="ui">Prepaid</span>, <span class="ui">Credit</span> and <span class="ui">LPO</span> buttons, or searched by name or phone.</p>""",
        ("29-new-customer", "Creating an account."),
        ("30-customers", "The customer list."),
    )
)
parts.append(
    step(
        "6.2 Take a deposit",
        "Cashier · Store manager",
        """<ol><li>Open <span class="ui">Accounts</span> and tap the customer.</li>
<li>Type the <span class="ui">Deposit amount</span>, and a reference such as the MoMo transaction number in <span class="ui">Reference/note</span>.</li>
<li>Tap <span class="ui">Deposit</span>. The <span class="ui">Balance</span> updates and the deposit appears in the <span class="ui">Statement</span> below as a <b>Top-up</b>.</li></ol>
<p>Take the money first, then record it. The app does not collect money.</p>""",
        ("31-deposit", "Entering a deposit."),
        ("32-deposit-done", "Balance: UGX 100,000."),
    )
)
parts.append(
    step(
        "6.3 See an account's statement",
        "Owner · Manager · Cashier",
        """<p>Open the customer (<span class="ui">Accounts</span>, or <span class="ui">Customers</span> for the owner). The <span class="ui">Statement</span> lists every <b>Top-up</b> and <b>Meal charged</b> with its date, newest first. Meals appear as negative amounts.</p>""",
        ("35-statement", "A top-up and a meal charged."),
    )
)
parts.append("</div>")

# ---------------- 7 my day ----------------
parts.append('<div class="chapter"><h2>7. My Day</h2>')
parts.append(
    step(
        "End-of-shift check",
        "Cashier · Store manager",
        """<p>Open <span class="ui">My Day</span> to see your branch's sales for today: the total, how many plates, plate and drink revenue, and the amount for each payment method.</p>
<p>At closing, compare the <b>Cash</b> line with the cash in the drawer. MoMo and Airtel should match the messages on your phone. Account sales are not cash; they are charged to customers.</p>""",
        ("25-my-day", "My Day after a UGX 54,000 cash sale."),
    )
)
parts.append("</div>")

# ---------------- 8 owner view ----------------
parts.append('<div class="chapter"><h2>8. The owner\'s view of each branch</h2>')
parts.append(
    step(
        "8.1 Branches",
        "Owner",
        """<p><span class="ui">Branches</span> is the first screen. Choose a period at the top: <span class="ui">Today</span>, <span class="ui">Yesterday</span>, <span class="ui">7 days</span>, <span class="ui">30 days</span> or <span class="ui">This month</span>.</p>
<ul><li>The big number is the takings of all branches for the period, with the change against the period just before it.</li>
<li>The chart shows when the money came in, by hour for one day and by day for longer periods. Each branch has its own colour.</li>
<li>Each branch card shows its takings, its share of the total, the number of sales, plates, drinks and the average sale, the time of its <b>last sale</b> (a quiet branch stands out), and how many items it needs to re-order.</li></ul>
<p>Catering is not included here; these are daily outlet sales only.</p>""",
        ("26-branches-today", "All branches for today."),
    )
)
parts.append(
    step(
        "8.2 One branch in detail",
        "Owner · Store manager",
        """<p>Tap a branch card. You see, for the chosen period:</p>
<ul><li><b>How customers paid</b>: cash, MoMo, Airtel, account, LPO.</li>
<li><b>Sales by staff</b>: each person's takings and plates.</li>
<li><b>Drinks sold</b>: how many of each.</li>
<li><b>Stock</b>: items to re-order with their levels, deliveries received, deliveries that came <b>short</b>, and deliveries still waiting to be confirmed.</li>
<li><b>Stock used</b> and the <b>Latest sales</b> with time, person and payment method.</li></ul>
<p>A store manager sees the same report for their own branch only, from the chart icon at the top of their screen.</p>""",
        ("27-branch-detail", "Lugogo, today."),
        ("27b-branch-detail-more", "Further down: staff, drinks, stock."),
    )
)
parts.append(
    step(
        "8.3 Dashboard",
        "Owner",
        """<p><span class="ui">Dashboard</span> shows today's total across branches, plates sold, money owed on credit accounts and the low-stock alerts, grouped by branch. Tap a branch to open its list. <b>Out</b> means none left; <b>Low</b> means some left but at or below the level.</p>""",
        ("28-dashboard", "Dashboard."),
        ("37-dashboard-kira", "Kira's alerts opened."),
    )
)
parts.append("</div>")

# ---------------- 9 faq ----------------
parts.append('<div class="chapter"><h2>9. Problems and answers</h2>')
faq = [
    (
        "I bought stock but it still says Re-Order.",
        "See chapter 4. Stock is counted per branch: buying at Kira fills Kira only, and the level may be higher than what you bought.",
    ),
    (
        "I cannot sell.",
        "Plates can always be sold. A drink can only be sold while the branch has it in stock: look for <b>Out of stock</b> under the drink, and record the purchase first (3.5). The owner sells from the menu: <span class=\"ui\">Sell</span>, then choose the branch (5.4). A storekeeper does not sell. If nothing loads, check the phone's connection.",
    ),
    (
        "It says &ldquo;Only 3 Soda in stock&rdquo; when I sell.",
        "The branch has fewer than you are selling. Count what is on the shelf; if the shelf has more, a purchase was not recorded. Record it (3.5), then sell. If the shelf really has fewer, sell fewer.",
    ),
    (
        "An item I need is missing from a list.",
        "Add it with <span class=\"ui\">Add a new item</span> (3.2).",
    ),
    (
        "It says only some amount is available when I send a transfer.",
        "Kira has less than you asked for. Record the purchase first (3.1), or send a smaller amount.",
    ),
    (
        "A delivery does not appear under Incoming Transfers.",
        "It was sent to a different branch, or it has already been confirmed. Check <span class=\"ui\">Stocking</span> &rarr; <span class=\"ui\">History</span> as the owner.",
    ),
    (
        "A sale on account was refused.",
        "A prepaid customer does not have enough money, or a credit customer would pass their limit. Take a deposit (6.2) or ask the owner to raise the limit.",
    ),
    (
        "It says it could not reach the server.",
        "The phone has no internet. Reconnect and try again. Check that the sale did not already go through in <span class=\"ui\">My Day</span> before you repeat it.",
    ),
    (
        "A number looks out of date.",
        "Open the screen again or pull the list down. Screens show the figures from when they were opened.",
    ),
    (
        "I forgot my password.",
        "Ask the owner to set a new one (1.1). If the owner forgets theirs, contact Thirdsan Enterprises.",
    ),
]
parts.append("".join(f'<div class="q"><h3>{q}</h3><p>{a}</p></div>' for q, a in faq))
parts.append("</div>")

# ---------------- 10 quick reference ----------------
parts.append('<div class="chapter"><h2>10. Quick reference</h2>')
parts.append(
    """<table>
<tr><th>I want to&hellip;</th><th>Who</th><th>Go to</th></tr>
<tr><td>Buy food at Kira</td><td>Owner, storekeeper</td><td>Stocking &rarr; Purchase</td></tr>
<tr><td>Add a new item</td><td>Owner, storekeeper</td><td>Stocking &rarr; Purchase &rarr; Item &rarr; Add a new item</td></tr>
<tr><td>Send stock to a branch</td><td>Owner, storekeeper</td><td>Stocking &rarr; Transfer</td></tr>
<tr><td>Confirm a delivery</td><td>Store manager</td><td>Stock &rarr; Incoming Transfers</td></tr>
<tr><td>Buy drinks for a branch</td><td>Manager, owner</td><td>Stock &rarr; Balances &rarr; cart icon (owner: Stocking &rarr; Purchase)</td></tr>
<tr><td>Record what was used</td><td>Manager, cashier</td><td>Stock &rarr; Balances &rarr; tap the item</td></tr>
<tr><td>See what needs re-ordering</td><td>Everyone</td><td>Stock &rarr; Re-Order only (owner: Dashboard)</td></tr>
<tr><td>Ring up a sale</td><td>Cashier, manager, owner</td><td>Sell (owner: choose the branch first)</td></tr>
<tr><td>Take a deposit</td><td>Cashier, manager</td><td>Accounts &rarr; customer</td></tr>
<tr><td>Create a customer account</td><td>Owner</td><td>Customers &rarr; New customer</td></tr>
<tr><td>Check today's takings at my branch</td><td>Cashier, manager</td><td>My Day</td></tr>
<tr><td>Compare my branches</td><td>Owner</td><td>Branches</td></tr>
<tr><td>Add staff / reset a password</td><td>Owner</td><td>Settings &rarr; Users</td></tr>
<tr><td>Change the plate price</td><td>Owner</td><td>Settings &rarr; Plate price</td></tr>
<tr><td>Change a re-order level</td><td>Owner</td><td>Settings &rarr; Items &rarr; Re-order level</td></tr>
<tr><td>Add a branch</td><td>Owner</td><td>Settings &rarr; Branches &rarr; New branch</td></tr>
</table>
<h4>How this manual was checked</h4>
<p class="foot">The steps above were run, in order, through the real Cream app on a new system: setting up staff (including a storekeeper), buying at Kira, adding an item, sending a transfer, confirming it with a shortfall, buying drinks at a branch, recording use, selling for cash and on account, the stock limit on drinks, selling as the owner, taking a deposit, changing the plate price, resetting a password, adding a branch, and reading the owner's reports. The same journey also runs as an automated test on the server, so the system's rules (stock, transfers, prices, account limits) are checked on every change.</p>
<p class="foot">Lists in the app show up to 500 items, users and customers, and up to 100 of the latest sales, movements and transfers.</p>"""
)
parts.append("</div>")

html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Cream POS User Manual</title>
<style>{CSS}</style></head><body>
{''.join(parts)}
</body></html>"""
OUT.write_text(html)
print("wrote", OUT, len(html) // 1024, "KB")
