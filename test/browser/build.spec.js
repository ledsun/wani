import { test, expect } from '@playwright/test';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { DefaultRubyVM } from '@ruby/wasm-wasi/dist/node';

test('browser uses freshly packed core/browser sources and the pinned loader', async () => {
  const manifest = JSON.parse(await readFile('assets/build.json', 'utf8'));
  const paths = ['Gemfile.lock', 'scripts/build_wasm.rb', 'scripts/build_wasm_runtime.rb',
    'scripts/detect_wasm_extensions.mjs', 'assets/bootstrap.rb', 'templates/slides.md'];
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

test('packaged CRuby is 4.0.10 and compile_file selects Prism', async () => {
  const { vm } = await DefaultRubyVM(await WebAssembly.compile(await readFile('assets/wani.wasm')));
  expect(vm.eval('RUBY_VERSION').toString()).toBe('4.0.10');
  expect(vm.eval(`RubyVM::InstructionSequence.compile_file('/wani/lib/wani/browser/application.rb').to_a[4].fetch(:parser)`).toString()).toBe('prism');
});
