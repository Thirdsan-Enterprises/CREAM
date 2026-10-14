// Part C: the Lugogo cashier rings up a sale.
const L = require('./lib');
(async () => {
  const { browser, page, errors } = await L.open();
  await L.login(page, '0771000002', 'lugogo-cashier');
  await L.settle(page, 1500);
  await L.shot(page, '22-sell');
  await L.tap(page, 'One more plate', { exact: true, wait: 400 });
  await page.getByRole('button', { name: /Soda UGX/ }).first().click();
  await L.settle(page, 400);
  await page.getByRole('group', { name: /^Soda/ }).first().click();   // tap the tile again for a second soda
  await L.settle(page, 500);
  await L.dump(page, 'cart');
  await L.shot(page, '23-sell-cart');
  // Water has never been bought for Lugogo, so it cannot be sold
  await page.getByRole('button', { name: /Water UGX/ }).first().click();
  await L.settle(page, 700);
  await L.dump(page, 'water out of stock');
  await L.shot(page, '23b-out-of-stock');
  await L.tap(page, 'Complete sale', { exact: true, wait: 1800 });
  await L.shot(page, '24-sale-done');
  await L.dump(page, 'after sale');

  await L.tap(page, 'Stock', { exact: true });
  await L.type(page, 'Search items', 'Soda');
  await L.dump(page, 'soda after sale');
  await L.tap(page, 'My Day', { exact: true, wait: 1800 });
  await L.shot(page, '25-my-day');
  await L.dump(page, 'my day');
  console.log(errors);
  await browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
