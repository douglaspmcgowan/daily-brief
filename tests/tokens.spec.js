// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const style = (html.match(/<style>([\s\S]*?)<\/style>/) || [])[1] || '';

/** Body of every top-level rule whose selector contains `:root` or the dark theme selector. */
function tokenBlocks() {
  const blocks = [];
  const re = /(:root(?::not\(\[data-theme="light"\]\))?(?:\[data-theme="dark"\])?)\s*\{([^}]*)\}/g;
  let m;
  while ((m = re.exec(style))) blocks.push({ sel: m[1], body: m[2] });
  return blocks;
}

for (const scheme of ['light', 'dark']) {
  test.describe(`tokens in ${scheme} mode`, () => {
    test.use({ colorScheme: /** @type {'light'|'dark'} */ (scheme) });

    test('type roles resolve to the two faces at 17px body', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const r = await page.evaluate(() => ({
        mast: getComputedStyle(document.querySelector('.mast-title')).fontFamily,
        summary: getComputedStyle(document.querySelector('.summary')).fontFamily,
        body: getComputedStyle(document.body).fontSize,
      }));
      expect(r.mast.startsWith('"Playfair Display"')).toBe(true);
      expect(r.summary.startsWith('"PT Serif"')).toBe(true);
      expect(r.body).toBe('17px');
    });

    test('every border radius is square', async ({ page }) => {
      await page.goto('/index.html');
      await page.waitForSelector('.item');
      const round = await page.evaluate(() => {
        const out = new Set();
        document.querySelectorAll('body *').forEach((e) => {
          const r = getComputedStyle(e).borderRadius;
          if (r !== '0px') out.add(`${e.tagName}.${e.className}=${r}`);
        });
        return [...out];
      });
      expect(round).toEqual([]);
    });

    test(':root exposes the new tokens and none of the retired ones', async ({ page }) => {
      await page.goto('/index.html');
      const t = await page.evaluate(() => {
        const cs = getComputedStyle(document.documentElement);
        const has = (n) => cs.getPropertyValue(n).trim() !== '';
        return {
          present: ['--sheet', '--caution', '--dur-1', '--rule-double', '--ease-in', '--wrap', '--measure',
            '--font-display', '--font-body', '--status-new', '--status-saved', '--radius-0'].filter((n) => !has(n)),
          retired: ['--link', '--warn', '--card', '--radius-pill', '--ink-soft', '--anchor-soft', '--on-anchor',
            '--shadow-firm', '--radius-round', '--radius-14'].filter(has),
        };
      });
      expect(t.present).toEqual([]);
      expect(t.retired).toEqual([]);
    });
  });
}

test('each palette defines at most nine hex colours', () => {
  const blocks = tokenBlocks();
  expect(blocks.length).toBe(3);
  for (const b of blocks) {
    const hex = new Set(b.body.match(/#[0-9a-fA-F]{3,8}\b/g) || []);
    expect(hex.size, b.sel).toBeLessThanOrEqual(9);
  }
});

test('the stylesheet carries no literal hex outside token blocks, no ease-in-out, linear or !important', () => {
  let rest = style;
  for (const b of tokenBlocks()) rest = rest.replace(b.body, '');
  expect(rest.match(/#[0-9a-fA-F]{3,8}\b/g) || []).toEqual([]);
  expect(style).not.toContain('ease-in-out');
  expect(style).not.toContain('linear');
  expect(style).not.toContain('!important');
  expect(rest.match(/\b\d*\.?\d+m?s\b(?!\s*var)/g) || []).toEqual([]);
});

test('the page loads the font stylesheet with preconnect', () => {
  expect(html).toContain('rel="preconnect" href="https://fonts.googleapis.com"');
  expect(html).toContain('fonts.googleapis.com/css2?family=Playfair+Display');
});
