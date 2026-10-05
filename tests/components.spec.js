// @ts-check
const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

/** button, input, summary and a[href] on the branch base (3066f3f), before P2 touched any control. */
const BASE_CONTROL_COUNT = 639;

test('every svg.ico is a Phosphor 256 viewBox icon', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  const bad = await page.evaluate(() =>
    [...document.querySelectorAll('svg.ico')]
      .filter((s) => s.getAttribute('viewBox') !== '0 0 256 256' || s.getAttribute('fill') !== 'currentColor')
      .map((s) => s.outerHTML.slice(0, 80)));
  expect(bad).toEqual([]);
  expect(await page.locator('svg.ico').count()).toBeGreaterThan(0);
});

test('read, save and snooze each set aria-pressed and swap to the fill icon', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  const first = page.locator('.cluster').first();
  for (const sel of ['.read-btn', '.rl-btn', '.snooze-btn']) {
    const btn = first.locator(sel);
    await expect(btn).toHaveAttribute('aria-pressed', 'false');
    await expect(btn.locator('svg.ico.fill')).toHaveCount(0);
    const before = await btn.locator('svg.ico path').getAttribute('d');
    await btn.click();
    await expect(btn).toHaveAttribute('aria-pressed', 'true');
    await expect(btn.locator('svg.ico.fill')).toHaveCount(1);
    expect(await btn.locator('svg.ico path').getAttribute('d')).not.toBe(before);
  }
});

test('the active section tab is pressed and filled with ink', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  const tab = page.locator('.pill[data-filter="design"]');
  await tab.click();
  await expect(tab).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.pill[data-filter="all"]')).toHaveAttribute('aria-pressed', 'false');
  const read = () => page.evaluate(() => {
    const t = document.querySelector('.pill[data-filter="design"]');
    const probe = document.createElement('i');
    probe.style.backgroundColor = 'var(--ink)';
    document.body.appendChild(probe);
    const ink = getComputedStyle(probe).backgroundColor;
    probe.remove();
    return getComputedStyle(t).backgroundColor === ink;
  });
  // the fill transitions over --dur-1, so poll until it settles
  await expect.poll(read).toBe(true);
});

test('the front-page index and the editor sidebar have no tint, gradient or box', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  for (const sel of ['.insight-card', '.whatsnew']) {
    const c = await page.evaluate((s) => {
      const cs = getComputedStyle(document.querySelector(s));
      return { bg: cs.backgroundColor, img: cs.backgroundImage, radius: cs.borderRadius, top: cs.borderTopStyle, side: cs.borderLeftWidth };
    }, sel);
    expect(c.bg).toBe('rgba(0, 0, 0, 0)');
    expect(c.img).toBe('none');
    expect(c.radius).toBe('0px');
    expect(c.top).toBe('double');
    expect(c.side).toBe('0px');
  }
});

test('no element carries both a border and a box-shadow', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  await page.click('#help-btn');
  const both = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('body *').forEach((e) => {
      const c = getComputedStyle(e);
      const border = ['Top', 'Right', 'Bottom', 'Left'].some((s) => parseFloat(c['border' + s + 'Width']) > 0 && c['border' + s + 'Style'] !== 'none');
      if (border && c.boxShadow !== 'none') out.push(`${e.tagName}.${e.className}`);
    });
    return out;
  });
  expect(both).toEqual([]);
});

test('no control was removed', async ({ page }) => {
  await page.goto('/index.html');
  expect(await page.locator('button, input, summary, a[href]').count()).toBe(BASE_CONTROL_COUNT);
});

test('a search with no match shows the empty state and a Clear filters button', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  await page.fill('#q', 'zzzzqq-no-such-story');
  await expect(page.locator('#no-results')).toBeVisible();
  await expect(page.locator('#no-results').getByRole('button', { name: 'Clear filters' })).toBeVisible();
});

test('the shortcuts dialog is a level 2 sheet that Escape closes and returns focus', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  await page.focus('#help-btn');
  await page.keyboard.press('Enter');
  const dlg = page.locator('#kbd-overlay [role="dialog"]');
  await expect(dlg).toBeVisible();
  const s = await dlg.evaluate((e) => {
    const c = getComputedStyle(e);
    return { shadow: c.boxShadow, border: c.borderTopWidth, bg: c.backgroundColor };
  });
  expect(s.shadow).not.toBe('none');
  expect(s.border).toBe('0px');
  await page.keyboard.press('Escape');
  await expect(page.locator('#kbd-overlay')).toHaveCount(0);
  await expect(page.locator('#help-btn')).toBeFocused();
});

test('the view toggles are pressed buttons', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('.item');
  await page.click('#rl-pill');
  await expect(page.locator('#rl-pill')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#arc-pill')).toHaveAttribute('aria-pressed', 'false');
});

for (const scheme of /** @type {const} */ (['light', 'dark'])) {
  test.describe(`axe in ${scheme} mode`, () => {
    test.use({ colorScheme: scheme });
    test('zero serious or critical violations', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const { violations } = await new AxeBuilder({ page }).analyze();
      const blocking = violations
        .filter((v) => v.impact === 'serious' || v.impact === 'critical')
        .map((v) => `${v.id} (${v.impact}) on ${v.nodes.length} node(s)`);
      expect(blocking).toEqual([]);
    });
  });
}
