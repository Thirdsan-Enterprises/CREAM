// Part I: the brainstorm features. Owner: Town's plate price, breakfast
// menu, Town staff. Then procurement, requests, breakfast sales, a branch
// customer, a void, the change log and the PDFs.
const L = require('./lib');

async function newUser(page, name, phone, password, role, store) {
  await L.tap(page, 'New user', { exact: false });
  await L.type(page, 'Name', name);
  await L.type(page, 'Phone', phone);
  await L.type(page, 'Password', password);
  await L.pick(page, /^Role/, role);
  if (store) await L.pick(page, /^Branch/, store);
  await L.tap(page, 'Create user', { exact: true, wait: 1800 });
}

(async () => {
  const { browser, page, errors } = await L.open();
  await L.login(page, '0700000000', 'password');
  await L.goTo(page, 'Settings');
  await L.tap(page, 'Users', { exact: true, wait: 1200 });
  await newUser(page, 'Peter Ssali', '0771000011', 'town-manager', 'Store manager', 'Town');
  await newUser(page, 'Joy Akello', '0771000012', 'town-cashier', 'Cashier', 'Town');

  // Town's plate at 15,000
  await L.tap(page, 'Prices & menu', { exact: true, wait: 1500 });
  await page.getByRole('button', { name: /^Plate/ }).first().click({ timeout: 8000 });
  await L.settle(page, 900);
  await L.pick(page, /^Price for/, 'Town');
  await L.type(page, 'Price', '15000');
  await L.type(page, 'Reason for the change', 'Town plate is smaller');
  await L.shot(page, '50-town-price');
  await L.tap(page, 'Save price', { exact: true, wait: 1800 });
  await L.shot(page, '51-prices');

  // Breakfast menu: tea (made to order) and boiled eggs (counted)
  await L.tap(page, 'Add to menu', { exact: true, wait: 1200 });
  await L.dump(page, 'add to menu');
  await L.type(page, 'Name', 'Tea');
  await L.type(page, 'Unit (piece, cup, bottle...)', 'cup');
  await L.type(page, 'Price at every branch', '1000');
  await page.getByRole('switch', { name: /^Count stock/ }).click();
  await L.settle(page, 500);
  await L.shot(page, '52-add-tea');
  await L.tap(page, 'Add', { exact: true, wait: 1800 });
  await L.tap(page, 'Add to menu', { exact: true, wait: 1200 });
  await L.type(page, 'Name', 'Boiled egg');
  await L.type(page, 'Price at every branch', '1500');
  await L.tap(page, 'Add', { exact: true, wait: 1800 });
  await L.dump(page, 'prices after menu');
  await L.shot(page, '53-menu');
  console.log('errors', errors);
  await browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 900)); process.exit(1); });
