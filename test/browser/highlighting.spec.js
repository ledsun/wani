import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const source = `# Code

\`\`\`ruby
# 日本語
def hello
  puts "Hello, Wani!"
end
\`\`\`

<!-- notes:
\`\`\`js
const answer = 42;
\`\`\`
-->

---

# HTML as text

\`\`\`html
<script>alert(1)</script>
\`\`\`

\`\`\`unknown-language
<b>plain & safe</b>
\`\`\`
`;

async function open(page, markdown) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: markdown }));
  await page.goto('/#slide=1');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

test('highlighting is styled before fitting and shared with speaker notes and PDF', async ({ page }, info) => {
  await page.addInitScript(() => {
    window.highlightMeasurements = [];
    const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollWidth');
    Object.defineProperty(Element.prototype, 'scrollWidth', { ...descriptor, get() {
      const keyword = this.matches('.body') && this.querySelector('.highlight .k');
      if (keyword) window.highlightMeasurements.push(getComputedStyle(keyword).color);
      return descriptor.get.call(this);
    } });
  });
  await open(page, source);
  const keyword = page.locator('#stage .highlight .k').first();
  const color = await keyword.evaluate(node => getComputedStyle(node).color);
  expect(color).not.toBe(await page.locator('.slide.active .body').evaluate(node => getComputedStyle(node).color));
  const measured = await page.evaluate(() => window.highlightMeasurements);
  expect(measured.length).toBeGreaterThan(0);
  expect(measured.every(value => value === color)).toBe(true);
  await expect(page.locator('#warnings')).toBeHidden();
  await expect(page.locator('#stage .slide').nth(1).locator('pre').nth(1)).toHaveText('<b>plain & safe</b>');
  await expect(page.locator('#stage script, #stage pre b')).toHaveCount(0);

  const popupPromise = page.waitForEvent('popup');
  await page.locator('#speaker').click();
  const popup = await popupPromise;
  await expect(popup.locator('#body .k').first()).toHaveCSS('color', color);
  await expect(popup.locator('#notes .kd')).toHaveText('const');
  await expect(popup.locator('#notes .kd')).toHaveCSS('color', color);
  await page.locator('#next').click();
  await expect(popup.locator('#current')).toHaveText('HTML as text');
  await expect(popup.locator('#body pre').first()).toHaveText('<script>alert(1)</script>');
  await expect(popup.locator('#body script')).toHaveCount(0);

  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toContainText('4 ページ');
  await expect(page.locator('#print-pages .print-sheet').nth(1).locator('.highlight .kd')).toHaveCSS('color', color);
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('#print-pages .k').first()).toHaveCSS('color', color);
  const pdf = await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('highlighting.pdf') });
  const task = getDocument({ data: new Uint8Array(pdf), useSystemFonts: true });
  try {
    const document = await task.promise;
    expect(document.numPages).toBe(4);
    const texts = [];
    for (let i = 1; i <= document.numPages; i++) {
      const text = await (await document.getPage(i)).getTextContent();
      texts.push(text.items.map(item => item.str).join(''));
    }
    expect(texts[0]).toContain('Hello, Wani!');
    expect(texts[1]).toContain('const answer = 42;');
    expect(texts[2]).toContain('<script>alert(1)</script>');
  } finally { await task.destroy(); }
});

test('plain code leaves Rouge unloaded and language-tagged code loads it on demand', async ({ page }) => {
  await open(page, '# Plain\n\n`inline`\n\n```\nputs "plain"\n```\n');
  expect(await page.evaluate(() => window.rubyVM.eval('defined?(Rouge).to_s').toString())).toBe('');
  await expect(page.locator('#stage .highlight')).toHaveCount(0);
  const html = await page.evaluate(() => window.rubyVM.eval('Wani::Core::Parser.new.parse("```rb\\nputs 1\\n```\\n").slides.first.html').toString());
  expect(html).toContain('<pre class="highlight">');
  expect(html).toContain('<span class=');
});
