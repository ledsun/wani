import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const source = '---\nfooter: 日本語フッター\n---\n# 日本語プレゼンテーション\n\n漢字・ひらがな・カタカナと English 123。\n\n**太字の本文**も同じフォントです。\n\n<!-- notes: 日本語の発表者ノート。 -->';

async function ready(page) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: source, contentType: 'text/plain; charset=utf-8' }));
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

async function renderedFonts(page, selector) {
  const client = await page.context().newCDPSession(page);
  try {
    await client.send('DOM.enable');
    await client.send('CSS.enable');
    const { root } = await client.send('DOM.getDocument');
    const { nodeId } = await client.send('DOM.querySelector', { nodeId: root.nodeId, selector });
    return (await client.send('CSS.getPlatformFontsForNode', { nodeId })).fonts;
  } finally {
    await client.detach();
  }
}

test('bundled Regular and Bold render Japanese before layout and embed in PDF', async ({ page }, info) => {
  const requests = [];
  page.on('request', request => requests.push(new URL(request.url())));
  // Delay Bold: a hidden title must not be fitted using its fallback font.
  await page.route('**/IBMPlexSansJP-Bold.woff2', async route => {
    await new Promise(resolve => setTimeout(resolve, 250));
    await route.continue();
  });
  await ready(page);
  const titleFonts = await renderedFonts(page, '.slide.active .title');
  const bodyFonts = await renderedFonts(page, '.slide.active .body p');
  const boldFonts = await renderedFonts(page, '.slide.active .body strong');
  for (const fonts of [titleFonts, bodyFonts, boldFonts]) {
    expect(fonts.length).toBeGreaterThan(0);
    expect(fonts.every(font => font.isCustomFont && font.familyName === 'IBM Plex Sans JP')).toBe(true);
  }
  expect(titleFonts.some(font => font.postScriptName === 'IBMPlexSansJP-Bold')).toBe(true);
  expect(bodyFonts.some(font => font.postScriptName === 'IBMPlexSansJP')).toBe(true);
  await expect(page.locator('#warnings')).toBeHidden();
  expect(requests.every(url => url.origin === new URL(page.url()).origin)).toBe(true);
  expect(requests.filter(url => url.pathname.endsWith('.woff2')).map(url => url.pathname).sort()).toEqual([
    '/assets/fonts/IBMPlexSansJP-Bold.woff2', '/assets/fonts/IBMPlexSansJP-Regular.woff2',
  ]);
  const pdfBuffer = await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('japanese.pdf') });
  const task = getDocument({ data: new Uint8Array(pdfBuffer), useSystemFonts: false });
  try {
    const pdf = await task.promise;
    expect(pdf.numPages).toBe(1);
    const pdfPage = await pdf.getPage(1);
    const text = await pdfPage.getTextContent();
    // Chromium may map shared kanji glyphs to compatibility radicals (⽇ vs 日).
    const extracted = text.items.map(item => item.str).join('').normalize('NFKC');
    expect(extracted).toContain('日本語プレゼンテーション');
    expect(extracted).toContain('日本語フッター');
    // Font names plus FontFile2 streams establish that glyphs are embedded, not OS-only.
    const raw = pdfBuffer.toString('latin1');
    expect(raw).toMatch(/\/BaseFont\s*\/(?:[A-Z]{6}\+)?IBMPlexSansJP(?:[\s/]|$)/);
    expect(raw).toContain('IBMPlexSansJP-Bold');
    expect(raw).toContain('/FontFile2');
  } finally {
    await task.destroy();
  }
  await page.screenshot({ path: info.outputPath('japanese.png') });
});

test('speaker window uses the same bundled Japanese font', async ({ page }) => {
  await ready(page);
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#notes')).toContainText('日本語の発表者ノート');
  await speaker.evaluate(() => document.fonts.ready);
  const fonts = await renderedFonts(speaker, '#notes p');
  expect(fonts.some(font => font.isCustomFont && font.familyName === 'IBM Plex Sans JP')).toBe(true);
  await speaker.close();
});

test('font failure warns and retains a usable fallback presentation', async ({ page }) => {
  await page.route('**/*.woff2', route => route.abort());
  await ready(page);
  await expect(page.locator('#warnings')).toContainText('フォントを読み込めませんでした');
  await expect(page.locator('.slide.active .title')).toHaveText('日本語プレゼンテーション');
});
