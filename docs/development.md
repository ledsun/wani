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
