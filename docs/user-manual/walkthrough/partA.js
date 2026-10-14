// Part A: the owner sets up staff, stocks food, adds a new item, dispatches to Lugogo.
const L = require('./lib');

const pick = L.pick;

async function newUser(page, name, phone, password, role, store) {
  await L.tap(page, 'New user', { exact: false });
  await L.type(page, 'Name', name);
  await L.type(page, 'Phone', phone);
  await L.type(page, 'Password', password);
  await pick(page, /^Role/, role);
  await pick(page, /^Branch/, store);
}

(async () => {
  const { browser, page, errors } = await L.open();
  await L.shot(page, '01-sign-in');
  await L.login(page, '0700000000', 'password');
  await L.settle(page, 1500);
  await L.shot(page, '02-owner-home');

  // Staff
  await L.goTo(page, 'Settings', '03-menu');
  await L.tap(page, 'Users', { exact: true });
  await newUser(page, 'Grace Nakato', '0771000001', 'lugogo-manager', 'Store manager', 'Lugogo');
  await L.shot(page, '04-new-user');
  await L.tap(page, 'Create user', { exact: true, wait: 1800 });
  await newUser(page, 'Sarah Auma', '0771000002', 'lugogo-cashier', 'Cashier', 'Lugogo');
  await L.tap(page, 'Create user', { exact: true, wait: 1800 });
  await L.shot(page, '05-users-list');

  // Stock food at Kira
  await L.goTo(page, 'Stocking');
  await L.shot(page, '06-stock-in');
  await L.chooseItem(page, 'Rice');
  await L.type(page, 'Quantity purchased', '100');
  await L.shot(page, '07-stock-in-filled');
  await L.tap(page, 'Record purchase', { exact: true, wait: 1500 });
  await L.shot(page, '08-stock-in-done');

  // A brand-new item
  await L.chooseItem(page, '+new');
  await L.type(page, 'Item name', 'Sugar');
  await L.type(page, 'Re-order level (optional)', '5');
  await L.shot(page, '09-add-item');
  await L.tap(page, 'Add item', { exact: true, wait: 1500 });
  await L.type(page, 'Quantity purchased', '50');
  await L.tap(page, 'Record purchase', { exact: true, wait: 1500 });
  await L.shot(page, '10-new-item-stocked');

  // Transfer
  await L.tap(page, 'Transfer', { exact: true });
  await pick(page, /^To branch/, 'Lugogo');
  await pick(page, /^Item/, /^Rice/);
  await L.type(page, 'Qty', '40');
  await L.tap(page, 'Add item', { exact: true });
  await pick(page, /^Item/, /^Sugar/, 1);
  await L.type(page, 'Qty', '20', 1);
  await L.shot(page, '11-transfer');
  await L.tap(page, 'Dispatch transfer', { exact: true, wait: 1500 });
  await L.shot(page, '12-transfer-dispatched');
  await L.tap(page, 'History', { exact: true, wait: 1500 });
  await L.shot(page, '13-history');
  await L.dump(page, 'history');
  console.log('errors', errors);
  await browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 900)); process.exit(1); });
