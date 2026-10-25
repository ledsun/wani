import { test, expect } from '@playwright/test';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';

test('browser uses freshly packed core/browser sources and the pinned loader', async () => {
  const manifest = JSON.parse(await readFile('assets/build.json', 'utf8'));
  const paths = [];
  for (const folder of ['core', 'browser']) {
    for (const name of await readdir(`lib/wani/${folder}`)) {
      if (name.endsWith('.rb')) paths.push(`lib/wani/${folder}/${name}`);
    }
  }
  const source = createHash('sha256');
  for (const path of paths.sort()) { source.update(path); source.update(await readFile(path)); }
  expect(manifest.source_sha256).toBe(source.digest('hex'));
  expect(manifest.wasm_sha256).toBe(createHash('sha256').update(await readFile('assets/wani.wasm')).digest('hex'));
  expect(await readFile('assets/runtime.pr672.js')).toEqual(await readFile('third_party/ruby-wasm-loader/browser.script.iife.js'));
});
