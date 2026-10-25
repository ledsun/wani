# ruby.wasm PR #672 ローダーの一時同梱

この `browser.script.iife.js` は公式 npm リリースではない。
[ruby/ruby.wasm#672](https://github.com/ruby/ruby.wasm/pull/672) の
[`dc6b0ffd5800ed9bfc49268ed8021d456f10ddf8`](https://github.com/ledsun/ruby.wasm/tree/dc6b0ffd5800ed9bfc49268ed8021d456f10ddf8)
から、既存の npm ビルド手順で生成したファイルを変更せずに同梱している。
`LICENSE` / `NOTICE` も同コミットから取得した。

## 再ビルド

検証ディレクトリから次を実行する。curl、tar、Ruby、Node.js / npm とネットワーク接続が必要。
再現確認に使用した Node.js は24.22.1。

```sh
npm run build:loader
```

`scripts/build_loader.rb` が一時ディレクトリで以下を実行する。

1. 固定コミットのアーカイブを取得し、`provenance.json` の SHA-256 と照合する。
2. アーカイブ内の package-lock.json に従い、必要なワークスペースへ `npm ci --ignore-scripts` を実行する。
3. 共通バインディングの `build:tsc` と Ruby 4.0 パッケージの `build:rollup` を実行する。
4. 成果物の SHA-256 が記録値と同じであることを確認して同梱ファイルを更新する。

ソースの追加修正や JS の文字列置換は行わない。通常の `npm run build` は、この同梱ファイルの
チェックサムを確認して `public/runtime.pr672.js` にコピーするだけなので、上流ソースの再取得は不要。
wasm 本体は npm の `@ruby/4.0-wasm-wasi@2.10.1` を基に Wani の Ruby / gem を pack する。
JS バインディングと公開版 wasm の組み合わせはこのリポジトリのブラウザーテストで検証する。

## 公式リリースへの移行

PR のマージだけでなく、機能を含む公式 npm パッケージの公開を待つ。
公開後は採用するバージョンを固定し、ビルドスクリプトのコピー元を公式パッケージへ変更する。
HTML の `data-ruby-wasm-url` は維持し、同梱ファイル・再ビルドスクリプト・出所情報を削除する。
起動・属性省略時の CDN 取得・失敗時の非フォールバックを含む回帰テストを実行する。
