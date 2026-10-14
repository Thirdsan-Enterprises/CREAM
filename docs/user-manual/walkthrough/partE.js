// Part E: customer account — owner creates it, cashier tops it up and sells on account.
const L = require('./lib');
(async () => {
  // Owner creates a prepaid account
  let s = await L.open();
  await L.login(s.page, '0700000000', 'password');
  await L.goTo(s.page, 'Customers');
  await L.tap(s.page, 'New customer', { exact: false });
  await L.dump(s.page, 'new customer dialog');
  await L.type(s.page, 'Name', 'Kampala Law Chambers');
  await L.type(s.page, 'Phone', '0772555000');
  await L.shot(s.page, '29-new-customer');
  await L.tap(s.page, 'Create account', { exact: true, wait: 1800 });
  await L.shot(s.page, '30-customers');
  await L.dump(s.page, 'customers after create');
  await s.browser.close();

})().catch(e => { console.error('FAILED', e.message.slice(0, 800)); process.exit(1); });
