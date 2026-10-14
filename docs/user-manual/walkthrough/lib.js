const { chromium } = require('playwright');
const path = require('path');
const SHOTS = path.join(__dirname, 'shots');

async function open() {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
  const ctx = await browser.newContext({
    locale: 'en-US', timezoneId: 'Africa/Kampala',
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 300)));
  await page.goto(process.env.APP_URL || 'http://127.0.0.1:8081/');
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(2500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1200);
  return { browser, page, errors };
}

const settle = (page, ms = 900) => page.waitForTimeout(ms);

async function dump(page, label = '') {
  const rows = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .map(e => (e.getAttribute('role') || '-') + ' | ' + ((e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\n/g, ' / ').slice(0, 90)))
    .filter(r => r.split('|')[1].trim().length > 0));
  console.log('--- semantics ' + label + '\n' + [...new Set(rows)].join('\n'));
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(SHOTS, name + '.png') });
}

// Tap something by its visible text / accessible name.
async function tap(page, text, opts = {}) {
  const exact = opts.exact ?? false;
  const loc = page.getByText(text, { exact }).or(page.getByRole('button', { name: text, exact })).or(page.getByRole('tab', { name: text, exact })).or(page.getByRole('checkbox', { name: text, exact }));
  await loc.nth(opts.nth ?? 0).click({ timeout: 8000 });
  await settle(page, opts.wait ?? 900);
}

// Focus a text field by its label and type into it.
async function type(page, label, value, nth = 0) {
  const box = page.getByRole('textbox', { name: label });
  await box.nth(nth).click({ timeout: 8000 });
  await page.keyboard.press('End');
  for (let i = 0; i < 14; i++) await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 15 });
  await settle(page, 300);
}

async function login(page, phone, password) {
  await type(page, 'Phone number', phone);
  await type(page, 'Password', password);
  await tap(page, 'Sign in', { exact: true, wait: 2500 });
}

// Open the navigation drawer and go to a Back Office section.
async function goTo(page, section, menuShot) {
  await tap(page, 'Open navigation menu', { exact: true, wait: 700 });
  if (menuShot) await shot(page, menuShot);
  await page.getByRole('button', { name: new RegExp('^' + section + ' Tab') }).click({ timeout: 8000 });
  await settle(page, 1800);
}

// Stocking > Purchase: open the searchable picker, search, choose.
async function chooseItem(page, name) {
  await page.getByRole('button', { name: /^Item/ }).first().click({ timeout: 8000 });
  await settle(page, 700);
  if (name === '+new') {
    await page.getByRole('button', { name: /^Add a new item/ }).click({ timeout: 8000 });
  } else {
    await type(page, 'Search items', name);
    await page.getByRole('button', { name: new RegExp('^' + name) }).first().click({ timeout: 8000 });
  }
  await settle(page, 800);
}

// Open a dropdown (by its label) and choose an option.
async function pick(page, dropdown, option, nth = 0) {
  await page.getByRole('button', { name: dropdown }).nth(nth).click({ timeout: 8000 });
  await settle(page, 700);
  await page.getByRole('menuitem', { name: option, exact: typeof option === 'string' }).first().click({ timeout: 8000 });
  await settle(page, 600);
}

// Click the button that sits on the same row as some text (for list rows
// whose trailing button has no name of its own).
async function clickOnRow(page, rowText, buttonName) {
  const row = page.getByRole('group', { name: new RegExp(rowText) }).first();
  await row.waitFor({ timeout: 8000 });
  const box = await row.boundingBox();
  const buttons = page.getByRole('button', { name: buttonName });
  const n = await buttons.count();
  let best = null, bestDist = 1e9;
  for (let i = 0; i < n; i++) {
    const b = await buttons.nth(i).boundingBox();
    if (!b) continue;
    const d = Math.abs((b.y + b.height / 2) - (box.y + box.height / 2));
    if (d < bestDist) { bestDist = d; best = buttons.nth(i); }
  }
  if (!best || bestDist > 40) throw new Error('no ' + buttonName + ' on row ' + rowText);
  await best.click();
  await settle(page, 900);
}

module.exports = { clickOnRow, goTo, chooseItem, pick, open, settle, dump, shot, tap, type, login };
