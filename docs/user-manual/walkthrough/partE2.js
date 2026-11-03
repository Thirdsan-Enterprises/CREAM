// Part E2: the cashier takes a deposit, then sells on the account.
const L = require('./lib');
(async () => {
  const s = await L.open();
  const page = s.page;
  await L.login(page, '0771000002', 'lugogo-cashier');
  await L.tap(page, 'Accounts', { exact: true, wait: 1500 });
  await page.getByRole('button', { name: /^Kampala Law/ }).first().click();
  await L.settle(page, 1200);
  await L.type(page, 'Reference', 'MoMo ref 48213');
  await L.type(page, 'Amount', '100000');
  await L.shot(page, '31-deposit');
  await L.tap(page, 'Save', { exact: true, wait: 1800 });
  await L.dump(page, 'after deposit');
  await L.shot(page, '32-deposit-done');
  await page.mouse.click(195, 90);   // tap outside the sheet to close it
  await L.settle(page, 800);

  await L.tap(page, 'Sell', { exact: true, wait: 800 });
  await L.tap(page, 'One more plate', { exact: true, wait: 400 });
  await L.tap(page, 'One more plate', { exact: true, wait: 400 });
  await L.tap(page, 'Account', { exact: true, wait: 800 });
  await L.tap(page, 'Select customer', { exact: true, wait: 1000 });
  await L.type(page, 'Search by name or phone', 'Kampala');
  await L.settle(page, 1500);
  await page.getByRole('button', { name: /^Kampala Law/ }).first().click({ timeout: 8000 });
  await L.settle(page, 1500);
  await L.dump(page, 'account chosen');
  await L.shot(page, '33-sell-account');
  await L.tap(page, 'Complete sale', { exact: true, wait: 1800 });
  await L.shot(page, '34-sale-on-account');
  await L.dump(page, 'after account sale');

  await L.tap(page, 'Accounts', { exact: true, wait: 1500 });
  await page.getByRole('button', { name: /^Kampala Law/ }).first().click();
  await L.settle(page, 1500);
  await L.dump(page, 'statement');
  await L.shot(page, '35-statement');
  await s.browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
