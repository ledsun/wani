try {
  const response = await fetch('./slides.wasm');
  if (!response.ok) throw new Error(`wasm: HTTP ${response.status}`);
  const module = await WebAssembly.compile(await response.arrayBuffer());
  const { vm } = await window['ruby-wasm-wasi'].DefaultRubyVM(module);
  // Rendering, DOM updates and event callbacks are all implemented in Ruby.
  vm.eval('require "/app/slides"');
} catch (error) {
  document.querySelector('#status').textContent = `起動失敗: ${error.message}`;
}
