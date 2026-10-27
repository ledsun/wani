# WANI の開発・検証

WANI — Web Assembly Narrative Illustrator のビルドとテストの手順です。
アプリケーションの利用方法は [README](../README.md)、内部構成は [アーキテクチャ](architecture.md) を参照してください。

## 開発環境とビルド

ソースからのビルドには Ruby 3.2 以上、Node.js 22.13 以上、npm、Bundler が必要です。
リポジトリのルートで実行してください。

```sh
bundle config set --local path vendor/bundle
bundle install
npm ci
bundle exec rake build:wasm
```

## テストとパッケージ

```sh
bundle install
npm ci
bundle exec rake build:wasm
bundle exec rake test
npx playwright install chromium
npm test
bundle exec ruby scripts/smoke_package.rb
```

既存 Chrome を使う場合は `CHROMIUM_PATH=/usr/bin/google-chrome npm test`。
自動テストは手動確認用サーバーとの競合を避け、既定で18000番を使います（`WANI_TEST_PORT` で変更可能）。
Rubyソースを変更した場合は必ず wasm を再ビルドしてください。テストがソースと生成物のハッシュを照合します。
ソース管理では生成 wasm を除外していますが、`gem build` の成果物には含めます。
`bundle exec rake package` は再ビルド・Rubyテスト・gem作成をまとめて実行します。

RubyテストはCLI・共通ロジック・ファイル配信・パストラバーサル・シンボリックリンク・終了処理を検証します。
ブラウザーテストは実際の Ruby サーバーと生成した wasm を使い、操作・レイアウト・各画像形式・ノート同期・
印刷PDFのページ数／寸法／内容と、CRubyとの解析結果一致を確認します。
PDF.js は生成済みPDFのテスト検査にだけ使い、製品のPDF生成には使いません。
`smoke_package.rb` は一時環境へ gem をインストールして `new` → `check` → `serve` と正常終了を確認し、後片付けします。

## 手動検証

自動検証環境は Linux / Ruby 4.0.7 / Node.js 24.22.1 / Chrome 156.0.8078.47。
通常ブラウザーの印刷ダイアログ、Windows・WSL2、Edge / Firefox / Safari はこの環境では未検証です。
以下を対象環境で確認してください。

1. WSL2 内で `wani serve` を起動し、Windows 側の Chrome / Edge で http://localhost:8000/ を開く。
   環境のポート転送設定に応じて `--bind 0.0.0.0` を指定する。
2. 全キー、F / Esc、N、ノートの同期とポップアップ拒否時の通知を確認する。
3. 「PDF」「ノート付き PDF」から保存し、16:9、ページ順、画像、フォント、脚注を確認する。
4. 長文・長いタイトル・複数画像・壊れた画像でレイアウトと警告を確認する。

コードフェンスとリスト／引用が複雑に入れ子になる全ての Markdown 方言、
最適な画像の自動配置、文書のライブリロードは対象外です。
発表者画面はメインの Ruby VM が制御するため、メインの終了・再読み込み後はノート画面を開き直してください。
将来の改善候補は追加ブラウザー検証、画像配置の改善、公式ローダーへの移行です。

## 関連資料

- [アーキテクチャ](architecture.md)
- [PR ローダーの出所・再ビルド](../third_party/ruby-wasm-loader/README.md)
- [フォントの出所・ライセンス](../third_party/ibm-plex-sans-jp/README.md)
- [初回 MVP の実装記録](implementation-report.md)（当時の環境・結果を記録した文書）

## 構文ハイライト

`SafeHTML`は言語指定付きコードブロックを処理するときにRougeを遅延読み込みします。未知の言語はエスケープ済みのプレーンHTMLに戻します。スライドとノートは同じ処理を使います。

`bundle exec rake build:wasm`はRougeをWASMへ同梱し、`assets/highlight.css`（Githubテーマ）と`assets/rouge.LICENSE`も生成します。これらの生成ファイルはリポジトリに含め、直接編集せずビルドで更新してください。CSSはメイン画面と発表者画面の両方で読み込みます。

WASMは配布ランタイム内のStringScannerを使用します。ネイティブ側の`strscan`とはパッチバージョンが異なる場合があります。依存更新時には`test/browser/parity.spec.js`でネイティブRubyとの出力一致を確認してください。ビルドのsource digestにはcore/browserのソースに加えてlockfile、ビルドスクリプト、bootstrapを含めます。

## Fontsourceフォントの取得・検証

利用者向けの追加・設定手順は [README](../README.md#fontsourceのフォントを使う) を参照してください。

フォントは`fonts/ID/`、登録情報は`.wani/fonts.yml`に保存します。登録情報には確定した配布バージョン、ライセンス種別、管理ファイル一覧とSHA-256を記録します。Variable版を優先し、通常版は利用可能な400・700を取得します。両方がない場合はエラーになります。利用可能なnormal・italicと、CSSが参照する全言語サブセットを保存するため、日本語フォントではファイル数が多くなります。

`wani serve`は起動時とブラウザーがMarkdownを再取得したときにフォント指定を検証し、未登録フォントの警告や指定形式のエラーをターミナルにも表示します。同じ診断は連続して表示しません。
ruby.wasmがCSSを登録し、全スライド・ノートの文字についてFont Loading APIで読み込みを待ってからサイズ計算します。未登録・読み込み失敗時は画面に警告し、既定フォントで描画します。

同名フォントや既存ディレクトリは上書きしません。使用中フォントの削除には対話端末で確認が必要です。非対話実行では削除を拒否します。管理ファイルが変更されている場合も削除を拒否し、管理外のファイルは残します。自動更新、ローカルフォントのインポート、独自検索・プレビューUIはありません。

取得仕様の根拠: [Fonts API](https://fontsource.org/docs/api/fonts)、[配布バージョンAPI](https://fontsource.org/docs/api/version)、[公式配布・手動取得](https://fontsource.org/docs/getting-started/install)、[Variable CSS](https://fontsource.org/docs/getting-started/variable)、[公式CDN](https://fontsource.org/docs/getting-started/cdn)。CLIは公開APIとjsDelivrの固定バージョンの公式`@fontsource` / `@fontsource-variable`パッケージを直接HTTP取得します。通信は接続10秒・読み取り20秒・リクエスト全体60秒、単一ファイル32MiB・インストール合計256MiBを上限とします。

通常のテストは外部APIをモックします。実サービスとの統合確認は明示的に別実行します（指定先は新しいディレクトリにしてください）。

```sh
bundle exec rake test
bundle exec rake build:wasm
npx playwright test
bundle exec ruby test/integration/fontsource.rb /tmp/wani-fontsource-demo
WANI_FONTSOURCE_PROJECT=/tmp/wani-fontsource-demo npx playwright test test/browser/fontsource.spec.js
```

ビルド・ブラウザーテスト用のNode.js依存は開発環境だけで使用します。必要に応じて`CHROMIUM_PATH`で既存のChrome/Chromiumを指定できます。
