# MVP 実装前の追加検証 (#5–#8 / 親 #1)

4 件の検証を同じ実行環境にまとめる。製品実装ではなく、#1 の方式選定用の最小構成。

| Issue | 検証 | 結論 |
| --- | --- | --- |
| [#5](https://github.com/ledsun/wani/issues/5) | 独自 JS なしの起動 | PR #672 の固定コミットからビルドしたローダーを変更せずに同梱。HTML 属性でローカル wasm を指定する。 |
| [#6](https://github.com/ledsun/wani/issues/6) | レイアウトと PDF | Ruby による計測・文字サイズ探索・画像待機・印刷 DOM 生成を確認。 |
| [#7](https://github.com/ledsun/wani/issues/7) | 全画面と発表者画面 | Ruby のイベントから操作可能。postMessage の同期とブラウザーによる拒否の処理を確認。 |
| [#8](https://github.com/ledsun/wani/issues/8) | 安全な共通パーサー | YAML 安全解析・GFM コードブロック・ノート抽出・許可した要素の描画を両環境で確認。 |

詳しい結果と未検証範囲は `results/issue-5.md` ～ `results/issue-8.md` を参照。

## 再現手順

検証環境は Linux、Ruby 4.0.7、Bundler 4.0.23、Node.js 24.22.1、
Google Chrome 156.0.8078.47。PDF.js 6.4.299 はテストで PDF を読み取るためだけに使用し、
アプリケーションの PDF 生成には使用しない。

```sh
cd experiments/mvp-preflight
bundle config set --local path vendor/bundle
bundle install
npm ci
npm run build
CHROMIUM_PATH=/usr/bin/google-chrome npm test
npm run serve
```

http://127.0.0.1:8080 を開く。Playwright 付属 Chromium を使う場合は
`npx playwright install chromium` 後、`CHROMIUM_PATH` を付けずに `npm test` を実行する。
Node.js は PDF.js の要件により 22.13.0 以上（検証は24系）。
ビルド時に `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` をコピーするので、Linux の
DejaVu フォントが必要。別環境では `scripts/build.rb` のフォントコピー元を変更する。
初回は依存の取得にネットワーク接続が必要。構成済みローダーのページはその後ローカル通信のみで動く。

## 構成

- `lib/parser.rb`: ブラウザーに依存しない共通パーサー。独自モデルを Hash / Array / String で返す。
- `lib/application.rb`: Ruby による取得・DOM・レイアウト・全画面・ウィンドウ同期・印刷処理。
- `public/bootstrap.rb`: 公式 `text/ruby` ローダーが非同期実行する Ruby 起動コード。
- `public/index.html`: 既存 JS ローダーと `text/ruby` の宣言。独自アプリ JS は置かない。
- `scripts/build.rb`: 公開版 wasm に Ruby / gem を `rbwasm pack` で追加。
  PR #672 からビルドして同梱したローダーの SHA-256 を検証し、変更せずにコピーする。
  HTML の `data-ruby-wasm-url="./preflight.wasm"` で取得先を指定する。
- `scripts/parse.rb`: 同一パーサーをネイティブ CRuby で実行する CLI。
- `scripts/serve.mjs`: 検証用の静的サーバー。#1 用の Ruby サーバーではない。
- `test/`: 起動6件、レイアウト・PDF4件、ウィンドウ4件、パーサー10件。
- `third_party/ruby-wasm-loader/`: 未リリース PR の固定コミットからビルドした JS と LICENSE / NOTICE。
  出所・チェックサム・再ビルド手順を同梱する。

wasm と既存 JS アセットは生成物なので Git 管理対象外。`lib/` や gem を変更したら再ビルドする。
ブラウザーへ含める gem は kramdown 2.5.2、rexml 3.4.4、kramdown-parser-gfm 1.1.0 のみ。
YAML / Psych は公開版 Ruby WASM の標準ライブラリを使用する。

## 未リリースローダーの採用

PR [ruby/ruby.wasm#672](https://github.com/ruby/ruby.wasm/pull/672) のコミット
`dc6b0ffd5800ed9bfc49268ed8021d456f10ddf8` に固定する。
公式 npm 版ではなく、このコミットからビルドしたローダーを一時同梱する方式を採用した。
従来の URL 文字列置換は廃止し、独自アプリ JS は追加していない。

```html
<script src="runtime.pr672.js" data-ruby-wasm-url="./preflight.wasm"></script>
```

通常ビルドでは同梱済みローダーをコピーする。ローダー自体の再ビルドは
`npm run build:loader`。詳細は [同梱ファイルの説明](third_party/ruby-wasm-loader/README.md)。
公式リリースに機能が入ったら、同じ属性を維持してコピー元を公式 npm 版へ差し替える。

## 手動確認

自動テストは headless Chrome の実ブラウザーで実行する。通常の Chrome / Edge では以下も確認する。

1. `Fullscreen` または F で全画面、Esc / `Exit fullscreen` で解除する。
2. N / `Speaker notes` を操作し、現在の本文とノートが別ウィンドウに表示され、ページ移動で同期する。
   ポップアップを禁止した設定でも通知が出るか確認する。
3. `Print` / `Print with notes` の印刷ダイアログから PDF 保存する。
   用紙は CSS 指定を使い、ブラウザーのヘッダー・フッターを無効にする。
4. 通常版2ページ、ノート付き4ページの順番・画像・フッターを確認する。

自動 PDF 検査は Chromium の印刷機構 `page.pdf` を使用し、OS の印刷ダイアログ操作は未検証。
WSL2 上のサーバーへの Windows ブラウザーからの接続もこの環境では未検証。
PDF とスクリーンショットは `test-results/` に生成される（Git 管理対象外）。

## 初回検証の実行記録 (2026-10-25 / URL置換方式)

`CHROMIUM_PATH=/usr/bin/google-chrome npm test` : **21 passed (49.3s)**。
最終生成 wasm は 33,236,595 bytes、生成日時 2026-10-25 21:34:24 JST。
Ruby の組み込みソースの変更後に再生成したものを使用した。
依存欠落による起動失敗を検出する負の検証も行い、復元後に全件成功した。
生成物の実際の日時・サイズは `stat public/preflight.wasm` で確認できる。

## PR #672 採用後の実行記録 (2026-10-25)

`npm run build:loader` でソースの取得・既存 npm スクリプトによるビルド・SHA-256 の再現を確認。
`npm run build` で新しく生成した wasm と PR ローダーを使い、
`CHROMIUM_PATH=/usr/bin/google-chrome npm test` は **24 passed (1.0m)**。
生成 wasm は 33,236,595 bytes、生成日時 2026-10-25 22:41:42 JST。
HTML の wasm パスを一時的に壊すと起動テストが失敗することも確認し、復元後に起動テストを再実行した。
復元後の起動テストは **6 passed (15.6s)**。
ローダーの出所は `third_party/ruby-wasm-loader/provenance.json` を参照。
