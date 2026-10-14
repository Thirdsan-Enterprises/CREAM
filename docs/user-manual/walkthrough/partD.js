// Part D: the owner checks the figures and changes a re-order level.
const L = require('./lib');
(async () => {
  const { browser, page, errors } = await L.open();
  await L.login(page, '0700000000', 'password');
  await L.settle(page, 2000);
  await L.shot(page, '26-branches-today');
  await page.getByRole('button', { name: /^Lugogo/ }).first().click();
  await L.settle(page, 2000);
  await L.shot(page, '27-branch-detail');
  await page.mouse.move(195, 500);
  await page.mouse.wheel(0, 900);
  await L.settle(page, 800);
  await L.shot(page, '27b-branch-detail-more');
  await page.getByRole('button', { name: 'Back' }).click();
  await L.settle(page, 800);

  await L.goTo(page, 'Dashboard');
  await L.shot(page, '28-dashboard');
  await L.dump(page, 'dashboard');

  // Re-order level for Rice at Kira
  await L.goTo(page, 'Settings');
  await L.tap(page, 'Items', { exact: true, wait: 1500 });
  await page.mouse.move(195, 500);
  await page.mouse.wheel(0, 1500);
  await L.settle(page, 900);
  await L.dump(page, 'items scrolled');
  await L.clickOnRow(page, '^Rice', 'Re-order level');
  await L.dump(page, 're-order dialog');
  await L.type(page, 'Re-order level', '80');
  await L.shot(page, '36-reorder-level');
  await L.tap(page, 'Save', { exact: true, wait: 1500 });
  await L.dump(page, 'after save level');
  await L.goTo(page, 'Dashboard');
  await page.getByRole('button', { name: /^Kira/ }).first().click();
  await L.settle(page, 900);
  await L.dump(page, 'kira alerts');
  await L.shot(page, '37-dashboard-kira');
  console.log(errors);
  await browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
