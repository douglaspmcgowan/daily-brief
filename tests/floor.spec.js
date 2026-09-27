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
