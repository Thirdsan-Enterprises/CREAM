// Part G: the owner resets a password, changes the plate price and adds a branch.
const L = require('./lib');
(async () => {
  let s = await L.open();
  let page = s.page;
  await L.login(page, '0700000000', 'password');
  await L.goTo(page, 'Settings');
  await L.tap(page, 'Users', { exact: true, wait: 1200 });
  await page.getByRole('button', { name: /^Sarah Auma/ }).first().click({ timeout: 8000 });
  await L.settle(page, 900);
  await L.type(page, 'New password', 'new-password-1');
  await L.shot(page, '38-edit-user');
  await L.tap(page, 'Save changes', { exact: true, wait: 1800 });

  await L.tap(page, 'Prices & menu', { exact: true, wait: 1500 });
  await L.dump(page, 'prices tab');
  await page.getByRole('button', { name: /^Plate/ }).first().click({ timeout: 8000 });
  await L.settle(page, 900);
  await L.type(page, 'Price', '26000');
  await L.type(page, 'Reason for the change', 'New prices from November');
  await L.shot(page, '39-plate-price');
  await L.tap(page, 'Save price', { exact: true, wait: 1800 });
  await L.dump(page, 'plate price after');

  await L.tap(page, 'Branches', { exact: true, wait: 1200 });
  await L.tap(page, 'New branch', { exact: false, wait: 900 });
  await L.type(page, 'Name', 'Ntinda');
  await L.type(page, 'Code', 'NTINDA');
  await L.shot(page, '40-new-branch');
  await L.tap(page, 'Create', { exact: true, wait: 1800 });
  await L.goTo(page, 'Branches');
  await L.dump(page, 'branches after new branch');
  await s.browser.close();

  // Sarah signs in with the new password and sees the new price
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000002', 'new-password-1');
  await L.settle(page, 1500);
  await L.dump(page, 'sarah after new password');
  await s.browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
