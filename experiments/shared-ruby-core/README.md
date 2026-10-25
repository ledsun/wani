# CRuby / ruby.wasm の共通 Ruby モジュール技術検証 (#4)

`lib/wani/deck.rb` の同じソースファイルを、ネイティブ CRuby の CLI と
ブラウザー上の ruby.wasm の両方で使う。Markdown 分割・kramdown による HTML 変換・
現在位置・移動の境界を共通モジュールが管理する。プラットフォーム判定や JS 依存は持たない。

## 実行

必要なもの: Ruby 3.2 以上、Bundler 4.0.23、Node.js 22 以上。
初回の依存取得にはネットワーク接続が必要。

```sh
cd experiments/shared-ruby-core
bundle config set --local path vendor/bundle
bundle install
npm ci
npm run build
npm run serve
```

http://127.0.0.1:8080 を開く。`---` の行でスライドを区切り、左右キーまたは
前へ・次へボタンで移動する。入力欄の編集後は「スライドを描画」で先頭に戻る。
#2・#3 と依存や生成物を別に持ち、単独で実行できる。

ネイティブ CLI は標準入力から JSON を受け取り、初期状態と各移動後の状態を JSON 配列で返す。

```sh
bundle exec ruby scripts/cli.rb <<'JSON'
{"markdown":"# First\n\n---\n\n# Second", "moves":[1,1,-1]}
JSON
```

各状態は `html`、0 始まりの `index`、`total`、`previous_disabled`、`next_disabled` を含む。
ブラウザーをインストールしなくても CLI は動く。

## 共有の仕組み

- `lib/wani/deck.rb`: 両環境で共用する Pure Ruby モジュール。
- `scripts/cli.rb`: `require_relative` で共通モジュールを読み込み、標準入出力を処理する。
- `lib/browser.rb`: 共通モジュールを読み込み、DOM 更新とキー・クリックイベントを処理する。
  wasm 内の gem load path と `require "js"` はこのアダプターに限定する。
- `scripts/build.rb`: 共通モジュールを含む `lib/` を加工せずに `rbwasm pack` で埋め込む。
  公開版 Ruby 4.0 ランタイムと kramdown 2.5.2 / rexml 3.4.4 を使用する。
- `public/app.js`: wasm の読み込みとブラウザー用 Ruby アダプターの起動。

共通モジュールを変更した場合は必ず `npm run build` で wasm を再生成する。
CLI は作業ツリーのソースを直接使い、ブラウザーはビルド時点の同じソースを使う。
生成物・依存ディレクトリは Git 管理対象外。

## 同一結果の検証

```sh
npx playwright install chromium
npm test
```

インストール済み Chrome を利用する場合:

```sh
CHROMIUM_PATH=/usr/bin/google-chrome npm test
```

各テストは実際の CLI を子プロセスとして実行する。その JSON 出力と、生成済み wasm を
読み込んだブラウザーの DOM を操作ごとに比較する。
HTML は末尾改行を含めて一致を確認し、ページ数・表示位置・前後ボタンの状態も照合する。
共通の誤実装だけでテストが通らないよう、初期状態には固定の期待値も用意する。

4 ケース: 日本語と強調を含む複数ページ、空文書、空白付き CRLF 区切り、空スライド。
先頭・末尾を超える移動、再描画での状態リセット、Ruby/gem の個別取得や外部通信が
発生しないことも確認する。

## 検証結果 (2026-10-25)

ネイティブ CRuby とブラウザーの ruby.wasm で同一の Pure Ruby モジュールを共有し、
4 ケースの HTML とページ状態が一致することを確認した。
Ruby 4.0.7 / Node.js 24.22.1 / Chrome で実行し、比較 E2E 4 件が成功
（最終実行 10.9 秒）。生成 wasm は 33,215,224 bytes、生成日時は
2026-10-25 21:11:20 JST。共有ファイルを作成した後のビルドで検証した。
wasm の読み込み先を一時的に壊すと、CLI が動いていても比較テストは
HTTP 404 による起動失敗を検出した。復元後に 4 件とも成功した。

## 制約

信頼できる Markdown を対象とする。ブラウザーでは HTML をそのまま DOM に挿入する。
区切り行は単純な文字列分割なのでコードブロック内でも区切りになる。
本検証で共有するのは文書変換と状態管理。DOM・ファイル・ネットワーク API など、
実行環境に依存する機能全般の互換性は検証していない。他ブラウザーや性能検証も対象外。
