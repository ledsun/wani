import { test, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';

const fixtures = [
  '# Highlight\n\n```rb\nputs "日本語 <script> &"\n```\n\n<!-- notes:\n```js\nconst x = 1;\n```\n-->\n',
  '# Fallback\n\n```unknown\n<b>&</b>\n```\n\n```\n<script>plain</script>\n```\n',
  '# Empty\n\n```ruby\n```\n',

  '---\npage-footnote: Shared\n---\n# **Title** &amp; more\n\nBody\n\n<!-- page-footnote: Page footnote -->\n\n<!--\nnotes:\nPrivate **notes**\n-->\n\n---\n\n## Next\n\n### Extra',
  '# Code\r\n\r\n```md\r\n---\r\n<!-- notes: literal -->\r\n```\r\n\r\n---\r\n\r\nEnd',
  '# Safe\n\n<script>alert(1)</script>\n\n[bad](javascript:alert) ![bad](data:image/svg+xml,evil) [entity](jav&#x61;script:alert)',
  '',
  '---\npage-footnote: !ruby/object:Object {}\n---',
  '# Title\n\n<!-- notes: unclosed',
];

test('CRuby and browser wasm share the parser with identical models and errors', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  for (const source of fixtures) {
    const native = spawnSync('bundle', ['exec', 'ruby', 'test/support/parse.rb'], { input: source, encoding: 'utf8', timeout: 30_000 });
    expect(native.status, native.stderr).toBe(0);
    const wasm = await page.evaluate(source => {
      window.__paritySource = source;
      return window.rubyVM.eval(`begin; Wani::Core::Parser.new.parse(JS.global[:__paritySource].to_s).to_h.to_json; rescue Wani::Core::Parser::Error => error; {error: error.message}.to_json; end`).toString();
    }, source);
    expect(JSON.parse(wasm)).toEqual(JSON.parse(native.stdout));
  }
});
