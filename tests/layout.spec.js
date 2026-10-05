// @ts-check
const { test, expect } = require('@playwright/test');

const cols = (el) => getComputedStyle(el).gridTemplateColumns.split(' ').filter(Boolean).length;

async function open(page, width) {
  await page.setViewportSize({ width, height: 900 });
  await page.goto('/index.html');
  await page.waitForSelector('.item');
}

test('at 1440 the summary holds the 68ch measure and the story has two columns', async ({ page }) => {
  await open(page, 1440);
  const r = await page.evaluate(() => {
    const s = document.querySelector('.summary');
    const probe = document.createElement('span');
    probe.textContent = '0';
    probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre';
    s.appendChild(probe);
    const zero = probe.getBoundingClientRect().width;
    probe.remove();
    const item = s.closest('.item');
    return { chars: s.getBoundingClientRect().width / zero,
      cols: getComputedStyle(item).gridTemplateColumns.split(' ').filter(Boolean).length };
  });
  expect(r.chars).toBeLessThanOrEqual(68);
  expect(r.cols).toBe(2);
});

for (const w of [768, 375]) {
  test(`at ${w} the story is one column and prose stays 17px`, async ({ page }) => {
    await open(page, w);
    const r = await page.evaluate(() => ({
      cols: getComputedStyle(document.querySelector('.item')).gridTemplateColumns.split(' ').filter(Boolean).length,
      fs: getComputedStyle(document.querySelector('.summary')).fontSize,
      rbtl: getComputedStyle(document.querySelector('.rbtl')).fontSize,
    }));
    expect(r.cols).toBe(1);
    expect(r.fs).toBe('17px');
    expect(r.rbtl).toBe('17px');
  });
}

test('with the reader pane open at 1440 the story falls to one column', async ({ page }) => {
  await open(page, 1440);
  await page.locator('.title[data-reader]').first().click();
  await expect(page.locator('#reading-pane')).toHaveClass(/open/);
  await page.waitForTimeout(500);
  const c = await page.evaluate(() => getComputedStyle(document.querySelector('.item')).gridTemplateColumns.split(' ').filter(Boolean).length);
  expect(c).toBe(1);
});

for (const w of [375, 768, 1440]) {
  test(`no horizontal scroll at ${w}`, async ({ page }) => {
    await open(page, w);
    const d = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    expect(d[0]).toBe(d[1]);
  });
}

test('the front page is two columns at 1440 and one at 375, sidebar first when stacked', async ({ page }) => {
  await open(page, 1440);
  expect(await page.evaluate(() => getComputedStyle(document.querySelector('.front-grid')).gridTemplateColumns.split(' ').filter(Boolean).length)).toBe(2);
  await open(page, 375);
  const r = await page.evaluate(() => {
    const g = document.querySelector('.front-grid');
    const side = g.querySelector('.insight-card');
    const idx = g.querySelector('.whatsnew');
    return { cols: getComputedStyle(g).gridTemplateColumns.split(' ').filter(Boolean).length,
      sideFirst: !side || side.getBoundingClientRect().top < idx.getBoundingClientRect().top };
  });
  expect(r.cols).toBe(1);
  expect(r.sideFirst).toBe(true);
});

test('references run in 3, 2 and 1 columns', async ({ page }) => {
  const n = async (w) => { await open(page, w); return page.evaluate(() => getComputedStyle(document.querySelector('.ref-list')).columnCount); };
  expect(await n(1440)).toBe('3');
  expect(await n(768)).toBe('2');
  expect(await n(375)).toBe('1');
});

test('the masthead date has no leading zero', async ({ page }) => {
  await open(page, 1440);
  expect(await page.locator('.mast-sub b').innerText()).not.toMatch(/ 0\d,/);
});

test('the reader pane arrives on 320ms and reduced motion zeroes it', async ({ page }) => {
  await open(page, 1440);
  const dur = () => page.evaluate(() => getComputedStyle(document.querySelector('#reading-pane')).transitionDuration);
  await page.locator('.title[data-reader]').first().click();
  await expect(page.locator('#reading-pane')).toHaveClass(/open/);
  expect((await dur()).split(',').map((s) => s.trim())[0]).toBe('0.32s');
  await page.keyboard.press('Escape');
  await expect(page.locator('#reading-pane')).not.toHaveClass(/open/);
  expect((await dur()).split(',').map((s) => s.trim())[0]).toBe('0.2s');

  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.locator('.title[data-reader]').first().click();
  await expect(page.locator('#reading-pane')).toHaveClass(/open/);
  expect((await dur()).split(',').map((s) => s.trim()).every((s) => s === '0s')).toBe(true);
});

test('every transition-duration is on the token scale', async ({ page }) => {
  await open(page, 1440);
  await page.locator('.title[data-reader]').first().click();
  const bad = await page.evaluate(() => {
    const ok = new Set(['0s', '0.12s', '0.2s', '0.32s']);
    const out = new Set();
    for (const el of document.querySelectorAll('*')) {
      for (const pseudo of [null, '::after', '::before']) {
        for (const d of getComputedStyle(el, pseudo).transitionDuration.split(',')) {
          if (!ok.has(d.trim())) out.add(d.trim());
        }
      }
    }
    return [...out];
  });
  expect(bad).toEqual([]);
});

test('keyboard path: search, escape, j/k, mark read, open reader, escape', async ({ page }) => {
  await open(page, 1440);
  await page.keyboard.press('/');
  await expect(page.locator('#q')).toBeFocused();
  await page.keyboard.type('a');
  await page.keyboard.press('Escape');
  await expect(page.locator('#q')).not.toBeFocused();
  await page.keyboard.press('j');
  await page.keyboard.press('j');
  await page.keyboard.press('k');
  await expect(page.locator('.cluster.focused')).toHaveCount(1);
  await page.keyboard.press('m');
  await expect(page.locator('.cluster.focused .read-btn')).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('o');
  await expect(page.locator('#reading-pane')).toHaveClass(/open/);
  await page.keyboard.press('Escape');
  await expect(page.locator('#reading-pane')).not.toHaveClass(/open/);
});
