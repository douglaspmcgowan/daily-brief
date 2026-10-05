// @ts-check
const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

test('the primary surface has no serious or critical accessibility violations', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  const { violations } = await new AxeBuilder({ page }).analyze();
  const blocking = violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}) on ${v.nodes.length} node(s)`);
  expect(blocking).toEqual([]);
});

test('keyboard focus paints a visible ring', async ({ page }) => {
  await page.goto('/index.html');
  await page.keyboard.press('Tab');
  const ring = await page.evaluate(() => {
    const el = /** @type {HTMLElement} */ (document.activeElement);
    const c = getComputedStyle(el);
    return {
      tag: el.tagName,
      focusVisible: el.matches(':focus-visible'),
      width: c.outlineWidth,
      style: c.outlineStyle,
      color: c.outlineColor,
    };
  });
  expect(ring.focusVisible).toBe(true);
  expect(ring.style).toBe('solid');
  expect(ring.width).toBe('2px');
  expect(ring.color).toBe('rgb(200, 72, 43)');
});

test.describe('dark mode follows the operating system', () => {
  test.use({ colorScheme: 'dark' });
  test('a reader with no saved choice gets the dark palette', async ({ page }) => {
    await page.goto('/index.html');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(bg).toBe('rgb(28, 25, 20)');
  });
});

test.describe('light mode stays the default', () => {
  test.use({ colorScheme: 'light' });
  test('a reader on a light system gets the paper palette', async ({ page }) => {
    await page.goto('/index.html');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(bg).toBe('rgb(246, 243, 236)');
  });
});

test('reduced motion switches transitions and animations off', async ({ page }) => {
  // Playwright's reducedMotion context option does not reach the page in this
  // Chromium build (matchMedia reported false), so emulate the media feature
  // through CDP, which the page does see.
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setEmulatedMedia', {
    features: [{ name: 'prefers-reduced-motion', value: 'reduce' }],
  });
  await page.goto('/index.html');
  const state = await page.evaluate(() => ({
    matches: matchMedia('(prefers-reduced-motion: reduce)').matches,
    cardBtn: getComputedStyle(document.querySelector('.card-btn')).transitionDuration,
    extLink: getComputedStyle(document.querySelector('.ext-link')).transitionDuration,
    paneLoading: getComputedStyle(document.querySelector('.pane-loading')).animationName,
  }));
  expect(state.matches).toBe(true);
  expect(state.cardBtn).toBe('0s');
  expect(state.extLink).toBe('0s');
  expect(state.paneLoading).toBe('none');
});

for (const width of [375, 768, 1440]) {
  test.describe(`at ${width}px`, () => {
    test.use({ viewport: { width, height: 900 } });

    test('the page does not scroll sideways', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const w = await page.evaluate(() => ({
        sw: document.documentElement.scrollWidth,
        cw: document.documentElement.clientWidth,
      }));
      expect(w.sw).toBeLessThanOrEqual(w.cw);
    });

    test('every interactive control is at least 44 by 44', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const small = await page.evaluate(() =>
        [...document.querySelectorAll('a[href],button,input,summary,select,textarea')]
          .map((e) => ({ e, r: e.getBoundingClientRect() }))
          .filter(({ r }) => r.width > 0 && r.height > 0 && (r.width < 43.9 || r.height < 43.9))
          .map(({ e }) => `${e.tagName}.${e.className}`));
      expect(small).toEqual([]);
    });

    test('the home screen uses at most three font sizes', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const sizes = await page.evaluate(() => {
        const set = new Set();
        document.querySelectorAll('body *').forEach((e) => {
          if ([...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()))
            set.add(getComputedStyle(e).fontSize);
        });
        return [...set];
      });
      expect(sizes.length).toBeLessThanOrEqual(3);
    });
  });
}

test('the page has one h1 and the identity head tags', async ({ page }) => {
  await page.goto('/index.html');
  expect(await page.locator('h1').count()).toBe(1);
  expect(await page.locator('meta[name="theme-color"]').count()).toBeGreaterThan(0);
  expect(await page.locator('meta[property="og:image"]').count()).toBe(1);
});

test('a filter with no match says so and offers a way out', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  await page.fill('#q', 'zzzzqq-no-such-story');
  await expect(page.locator('#no-results')).toBeVisible();
  await expect(page.locator('#no-results-msg')).toContainText('No stories match');
  await page.click('#clear-filters');
  await expect(page.locator('#no-results')).toBeHidden();
  expect(await page.locator('.cluster:visible').count()).toBeGreaterThan(0);
});

test('no chrome uses a middle dot, an eyebrow label or monospace outside code', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  const found = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('.mast-sub, .meta, .new-src, .controls, footer').forEach((e) => {
      if (/[\u00b7\u2022]/.test(e.textContent)) out.push('dot in ' + e.className);
    });
    document.querySelectorAll('body *').forEach((e) => {
      if (e.closest('code,pre')) return;
      const c = getComputedStyle(e);
      if (c.textTransform === 'uppercase') out.push('uppercase ' + e.className);
      if (/mono/i.test(c.fontFamily) && e.textContent.trim()) out.push('mono ' + e.className);
    });
    return out;
  });
  expect(found).toEqual([]);
});
