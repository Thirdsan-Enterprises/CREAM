// Part I3: breakfast sales at Town, a Town customer near the credit limit,
// a voided sale, the change log and the branch report PDF.
const L = require('./lib');
(async () => {
  let s = await L.open();
  let page = s.page;
  await L.login(page, '0771000012', 'town-cashier');
  await L.settle(page, 1800);
  await page.getByRole('button', { name: /^Tea UGX/ }).first().click();
  await L.settle(page, 300);
  await page.getByRole('group', { name: /^Tea/ }).first().click();
  await L.settle(page, 300);
  await page.getByRole('button', { name: /^Boiled egg UGX/ }).first().click();
  await L.settle(page, 600);
  await L.dump(page, 'breakfast cart');
  await L.shot(page, '64-breakfast-sale');
  await L.tap(page, 'Complete sale', { exact: true, wait: 1800 });

  // A plate at Town's price, rung up as 3 by mistake
  await L.tap(page, 'One more plate', { exact: true, wait: 300 });
  await L.tap(page, 'One more plate', { exact: true, wait: 300 });
  await L.tap(page, 'One more plate', { exact: true, wait: 300 });
  await L.shot(page, '65-town-plate');
  await L.tap(page, 'Complete sale', { exact: true, wait: 1800 });

  // A new Town customer on credit
  await L.tap(page, 'Accounts', { exact: true, wait: 1500 });
  await L.tap(page, 'New customer', { exact: false, wait: 900 });
  await L.type(page, 'Name', 'Jane Nambi');
  await L.type(page, 'Phone', '0772444111');
  await L.tap(page, 'Credit', { exact: true, wait: 600 });
  await L.shot(page, '66-branch-new-customer');
  await L.tap(page, 'Create account', { exact: true, wait: 1800 });
  await s.browser.close();

  // The owner sets Jane's credit limit
  s = await L.open();
  page = s.page;
  await L.login(page, '0700000000', 'password');
  await L.goTo(page, 'Customers');
  await page.getByRole('button', { name: /^Jane Nambi/ }).first().click();
  await L.settle(page, 1500);
  await page.getByRole('button', { name: 'More', exact: true }).click();
  await L.settle(page, 800);
  await page.getByRole('menuitem', { name: 'Edit details' }).click();
  await L.settle(page, 1200);
  await L.dump(page, 'edit customer');
  await L.type(page, 'Credit limit', '50000');
  await L.shot(page, '67-set-credit-limit');
  await L.tap(page, 'Next', { exact: true, wait: 900 });
  await L.type(page, 'Reason', 'Works next door, pays monthly');
  await L.tap(page, 'Save', { exact: true, wait: 1800 });
  await L.shot(page, '68-customer-limit-set');
  await s.browser.close();

  // Joy charges Jane 3 plates: 45,000 of 50,000
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000012', 'town-cashier');
  await L.settle(page, 1500);
  for (let i = 0; i < 3; i++) await L.tap(page, 'One more plate', { exact: true, wait: 300 });
  await page.mouse.move(195, 500);
  await page.mouse.wheel(0, 1500);
  await L.settle(page, 800);
  await L.tap(page, 'Account', { exact: true, wait: 800 });
  await L.tap(page, 'Select customer', { exact: true, wait: 1500 });
  await page.getByRole('button', { name: /^Jane Nambi/ }).first().click({ timeout: 8000 });
  await L.settle(page, 1500);
  await L.tap(page, 'Complete sale', { exact: true, wait: 2000 });
  await L.dump(page, 'after account sale');
  await L.shot(page, '69-credit-warning');
  await L.tap(page, 'OK', { exact: true, wait: 800 });
  await s.browser.close();

  // Peter voids the mistaken 3 plates
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000011', 'town-manager');
  await L.settle(page, 1500);
  await L.tap(page, 'My Day', { exact: true, wait: 1800 });
  await page.mouse.move(195, 500);
  await page.mouse.wheel(0, 1200);
  await L.settle(page, 800);
  await L.dump(page, 'my day sales');
  await L.shot(page, '70-my-day-sales');
  await page.getByRole('button', { name: /^UGX 45,000\s*\n?.*3 Plate.*MoMo|Cash/ }).first().click().catch(async () => {
    await page.getByRole('button', { name: /3 Plate/ }).last().click();
  });
  await L.settle(page, 1000);
  await L.shot(page, '71-sale-detail');
  await L.tap(page, 'Void this sale', { exact: true, wait: 1500 });
  await L.type(page, 'Reason', 'Rang 3 plates, customer had 1');
  await L.shot(page, '72-void-reason');
  await L.tap(page, 'Void sale', { exact: true, wait: 2000 });
  await L.tap(page, 'Changes', { exact: true, wait: 1800 });
  await L.shot(page, '73-manager-changes');
  await s.browser.close();

  // The owner reads the changes and downloads Town's report
  s = await L.open();
  page = s.page;
  await L.login(page, '0700000000', 'password');
  await L.goTo(page, 'Changes');
  await L.shot(page, '74-owner-changes');
  await L.goTo(page, 'Branches');
  await page.mouse.move(195, 600);
  for (let i = 0; i < 3; i++) {
    await page.mouse.wheel(0, 900);
    await L.settle(page, 600);
  }
  await page.getByRole('button', { name: /Town UGX/ }).first().click();
  await L.settle(page, 2000);
  await L.shot(page, '75-town-detail');
  await L.tap(page, 'Download report', { exact: true, wait: 900 });
  await L.shot(page, '76-report-choice');
  await s.browser.close();
  console.log('ok');
})().catch(e => { console.error('FAILED', e.message.slice(0, 900)); process.exit(1); });
