// Part I2: procurement buys eggs; Town asks for eggs; procurement sends;
// Town confirms and downloads the receipt.
const L = require('./lib');
(async () => {
  let s = await L.open();
  let page = s.page;
  await L.login(page, '0771000003', 'kira-storekeeper');
  await L.settle(page, 1500);
  await L.tap(page, 'Purchase', { exact: true });
  await L.chooseItem(page, 'Boiled egg');
  await L.type(page, 'Quantity purchased', '90');
  await L.tap(page, 'Record purchase', { exact: true, wait: 1500 });
  await s.browser.close();

  // Town's manager asks procurement
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000011', 'town-manager');
  await L.settle(page, 1500);
  await L.tap(page, 'Stock', { exact: true });
  await L.tap(page, 'Requests', { exact: true, wait: 1200 });
  await L.shot(page, '54-branch-requests');
  await L.tap(page, 'Ask procurement', { exact: true, wait: 1800 });
  await L.type(page, 'Search items', 'egg');
  await L.dump(page, 'request sheet');
  await page.getByRole('textbox').nth(1).click();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type('30');
  await L.settle(page, 300);
  await L.type(page, 'Note (optional)', 'For breakfast this week');
  await L.shot(page, '55-ask-procurement');
  await L.tap(page, 'Send request', { exact: true, wait: 1800 });
  await L.shot(page, '56-request-sent');
  await s.browser.close();

  // Procurement answers from the Requests inbox
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000003', 'kira-storekeeper');
  await L.settle(page, 1800);
  await L.dump(page, 'procurement inbox');
  await L.shot(page, '57-procurement-inbox');
  await L.tap(page, 'Send', { exact: true, wait: 1200 });
  await L.shot(page, '58-send-request');
  await page.getByRole('button', { name: 'Send', exact: true }).last().click();
  await L.settle(page, 2000);
  await L.tap(page, 'All', { exact: true, wait: 1500 });
  await L.shot(page, '59-request-answered');
  await L.tap(page, 'Transfers', { exact: true, wait: 1500 });
  await L.dump(page, 'transfers');
  await L.shot(page, '60-transfers');
  await page.getByRole('button', { name: 'Receipt' }).first().click();
  await L.settle(page, 900);
  await L.shot(page, '61-receipt-choice');
  await s.browser.close();

  // Town confirms the eggs
  s = await L.open();
  page = s.page;
  await L.login(page, '0771000011', 'town-manager');
  await L.settle(page, 1500);
  await L.tap(page, 'Stock', { exact: true });
  await L.tap(page, 'Incoming', { exact: true, wait: 1200 });
  await L.dump(page, 'incoming');
  await L.tap(page, 'Confirm receipt', { exact: true, wait: 1800 });
  await L.shot(page, '62-eggs-received');
  await L.tap(page, 'Requests', { exact: true, wait: 1200 });
  await L.shot(page, '63-branch-request-answered');
  await s.browser.close();
  console.log('ok');
})().catch(e => { console.error('FAILED', e.message.slice(0, 900)); process.exit(1); });
