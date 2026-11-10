import { test, expect } from '@playwright/test';

test('places an image and text on either side in slides and print', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: `# Cover

---

# Right

Some text on the left.

![bg right Diagram](images/wide.svg)

---

# Left

![bg left Diagram](images/wide.svg)

- Text on the right
` }));
  await page.goto('/#slide=2');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  for (const [slide, side] of [[2, 'right'], [3, 'left']]) {
    await page.evaluate(number => { location.hash = `slide=${number}`; }, slide);
    const body = page.locator('.slide.active .body');
    await expect(body).toHaveClass(/image-columns/);
    await expect(body.locator('img')).toHaveAttribute('alt', 'Diagram');
    const geometry = await body.evaluate(node => {
      const image = node.querySelector('.image-column-image').getBoundingClientRect();
      const text = node.querySelector('.image-column-text').getBoundingClientRect();
      return { image: image.left, text: text.left, fits: node.scrollHeight <= node.clientHeight + 1 && node.scrollWidth <= node.clientWidth + 1 };
    });
    expect(geometry.fits).toBe(true);
    expect(side === 'left' ? geometry.image < geometry.text : geometry.image > geometry.text).toBe(true);
  }
  await expect(page.locator('#warnings')).toBeHidden();
  await page.locator('#print').click();
  await expect(page.locator('#print-pages .image-columns')).toHaveCount(2);
});
