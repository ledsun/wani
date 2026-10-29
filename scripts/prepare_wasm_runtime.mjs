import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DefaultRubyVM } from '@ruby/wasm-wasi/dist/node';

// Copy from the pinned WASM distribution, never from the host Ruby installation.
const [source, destination] = process.argv.slice(2);
const { vm } = await DefaultRubyVM(await WebAssembly.compile(readFileSync(source)));
const files = JSON.parse(vm.eval(`
  require 'json'
  root = '/usr/local/lib/ruby/4.0.0'
  # Keep complete components: some dependencies are required only while rendering.
  components = %w[date json pathname psych strscan uri yaml
                  cgi delegate forwardable set singleton time
                  unicode_normalize]
  paths = components.flat_map do |name|
    ["#{root}/#{name}.rb", *Dir.glob("#{root}/#{name}/**/*")]
  end
  paths += Dir.glob('/bundle/gems/js-*/lib/**/*')
  JSON.generate(paths.uniq.select { |path| File.file?(path) }.map do |path|
    [path, [File.binread(path)].pack('m0')]
  end)
`).toString());
for (const [path, contents] of files) {
  const target = join(destination, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, Buffer.from(contents, 'base64'));
}
// Ruby's startup hook normally adds all bundled gems. Only JS is needed here.
mkdirSync(join(destination, 'bundle'), { recursive: true });
writeFileSync(join(destination, 'bundle/setup.rb'),
  "$LOAD_PATH.unshift(*Dir.glob('/bundle/gems/js-*/lib'))\n");
