import { test, expect } from '@playwright/test';
import { nativeParse, ready } from './helpers.js';

const fixtures = [
  {
    name: 'front matter, title, notes, footer and image',
    source: '---\nfooter: "Shared footer"\n---\n# Title\n\nText **bold**.\n\n![alt](wide.svg)\n\n<!-- notes:\nPrivate **notes**.\n-->\n\n---\n\n## Second\n\n### Extra heading',
    check(model) {
      expect(model.footer).toBe('Shared footer');
      expect(model.slides).toHaveLength(2);
      expect(model.slides[0]).toMatchObject({ title: 'Title', images: ['wide.svg'], notes_html: '<p>Private <strong>notes</strong>.</p>' });
      expect(model.slides[0].html).not.toContain('Private');
      expect(model.warnings).toEqual(['slide 2: additional heading']);
    },
  },
  {
    name: 'fenced and indented code keep separator and notes literals',
    source: '# Code\n\n```text\n---\n<!-- notes: literal -->\n```\n\n~~~\n---\n~~~\n\n    ---\n\n---\n\nLast',
    check(model) {
      expect(model.slides).toHaveLength(2);
      expect(model.slides[0].html).toContain('&lt;!-- notes: literal --&gt;');
      expect(model.slides[0].notes_html).toBe('');
    },
  },
  {
    name: 'raw HTML and dangerous URL attributes are removed',
    source: '# Safe\n\n<script>alert(1)</script>\n\n<img src="x" onerror="alert(2)">\n\n[bad](javascript:alert) ![bad](data:image/svg+xml,boom) [entity](jav&#x61;script:alert) [ok](https://example.com/)\n\n<!-- notes: <script>alert(3)</script> -->',
    check(model) {
      const html = model.slides[0].html + model.slides[0].notes_html;
      expect(html).not.toMatch(/<script|onerror|javascript:|data:image/);
      expect(html).toContain('href="https://example.com/"');
    },
  },
  { name: 'unsafe YAML object tag', source: '---\nfooter: !ruby/object:Object {}\n---\n# Test', error: 'invalid front matter' },
  { name: 'YAML alias', source: '---\na: &x hello\nfooter: *x\n---\n# Test', error: 'invalid front matter' },
  { name: 'invalid YAML syntax', source: '---\nfooter: [broken\n---\n# Test', error: 'invalid front matter' },
  { name: 'invalid footer type', source: '---\nfooter: [one, two]\n---\n# Test', error: 'footer must be a string' },
  { name: 'unclosed front matter', source: '---\nfooter: title', error: 'unclosed front matter' },
  { name: 'unclosed notes', source: '# Title\n\n<!-- notes: unclosed', error: 'unclosed notes' },
  {
    name: 'notes keep internal separators',
    source: '# Title\n\n<!-- notes:\nBefore\n\n---\n\nAfter\n-->\n\n---\n\n# Next',
    check(model) {
      expect(model.slides).toHaveLength(2);
      expect(model.slides[0].notes_html).toContain('<hr>');
    },
  },
];

for (const fixture of fixtures) {
  test(`CRuby/wasm parser parity: ${fixture.name}`, async ({ page }) => {
    const native = nativeParse(fixture.source);
    if (fixture.error) expect(native).toEqual({ error: fixture.error });
    else fixture.check(native);
    await page.route('**/input.md', route => route.fulfill({ body: fixture.source, contentType: 'text/plain; charset=utf-8' }));
    if (fixture.error) {
      await page.goto('/?file=input.md');
      await expect(page.locator('#status')).toContainText(fixture.error, { timeout: 90_000 });
    } else {
      await ready(page, 'input.md');
      expect(JSON.parse(await page.locator('#model').textContent())).toEqual(native);
      await expect(page.locator('#stage script, #stage [onerror]')).toHaveCount(0);
    }
  });
}
