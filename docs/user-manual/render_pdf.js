// Renders index.html to Cream-POS-User-Manual.pdf (needs `npm i playwright`).
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.goto('file://' + path.join(__dirname, 'index.html'));
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(800);
  await p.pdf({ path: path.join(__dirname, 'Cream-POS-User-Manual.pdf'), preferCSSPageSize: true, printBackground: true });
  await b.close();
})();
