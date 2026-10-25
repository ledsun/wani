import { expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';

export function nativeParse(source) {
  const result = spawnSync('bundle', ['exec', 'ruby', 'scripts/parse.rb'], {
    input: source, encoding: 'utf8', timeout: 30_000,
  });
  expect(result.status, result.stderr).toBe(0);
  return JSON.parse(result.stdout);
}
export async function ready(page, file = 'slides.md') {
  await page.goto(`/?file=${encodeURIComponent(file)}`);
  await expect(page.locator('#status')).toHaveText('ready', { timeout: 90_000 });
}
