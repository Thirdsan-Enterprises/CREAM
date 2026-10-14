// Part B: the Lugogo manager confirms the delivery and buys drinks.
const L = require('./lib');
(async () => {
  const { browser, page, errors } = await L.open();
  await L.login(page, '0771000001', 'lugogo-manager');
  await L.settle(page, 1500);
  await L.shot(page, '14-manager-sell');

  await L.tap(page, 'Stock', { exact: true });
  await L.shot(page, '15-manager-stock');
  await L.tap(page, 'Incoming Transfers', { exact: false });
  await L.type(page, 'Receiv', '38', 0);   // 2 kg of rice short
  await L.shot(page, '16-confirm-receipt');
  await L.tap(page, 'Confirm receipt', { exact: true, wait: 1800 });
  await L.shot(page, '17-receipt-confirmed');
  await L.tap(page, 'Balances', { exact: true, wait: 1500 });
  await L.dump(page, 'balances after confirm');
  await L.shot(page, '18-balances-after');

  // Drinks are bought at the branch: find Soda and buy 24
  await L.type(page, 'Search items', 'Soda');
  await L.shot(page, '19-search-soda');
  await page.getByRole('button', { name: 'Buy stock' }).first().click({ timeout: 8000 });
  await L.settle(page, 800);
  await L.type(page, 'Quantity bought', '24');
  await L.shot(page, '20-buy-drink');
  await L.tap(page, 'Save', { exact: true, wait: 1800 });
  await L.dump(page, 'after soda purchase');
  await L.shot(page, '21-drink-bought');
  // Daily use: tell the system what the kitchen used
  await L.type(page, 'Search items', 'Rice');
  await page.getByRole('button', { name: /^Rice/ }).first().click({ timeout: 8000 });
  await L.settle(page, 800);
  await L.type(page, 'Quantity used', '8');
  await L.shot(page, '22a-log-use');
  await L.tap(page, 'Save', { exact: true, wait: 1800 });
  await L.dump(page, 'after logging use');
  console.log(errors);
  await browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
