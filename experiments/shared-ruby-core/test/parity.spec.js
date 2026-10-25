import { test, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';

const cases = [
  {
    name: 'Japanese Markdown and navigation boundaries',
    markdown: '# 共通コード\n\n**Ruby** & wasm\n\n---\n\n# 二枚目\n\n- one\n- two\n\n---\n\n最後',
    moves: [-1, 1, 1, 1, -1, -1, -1], total: 3,
    firstHTML: '<h1 id="section">共通コード</h1>\n\n<p><strong>Ruby</strong> &amp; wasm</p>\n',
  },
  { name: 'empty document', markdown: '', moves: [-1, 1], total: 1, firstHTML: '' },
  {
    name: 'CRLF separators with whitespace',
    markdown: '# Start\r\n\r\n \t--- \t\r\n\r\n`#{raise "injected"}`',
    moves: [1, 1, -1], total: 2, firstHTML: '<h1 id="start">Start</h1>\n',
  },
  { name: 'empty slides', markdown: '---\n---', moves: [1, 1, 1, -1], total: 3, firstHTML: '' },
];

function nativeSnapshots(input) {
  // Execute the real CLI, using the same core file that the build embeds.
  const result = spawnSync('bundle', ['exec', 'ruby', 'scripts/cli.rb'], {
    input: JSON.stringify(input), encoding: 'utf8', timeout: 30_000,
  });
  expect(result.error).toBeUndefined();
  expect(result.status, result.stderr).toBe(0);
  return JSON.parse(result.stdout);
}

async function expectState(page, state) {
  await expect(page.locator('#slides')).toHaveJSProperty('innerHTML', state.html);
  await expect(page.locator('#position')).toHaveText(`${state.index + 1} / ${state.total}`);
  await expect(page.locator('#previous')).toHaveJSProperty('disabled', state.previous_disabled);
  await expect(page.locator('#next')).toHaveJSProperty('disabled', state.next_disabled);
}

for (const input of cases) {
  test(`native CRuby and browser wasm agree: ${input.name}`, async ({ page }) => {
    const snapshots = nativeSnapshots(input);
    expect(snapshots).toHaveLength(input.moves.length + 1);
    expect(snapshots[0]).toEqual({
      html: input.firstHTML + '\n', index: 0, total: input.total,
      previous_disabled: true, next_disabled: input.total === 1,
    });
    const errors = [];
    const requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => requests.push(new URL(request.url())));
    await page.goto('/');
    await expect(page.locator('#status')).toHaveText('共通 Ruby モジュールの準備ができました', { timeout: 90_000 });
    await page.locator('#markdown').fill(input.markdown);
    await page.locator('#render').click();
    await expectState(page, snapshots[0]);
    for (const [index, delta] of input.moves.entries()) {
      await page.keyboard.press(delta > 0 ? 'ArrowRight' : 'ArrowLeft');
      await expectState(page, snapshots[index + 1]);
    }
    // Replacing the document resets the shared core to the CLI's initial state.
    await page.locator('#render').click();
    await expectState(page, snapshots[0]);
    expect(errors).toEqual([]);
    expect(requests.some(url => url.pathname === '/shared-core.wasm')).toBe(true);
    expect(requests.every(url => url.origin === 'http://127.0.0.1:8080')).toBe(true);
    expect(requests.filter(url => /\.(rb|gem)$/.test(url.pathname))).toEqual([]);
  });
}
