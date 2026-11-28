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

CRuby 4.0.10 の公式ソースの SHA-256 を検証し、`ruby_wasm` で WASI Preview 1 向けにコンパイルします。
初回はホスト用 C コンパイラー、`make`、`curl`、ネット接続が必要です。
通常版は標準 C 拡張を組み込み、同じビルドから JSON・YAML（Psych）・URI など必要な標準ライブラリを選んで収録します。
JS gem の Ruby コードも収録し、C 拡張は静的にリンクします。
RubyGems・Bundler・Prism の Ruby ライブラリ・テスト用 gem は収録しません。
依存ライブラリを追加したときは `scripts/build_wasm_runtime.rb` の収録リストを確認し、WASM を再ビルドしてブラウザーテストを実行してください。

### WASM で使う標準拡張の検出

`bundle exec rake build:wasm` の後に実行します。WASM 上で Wani のブラウザー用コードを読み込み、
YAML 設定とコードハイライトを含むテンプレートを解析して、ロードされた標準拡張を
Ruby の `--with-ext` に渡せるカンマ区切りの形式で標準出力に出します。

```sh
node scripts/detect_wasm_extensions.mjs
node scripts/detect_wasm_extensions.mjs --wasm /path/to/wani.wasm path/to/slides.md
```

Markdown ファイルを追加すると、その解析中に遅延ロードされた拡張も検出します。
Ruby 本体の組み込み機能、エンコーディング関連の機能、別途組み込む `js` gem は一覧から除きます。
結果は実行した処理に基づくため、拡張を絞った WASM の動作はブラウザーテストで確認してください。

### 軽量版のビルド

開発環境のセットアップ後、次のコマンドで `assets/wani.wasm` に軽量版を生成します。

```sh
bundle exec rake build:wasm_minimal
npm test
```

同じ CRuby 4.0.10 の通常版を検出用に使い、Wani が読み込んだ C 拡張を軽量版に組み込みます。
軽量版は `patch` コマンドで CRuby にパッチを適用し、Ruby ソースの構文解析を Prism に固定します。
旧パーサー `parse.y` の本体をリンクから外すため、軽量版では `--parser=parse.y` を指定できず、
`RubyVM::InstructionSequence.compile_parsey` と `RubyVM::AbstractSyntaxTree.parse` は `NotImplementedError` を送出します。
文字コードは Ruby の組み込みの UTF-8・US-ASCII・ASCII-8BIT に加え、Psych が使う UTF-16LE／BE とその変換を組み込みます。
CRuby の C コンパイルはサイズ優先の `-Oz` を使います。
ビルド済みのランタイムは `vendor/wani-wasm/` に CRuby のバージョン、拡張リスト、文字コード構成、最適化設定、パッチごとにキャッシュします。
通常版を生成するには `bundle exec rake build:wasm` を実行してください。

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
ビルドは開発用の `assets/wani.wasm` と、配信用の `assets/wani.wasm.gz` を生成します。
gem には gzip 版だけを収録します。`/assets/wani.wasm` は gzip 対応クライアントに圧縮済みのデータを返し、それ以外には展開して返します。
`bundle exec rake package` は再ビルド・Rubyテスト・gem作成をまとめて実行します。

RubyテストはCLI・共通ロジック・ファイル配信・パストラバーサル・シンボリックリンク・終了処理を検証します。
ブラウザーテストは実際の Ruby サーバーと生成した wasm を使い、操作・レイアウト・各画像形式・ノート同期・
印刷PDFのページ数／寸法／内容と、CRubyとの解析結果一致を確認します。
PDF.js は生成済みPDFのテスト検査にだけ使い、製品のPDF生成には使いません。
`smoke_package.rb` は一時環境へ gem をインストールして `new` → `check` → `serve` と正常終了を確認し、後片付けします。

## リリース

依存関係と Chromium を上の手順でインストールし、変更をコミットした `main` で実行します。
`origin` への push 権限が必要です。

```sh
bundle exec rake release
```

パッチバージョンを1つ上げ、`lib/wani/version.rb`・`Gemfile.lock`・README のインストール例を更新します。
`bundle exec rake package:minimal` で軽量版 WASM をビルドして gem に収録します。
Ruby テスト、ブラウザーテスト、パッケージの動作確認が成功すると、
バージョン更新をコミットして `vX.Y.Z` タグを作成し、`main` とタグを `origin` へ atomic push します。
タグの push により、GitHub Actions が同じタスクで軽量版の gem を作成し、再検証して RubyGems.org に公開します。
コマンドの成功は push までを意味します。公開の成否は Actions の `Publish gem` で確認してください。

テストに失敗した場合は、バージョン更新を元に戻し、コミット・タグ・push は行いません。
push に失敗した場合はローカルのコミットとタグが残ります。原因を解消して、表示された
`git push --atomic origin HEAD:refs/heads/main refs/tags/vX.Y.Z` を再実行してください。
`CHROMIUM_PATH` などのテスト用環境変数はそのまま利用できます。

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

WASM に同梱する lexer を変更するときは、[README の対応言語一覧](../README.md#コードの構文ハイライト) も更新します。

`bundle exec rake build:wasm`は`assets/highlight.css`（Githubテーマ）と`assets/rouge.LICENSE`も生成します。これらの生成ファイルはリポジトリに含め、直接編集せずビルドで更新してください。CSSはメイン画面と発表者画面の両方で読み込みます。

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
