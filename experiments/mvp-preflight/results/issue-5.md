# #5: 独自 JavaScript なしの起動

## 結論

Ruby の起動・Markdown の取得・解析・描画を、独自アプリ JS を置かずに実行できた。
ただし **公式ローダーを無変更のまま、同梱の独自 wasm をローカル取得する方式は確認できていない**。
固定した公開版 `@ruby/4.0-wasm-wasi@2.10.1` は wasm の取得先が CDN に固定されている。

## 検証

- 公式 `browser.script.iife.js` をそのまま読み込む `/original.html` で、CDN への実リクエスト発行を確認。
  テストではその通信を意図的に遮断する。CDN 取得成功やオンラインでの起動を実証するテストではない。
- 既存ローダーの wasm 取得 URL だけを `./preflight.wasm` に変更して生成。
  テストで元の JS との差分がその1箇所だけであることを照合。
- HTML の `type="text/ruby" data-eval="async"` から Ruby を起動し、Ruby の fetch / await で Markdown を取得。
- リクエストが同一 origin 内だけで、独自 JS の追加ロードがないこと、Markdown の404表示を確認。
- 組み込みアプリの require 先を一時的に壊すと起動テストが失敗し、復元後は成功した。

## #1 への提案

取得先の変更を「既存ランタイムの配布時設定」として許容するか、本実装前に決める必要がある。
許容する場合、変更箇所・バージョン・ライセンスを管理し、未知のローダーには適用しない。
既存 JS の変更も禁止する場合は、公式側の取得先指定 API の追加や、最小限の起動 JS の例外許可など、
別の方針が必要。無変更で要件を満たしたとは扱わない。

根拠: 固定版 npm パッケージ内のローダーと
[公式ローダーのソース](https://github.com/ruby/ruby.wasm/blob/main/packages/npm-packages/ruby-wasm-wasi/src/browser.script.ts)。
