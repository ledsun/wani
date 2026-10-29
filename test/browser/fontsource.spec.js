import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const live = process.env.WANI_FONTSOURCE_PROJECT;
const family = live ? 'Noto Sans JP Variable' : 'Fixture Font';
const source = `---\nfont: ${live ? 'Noto Sans JP' : family}\n---\n# 日本語プレゼンテーション\n\n本文 **太字**\n\n---\n\n# 隠れた文字\n\n𠮷野家と髙橋`;

async function setup(page, { missing = false, broken = false, markdown = source } = {}) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: markdown }));
  if (!live) {
    await page.route('**/talk/fonts.json', route => route.fulfill({ json: missing ? {} : {
      fixture: { family, css_family: family, stylesheet: 'fonts/fixture/font.css', styles: ['normal'] },
    } }));
    await page.route('**/talk/fonts/fixture/font.css', route => route.fulfill({ contentType: 'text/css', body:
      [400, 500, 700].map(weight => `@font-face { font-family: "${family}"; font-weight: ${weight}; src: url('./files/${weight}.woff2') format('woff2'); }`).join('\n'),
    }));
    await page.route('**/talk/fonts/fixture/files/*.woff2', async route => {
      if (broken) return route.abort();
      await new Promise(resolve => setTimeout(resolve, 400));
      const bold = route.request().url().includes('700.woff2');
      await route.fulfill({ contentType: 'font/woff2', body: fs.readFileSync(`assets/fonts/IBMPlexSansJP-${bold ? 'Bold' : 'Regular'}.woff2`) });
    });
  }
  // Internet is unavailable; the local presentation server remains available.
  await page.route(/https?:\/\/(?!127\.0\.0\.1:)/, route => route.abort());
  await page.goto('/#slide=1');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

test('project font loads before fitting hidden slides and is embedded in PDF offline', async ({ page }, info) => {
  const earlyMeasurements = [];
  await page.addInitScript(() => {
    window.fontMeasurements = [];
    const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollWidth');
    Object.defineProperty(Element.prototype, 'scrollWidth', { ...descriptor, get() {
      if (this.matches('.title, .body')) window.fontMeasurements.push({ family: getComputedStyle(this).fontFamily, status: document.fonts.status });
      return descriptor.get.call(this);
    } });
  });
  await setup(page);
  earlyMeasurements.push(...await page.evaluate(() => window.fontMeasurements));
  expect(earlyMeasurements.length).toBeGreaterThan(0);
  expect(earlyMeasurements.every(item => item.family.includes(family) && item.status === 'loaded')).toBe(true);
  await expect(page.locator('#warnings')).toBeHidden();
  await expect(page.locator('.slide.active .title')).toHaveCSS('font-weight', '700');
  await expect(page.locator('.slide.active .body')).toHaveCSS('font-weight', '400');
  const client = await page.context().newCDPSession(page);
  await client.send('DOM.enable');
  await client.send('CSS.enable');
  async function assertActualFont(selector) {
    const { root } = await client.send('DOM.getDocument');
    const { nodeId } = await client.send('DOM.querySelector', { nodeId: root.nodeId, selector });
    const { fonts } = await client.send('CSS.getPlatformFontsForNode', { nodeId });
    expect(fonts.length).toBeGreaterThan(0);
    expect(fonts.every(font => font.isCustomFont && font.familyName.startsWith(live ? 'Noto Sans JP' : 'IBM Plex Sans JP'))).toBe(true);
  }
  await assertActualFont('.slide.active .title');
  await assertActualFont('.slide.active .body p');
  await expect(page.locator('.slide.active .title')).toHaveCSS('font-family', new RegExp(family));
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('.slide.active .title')).toHaveText('隠れた文字');
  if (live) await assertActualFont('.slide.active .body p');
  await client.detach();
  const pdf = await page.pdf({ path: info.outputPath('fontsource.pdf'), preferCSSPageSize: true });
  expect(pdf.toString('latin1')).toContain(live ? 'NotoSansJP' : 'IBMPlexSansJP');
  expect(pdf.toString('latin1')).toContain('/FontFile2');
  const task = getDocument({ data: new Uint8Array(pdf), useSystemFonts: false });
  try {
    const document = await task.promise;
    expect(document.numPages).toBe(2);
    const text = await (await document.getPage(1)).getTextContent();
    expect(text.items.map(item => item.str).join('').normalize('NFKC')).toContain('日本語プレゼンテーション');
  } finally { await task.destroy(); }
  await page.screenshot({ path: info.outputPath('fontsource.png') });
});

test('unregistered font warns and falls back', async ({ page }) => {
  test.skip(!!live, 'Mock-only error scenario');
  await setup(page, { missing: true });
  await expect(page.locator('#warnings')).toContainText('未登録のフォント');
  await expect(page.locator('.slide.active .title')).toHaveCSS('font-family', /IBM Plex Sans JP/);
});

test('project font download failure warns and falls back before layout', async ({ page }) => {
  test.skip(!!live, 'Mock-only error scenario');
  await setup(page, { broken: true });
  await expect(page.locator('#warnings')).toContainText('フォントを読み込めませんでした');
  await expect(page.locator('.slide.active .title')).toHaveCSS('font-family', /IBM Plex Sans JP/);
});

for (const customFont of [true, false]) {
  test(`font weights apply before fitting and to print pages (custom font: ${customFont})`, async ({ page }) => {
    await page.addInitScript(() => {
      window.measuredWeights = [];
      const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollWidth');
      Object.defineProperty(Element.prototype, 'scrollWidth', { ...descriptor, get() {
        if (this.matches('.title, .body')) window.measuredWeights.push({
          title: this.matches('.title'), weight: getComputedStyle(this).fontWeight, status: document.fonts.status,
        });
        return descriptor.get.call(this);
      } });
    });
    await setup(page, { markdown: `---\n${customFont ? `font: ${live ? 'Noto Sans JP' : family}\n` : ''}title-weight: 500\nbody-weight: ${customFont ? 400 : 300}\n---\n# Title\n\nBody **bold**\n\n---\n\n# Hidden title\n\nHidden body` });
    const measurements = await page.evaluate(() => window.measuredWeights);
    expect(measurements.length).toBeGreaterThan(0);
    expect(measurements.every(item => item.weight === (item.title ? '500' : (customFont ? '400' : '300')) && item.status === 'loaded')).toBe(true);
    await expect(page.locator('.slide.active .title')).toHaveCSS('font-weight', '500');
    await expect(page.locator('.slide.active .body')).toHaveCSS('font-weight', customFont ? '400' : '300');
    await expect(page.locator('.slide.active strong')).toHaveCSS('font-weight', customFont ? '700' : '400');
    await page.emulateMedia({ media: 'print' });
    await expect(page.locator('#print-pages .title').first()).toHaveCSS('font-weight', '500');
    await expect(page.locator('#print-pages .body').first()).toHaveCSS('font-weight', customFont ? '400' : '300');
  });
}
