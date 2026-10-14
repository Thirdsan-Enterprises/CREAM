// Part H: the storekeeper stocks and sends; the owner sells for a branch.
const L = require('./lib');
(async () => {
  // Storekeeper at Kira
  let s = await L.open();
  let page = s.page;
  await L.login(page, '0771000003', 'kira-storekeeper');
  await L.settle(page, 1800);
  await L.dump(page, 'storekeeper home');
  await L.shot(page, '41-storekeeper-home');
  await L.chooseItem(page, 'Matooke');
  await L.type(page, 'Quantity purchased', '30');
  await L.tap(page, 'Record purchase', { exact: true, wait: 1500 });
  await L.dump(page, 'storekeeper purchase');
  await L.tap(page, 'Transfer', { exact: true, wait: 900 });
  await L.pick(page, /^To branch/, 'Town');
  await L.pick(page, /^Item/, /^Matooke/);
  await L.type(page, 'Qty', '10');
  await L.tap(page, 'Dispatch transfer', { exact: true, wait: 1500 });
  await L.dump(page, 'storekeeper transfer');
  await L.shot(page, '42-storekeeper-transfer');
  await s.browser.close();

  // Owner sells for Town
  s = await L.open();
  page = s.page;
  await L.login(page, '0700000000', 'password');
  await L.goTo(page, 'Sell');
  await L.shot(page, '43-owner-pick-branch');
  await L.tap(page, 'Town', { exact: true, wait: 1500 });
  await L.shot(page, '44-owner-sell');
  await L.dump(page, 'owner sell at Town');
  await L.tap(page, 'Complete sale', { exact: true, wait: 1800 });
  await L.shot(page, '45-owner-sale-done');
  await L.dump(page, 'owner sale done');
  await s.browser.close();
})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
