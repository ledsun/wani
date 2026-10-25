# kramdown を ruby.wasm に組み込む技術検証 (#2)

kramdown とその依存 rexml、自作の Pure Ruby コード `lib/markdown.rb` を
単一の `public/kramdown.wasm` に埋め込み、ブラウザーの JavaScript から呼び出す。
Ruby のソースや gem をブラウザーから個別に取得する必要はない。

## 実行

必要なもの: Ruby 3.2 以上、Bundler 4.0.23、Node.js 22 以上。
依存の初回取得にはネットワーク接続が必要。

```sh
cd experiments/kramdown-wasm
bundle config set --local path vendor/bundle
bundle install
npm ci
npm run build
npm run serve
```

http://127.0.0.1:8080 を開き、Markdown を入力して「HTML に変換」を押す。
静的ファイルの配信のみで動作し、サーバー側で Ruby を実行しない。
生成した wasm と JS ランタイムは Git の管理対象外なので、初回はビルドする。

## ブラウザーテスト

```sh
npx playwright install chromium
npm test
```

インストール済み Chrome を使う場合:

```sh
CHROMIUM_PATH=/usr/bin/google-chrome npm test
```

生成済みの wasm を HTTP 経由で読み込み、初期表示の日本語・見出し・強調、
リストへの再変換、Ruby の補間に似た文字列、空入力を検証する。
Ruby/gem の個別取得や外部へのリクエストが発生しないことも確認する。
`lib/` や gem を変更した場合は `npm run build` を実行してからテストする。

## 検証結果 (2026-10-25)

組み込んだ Pure Ruby コードと kramdown をブラウザーから利用できることを確認した。
Ruby 4.0.7 / Node.js 24.22.1 の環境でビルドし、Chrome で上記 E2E 1 件が成功
（テスト本体 2.1 秒、全体 3.1 秒）。生成物は 33,213,923 bytes。
生成日時は 2026-10-25 20:45:01 JST。
読み込み先を存在しない wasm に一時変更すると、HTTP 404 による起動失敗を
テストが検出した。変更を戻して成功することも確認した。

## 構成と制約

- `scripts/build.rb`: 公開版 `@ruby/4.0-wasm-wasi@2.10.1` の標準ライブラリ入り wasm に、
  `ruby_wasm@2.10.1` の `rbwasm pack` で Ruby コードを追加する。CRuby 自体の再コンパイルは不要。
- `lib/markdown.rb`: kramdown 2.5.2 / rexml 3.4.4 の load path を設定し、`Wani::Markdown.render` を公開する。
- `public/app.js`: `DefaultRubyVM` を起動し、Ruby の JS interop で入力を読み取って変換する。
- 入力は kramdown 形式。GFM パーサーと構文ハイライトは組み込んでいない。
- 結果は HTML ソースとして表示する。kramdown の出力には入力中の HTML が含まれるため、
  将来プレビュー表示を追加する場合はサニタイズが必要。
- wasm の初期ロードと同期変換はメインスレッドで行う。大きな文書の性能や Worker 化、
  ネイティブ拡張を持つ gem、他ブラウザーは本検証の範囲外。

方式は [ruby.wasm のパッケージング例](https://github.com/ruby/ruby.wasm#quick-example-how-to-package-your-ruby-application-as-a-wasi-application)
と [ブラウザー API](https://github.com/ruby/ruby.wasm/blob/2.10.1/packages/npm-packages/ruby-wasm-wasi/src/browser.ts) を参照。
