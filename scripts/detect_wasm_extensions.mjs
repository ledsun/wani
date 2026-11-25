import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';

const { values, positionals } = parseArgs({
  options: { wasm: { type: 'string' }, help: { type: 'boolean', short: 'h' } },
  allowPositionals: true,
});

if (values.help) {
  console.log('Usage: node scripts/detect_wasm_extensions.mjs [--wasm path] [slides.md ...]');
  console.log('Prints the comma-separated Ruby --with-ext list observed when loading Wani and parsing slides.');
  process.exit(0);
}

const wasm = values.wasm ?? new URL('../assets/wani.wasm', import.meta.url);
const sample = new URL('../templates/slides.md', import.meta.url);
const binary = readFileSync(wasm);
const { DefaultRubyVM } = await import('@ruby/wasm-wasi/dist/node');
const { vm } = await DefaultRubyVM(await WebAssembly.compile(binary));
const loadedExtensions = () => vm.eval(
  '$LOADED_FEATURES.select { |feature| feature.end_with?(".so") }.join("\\n")',
).toString().split('\n');

const builtins = new Set(loadedExtensions());
vm.eval(`
  $LOAD_PATH.unshift(*Dir.glob('/wani/bundle/*/lib'))
  require '/wani/lib/wani/browser/application'
`);

for (const path of [sample, ...positionals]) {
  // Pass Markdown as data so Ruby never evaluates its contents as source code.
  globalThis.waniExtensionProbeMarkdown = readFileSync(path, 'utf8');
  try {
    vm.eval('Wani::Core::Parser.new.parse(JS.global[:waniExtensionProbeMarkdown].to_s)');
  } finally {
    delete globalThis.waniExtensionProbeMarkdown;
  }
}

// These loaded feature names differ from their Ruby ext/ paths.
const extensionPaths = new Map([
  ['date_core.so', ['date']],
  ['json/ext/generator.so', ['json', 'json/generator']],
  ['json/ext/parser.so', ['json', 'json/parser']],
]);
// Ruby links encodings and transcoders separately. The JS bridge is a gem.
const observed = loadedExtensions().filter(feature =>
  !builtins.has(feature) && feature !== 'js.so' && !/^(enc|trans)\//.test(feature),
);
const extensions = new Set(observed.flatMap(feature => extensionPaths.get(feature) ?? [feature.slice(0, -3)]));
console.log([...extensions].sort().join(','));
