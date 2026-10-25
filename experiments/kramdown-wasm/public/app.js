const status = document.querySelector('#status');
const button = document.querySelector('#convert');
try {
  const response = await fetch('./kramdown.wasm');
  if (!response.ok) throw new Error(`wasm: HTTP ${response.status}`);
  const module = await WebAssembly.compile(await response.arrayBuffer());
  const { vm } = await window['ruby-wasm-wasi'].DefaultRubyVM(module);
  vm.eval('require "/app/markdown"; require "js"');
  button.addEventListener('click', () => {
    try {
      // Read text through JS interop: input never becomes Ruby source code.
      const result = vm.eval(`Wani::Markdown.render(JS.global[:document].getElementById("markdown")[:value].to_s)`);
      document.querySelector('#output').textContent = result.toString();
      status.textContent = '変換しました';
    } catch (error) {
      status.textContent = `変換失敗: ${error.message}`;
    }
  });
  button.disabled = false;
  status.textContent = 'Ruby / kramdown の準備ができました';
} catch (error) {
  status.textContent = `起動失敗: ${error.message}`;
}
