import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

test('body wrapping uses rendered width at twenty fullwidth characters and respects breaks', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({
    body: readFileSync(new URL('../fixtures/wrapping/slides.md', import.meta.url), 'utf8'),
  }));
  await page.goto('/#slide=2');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  const results = [];
  for (let index = 0; index < 6; index++) {
    if (index) await page.keyboard.press('ArrowRight');
    results.push(await page.locator('.slide.active .body').evaluate(body => {
      const lines = [...body.querySelectorAll('[data-wani-line]')];
      return {
        wraps: lines.map(line => line.style.whiteSpace),
        rows: lines.map(line => {
          const range = document.createRange();
          range.selectNodeContents(line);
          return new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size;
        }),
        fits: body.scrollWidth <= body.clientWidth + 1 && body.scrollHeight <= body.clientHeight + 1,
      };
    }));
  }
  expect(results.map(result => result.wraps)).toEqual([
    ['nowrap'], ['nowrap'], ['normal'], ['nowrap'],
    ['nowrap', 'nowrap'], ['nowrap', 'normal'],
  ]);
  expect(results[0].rows).toEqual([1]);
  expect(results[1].rows).toEqual([1]);
  expect(results[2].rows[0]).toBeGreaterThan(1);
  expect(results.every(result => result.fits)).toBe(true);
  await expect(page.locator('#stage strong')).toHaveText('綺麗なUI');
  await expect(page.locator('#warnings')).toBeHidden();
});

test('table fitting keeps short cells on one line and wraps long cells', async ({ page }) => {
  const short = 'あ'.repeat(15);
  const long = 'あ'.repeat(30);
  const wideRow = value => `| ${Array(9).fill(value).join(' | ')} |`;
  await page.route('**/talk/slides.md', route => route.fulfill({
    body: `# 表紙

---

# ファイルサイズ

| 名前 | 圧縮前 | 圧縮後 |
| --- | --- | --- |
| ${short} | \`35,182,903\` B | ${short} |
| ${long} | 20,502,957 B | ${short} |

---

# 列が多い表

${wideRow('見出し')}
${wideRow('---')}
${wideRow(short)}
`,
  }));
  await page.goto('/#slide=2');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  const body = page.locator('.slide.active .body');
  const row = body.locator('tbody tr').first();
  await expect(row.locator('td [data-wani-line]')).toHaveCount(3);
  for (const cell of await row.locator('td [data-wani-line]').all()) {
    await expect(cell).toHaveCSS('white-space', 'nowrap');
  }
  const longCell = body.locator('tbody tr').nth(1).locator('td [data-wani-line]').first();
  await expect(longCell).toHaveCSS('white-space', 'normal');
  expect(await longCell.evaluate(line => line.getClientRects().length)).toBeGreaterThan(1);
  expect(await body.evaluate(node => node.scrollWidth <= node.clientWidth + 1)).toBe(true);
  await expect(row.locator('code')).toHaveText('35,182,903');
  await page.keyboard.press('ArrowRight');
  const crowdedCell = body.locator('td [data-wani-line]').first();
  await expect(crowdedCell).toHaveCSS('white-space', 'normal');
  const crowdedRows = await body.locator('td [data-wani-line]').evaluateAll(lines =>
    lines.map(line => line.getClientRects().length));
  expect(Math.max(...crowdedRows)).toBeGreaterThan(1);
  await expect(page.locator('#warnings')).toBeHidden();
});
