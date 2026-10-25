# Ruby から DOM を操作するスライド技術検証 (#3)

Ruby で DOM 要素を生成し、kramdown の変換結果をスライドとして描画する。
左右キーとボタンのイベントを Ruby のブロックで受け取り、表示中のスライドを切り替える。
JavaScript は wasm の読み込みと Ruby の起動のみを担当する。

## 実行

必要なもの: Ruby 3.2 以上、Bundler 4.0.23、Node.js 22 以上。
初回の依存取得にはネットワーク接続が必要。

```sh
cd experiments/ruby-dom-slides
bundle config set --local path vendor/bundle
bundle install
npm ci
npm run build
npm run serve
```

http://127.0.0.1:8080 を開く。静的ファイルの配信だけで動作する。
生成物は Git 管理対象外のため、初回と `lib/` 変更後は必ずビルドする。
#2 の検証とは依存・生成物を別に持ち、単独で実行できる。

## 操作

- `---` だけの行でスライドを区切る。前後のスペースと CRLF にも対応。
- 「スライドを描画」で入力を再描画し、先頭に戻る。
- 左右キーまたは「前へ」「次へ」で移動する。先頭・末尾を超えない。
- 入力欄や編集可能要素内、および Ctrl / Alt / Meta を併用したキー操作は処理しない。
- 空入力は空のスライド 1 枚として表示する。

## 実装

`lib/slides.rb` が `require "js"` により DOM API を呼ぶ。
`createElement` / `appendChild` / `replaceChildren` でスライドを構成し、
`innerHTML` で変換結果を設定する。Ruby が現在位置を保持し、`hidden`・
ボタンの `disabled`・ページ数の `textContent` を更新する。
`addEventListener` に渡した Ruby ブロックが `keydown` / `click` を処理する。

`lib/markdown.rb` とビルド方法は #2 と同じ方式。
公開済み `@ruby/4.0-wasm-wasi@2.10.1` の標準ライブラリ入り wasm に、
kramdown 2.5.2・rexml 3.4.4・自作 Ruby コードを `rbwasm pack` で埋め込む。
ブラウザーから Ruby ソースや gem を個別に取得する必要はない。

[公式 DOM イベント処理例](https://github.com/ruby/ruby.wasm/blob/2.10.1/packages/npm-packages/ruby-wasm-wasi/example/lucky.html)
と [ruby.wasm の説明](https://ruby.github.io/ruby.wasm/) を参照。

## 検証

```sh
npx playwright install chromium
npm test
```

インストール済み Chrome を使う場合:

```sh
CHROMIUM_PATH=/usr/bin/google-chrome npm test
```

E2E では生成済み wasm を実際にロードし、次を確認する。

- 日本語・強調を含むスライドの DOM 描画と、1 枚のみの表示
- 左右キー・ボタンによる移動、ページ数、先頭と末尾の境界
- 入力欄内と Ctrl 併用時のキー操作を無視
- 入力変更後の再描画、ページ数と表示位置のリセット、イベントの継続動作
- CRLF と空入力、Ruby/gem の個別取得や外部通信がないこと

## 検証結果 (2026-10-25)

Ruby から DOM 描画とキーボードイベント処理を実装できることを確認した。
Ruby 4.0.7 / Node.js 24.22.1 の環境でビルドし、Chrome で E2E 2 件が成功
（最終実行: 各 2.2 秒・2.0 秒、全体 5.3 秒）。
生成 wasm は 33,215,182 bytes、生成日時は 2026-10-25 20:56:31 JST。
空入力のテストで見つかった `1 / 0` 表示を修正し、修正後の wasm を再生成して検証した。
読み込み先を存在しない wasm に一時変更すると HTTP 404 による起動失敗を検出し、
復元後に 2 件とも成功した。

## 制約

自分で用意した信頼できる Markdown を扱う技術検証。
HTML をそのまま DOM に挿入するため、未信頼の入力を扱う場合はサニタイズが必要。
区切り行は単純な文字列分割なので、コードブロック内の `---` も区切りになる。
GFM・構文ハイライト・大きな文書の性能・Worker 化・他ブラウザーは対象外。
