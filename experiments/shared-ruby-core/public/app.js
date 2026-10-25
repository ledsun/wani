try {
  const response = await fetch('./shared-core.wasm');
  if (!response.ok) throw new Error(`wasm: HTTP ${response.status}`);
  const module = await WebAssembly.compile(await response.arrayBuffer());
  const { vm } = await window['ruby-wasm-wasi'].DefaultRubyVM(module);
  // The Ruby browser adapter uses the same Deck module as the native CLI.
  vm.eval('require "/app/browser"');
} catch (error) {
  document.querySelector('#status').textContent = `起動失敗: ${error.message}`;
}
