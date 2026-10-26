# Wani

Markdown からスライドを作り、ブラウザー内の Ruby でプレゼンテーションするツールです。
Rabbit へのオマージュとして、因幡の白兎に登場するワニ（鮫）から名付けました。

## インストールと開始

現在はソースから gem をビルドして利用します。RubyGems.org への公開は行っていません。
Ruby 3.2 以上が必要です。ソースのビルドには Node.js 22.13 以上、npm、Bundler が必要ですが、
ビルド済み gem の利用に Node.js は不要です。

```sh
bundle config set --local path vendor/bundle
bundle install
npm ci
bundle exec rake build:wasm

gem build wani.gemspec
gem install ./wani-0.1.1.gem

wani new my-talk
cd my-talk
wani check
wani serve
```

rbenv 環境でインストール後に `wani: command not found` となる場合は、
`rbenv rehash` を実行して実行ファイルの shim を更新してください。

表示された http://127.0.0.1:8000/ を Chrome または Edge で開きます。
`slides.md` を編集したらブラウザーを再読み込みしてください。
生成されるプロジェクトは `slides.md` と空の `images/` だけです。
HTML / CSS / JS ランタイム / wasm は gem が保持し、各プロジェクトへコピーしません。

## コマンド

```sh
wani new DIRECTORY
wani check [FILE]
wani serve [FILE] --port 8000 --bind 127.0.0.1
wani --version
wani --help
```

- `new`: サンプルを生成します。既存のディレクトリ、ファイル、シンボリックリンクは上書きしません。
- `check`: ファイル省略時は `slides.md`。Front Matter・区切り・タイトル・ノート・画像を検証します。
  エラーは終了コード1、成功および警告のみの場合は0です。実際のはみ出しはブラウザーが検出します。
- `serve`: 指定ファイルを静的配信します。省略時は `slides.md`。
  `--port` / `-p`、`--bind` / `-b` で変更でき、Ctrl+C で正常終了します。
  初期バインド先は127.0.0.1、ポートは8000です。ポート0を指定すると利用可能なポートを選びます。

Markdown の画像は、そのファイルを基準に相対パスで記述します。
PNG / JPEG / WebP / SVG に対応します。HTTP(S)画像も表示できますが、`check` の存在確認はローカル画像だけです。

## Markdown

```markdown
---
footer: Wani Presentation
decorations: true
---

# Ruby on WebAssembly

**Ruby** がブラウザーでスライドを描画します。

![構成図](images/architecture.svg)

<!--
notes:
ここで仕組みを説明します。
**ノートの Markdown** も使えます。
-->

---

## 次のスライド

見出しレベルが違っても、タイトルのデザインは同じです。
```

先頭の YAML Front Matter はプレゼンテーション全体の設定です。
`footer` は文字列、`decorations` は真偽値（省略時true）。YAML のオブジェクト生成と alias は許可しません。

独立した `---` の行で分割します。コードフェンス（バッククォート／チルダ）内、
インデントコード内、コメント内の区切りは分割に使いません。
コードフェンスは0〜3スペースの字下げに対応し、4スペース以上の行はインデントコードとして扱います。
先頭に Front Matter を置かない場合、文書を `---` から開始しないでください。

各スライドの最初の見出しをタイトルにし、追加の見出しは本文に残して警告します。
タイトルなしのスライドも使えます。空タイトルはエラー、空スライド・閉じていないコードフェンスは警告です。
`<!-- notes: ... -->` は本文から除外し、発表者画面とノート付きPDFだけに使います。
複数のノートブロックは警告して結合します。

段落、強調、リスト、引用、コード、リンク、画像、表を表示できます。
任意の HTML や属性は引き継がず、kramdown の AST から許可した要素だけを生成します。
HTML の直接記述を使った装飾、スクリプト、埋め込み iframe、危険な URL はサポートしません。
パーサーは kramdown の GFM パーサーを使用しますが、脚注など全ての拡張記法に対応するものではありません。

## 発表と印刷

| キー | 操作 |
| --- | --- |
| → / Space / PageDown | 次のスライド |
| ← / PageUp | 前のスライド |
| Home / End | 最初 / 最後 |
| F | 全画面の切り替え |
| Esc | 全画面を解除 |
| N | 発表者ノートを別ウィンドウに開く |

`#slide=3` のような URL で特定のスライドを開けます。
ノート画面は本文・ノート・ページ番号をメインから一方向で同期します。
開けない場合はブラウザーのポップアップ設定を確認してください。

スライドは1920×1080、16:9、白背景です。タイトル・本文・フッターを分け、画面に合わせて全体を拡大縮小します。
画像とフォントを待ち、幅・高さを計測して文字サイズを二分探索します。
本文は16〜160px、タイトルは24〜220px（`lib/wani/browser/layout.rb` の定数で調整可能）。
画像は比率を維持して縦に配置し、画像だけの場合は本文領域を広く使います。
収まらない内容は分割・スクロールせず、番号と内容を含む警告を表示します。
画像の読み込みを最大15秒待ち、失敗やタイムアウトを通知します。

ツールバーの「PDF」「ノート付き PDF」から印刷ダイアログを開き、PDFとして保存します。
起動時にも通常の印刷DOMを準備するため、Ctrl+P で印刷できます。
用紙は320×180mmを指定し、ブラウザーのヘッダー・フッターはオフにしてください。
通常版は1スライド1ページ、ノート付きは各スライドの次に対応するノートを置きます。
画像・フォントの完了後に印刷し、フッターと差し替え可能な仮SVG装飾も出力します。
装飾を無効にする場合は `decorations: false` を指定してください。

## 同梱フォント

日本語・英数字の標準書体は **IBM Plex Sans JP** です。
IBM 公式パッケージ `@ibm/plex-sans-jp@3.0.0` の Regular（400）と Bold（700）の
完成版 WOFF2 を gem に同梱します。フォントファイルの合計は4,635,040 bytesです。
OS へのインストールや外部 CDN への接続は不要です。

本文・タイトル・発表者画面・PDF に同じ書体を使い、計測前に通常と太字の両方を明示的に読み込みます。
コードは等幅フォントを優先し、日本語の代替候補に IBM Plex Sans JP を指定します。
読み込みに失敗した場合は警告し、代替書体で表示を続けます。

フォントは SIL Open Font License 1.1 です。原文のライセンス・著作権表示と配布元・チェックサムは
[third_party/ibm-plex-sans-jp](third_party/ibm-plex-sans-jp/README.md) に保持しています。

## 配信とアーキテクチャ

- `lib/wani/core/`: Markdown文字列から独自モデルを返す共通パーサー、許可した要素のレンダラー、静的検証。
- `lib/wani/server/`: WEBrick の静的 HTTP 配信。スライドのHTMLはサーバーで生成しません。
- `lib/wani/browser/`: Ruby による DOM 生成、計測、操作、ノート、印刷。
- `assets/`: gem に同梱するアプリシェル、スタイル、起動Ruby、SVG、生成した wasm / ローダー。

URL は `/assets/`（gem の固定アセット）と `/talk/`（選択した Markdown とそのディレクトリ内の画像）に分けます。
他の Markdown や任意のファイルは公開しません。`..`・不正なエンコード・二重エンコード・
バックスラッシュ・公開ディレクトリ外へ出るシンボリックリンクを拒否します。
ファイル名中の `%` はこの制限により非対応です。サーバーはローカルでの発表・開発用途です。
Ruby / JS interop の初期化に必要な `unsafe-eval` を CSP で許可していますが、任意のユーザー JS は生成しません。

## wasm とローダー

[公式のパッケージング方式](https://ruby.github.io/ruby.wasm/) に従い、
`@ruby/4.0-wasm-wasi@2.10.1` の標準ライブラリ入り wasm に `rbwasm pack` で core・browser・Pure Ruby gem を追加します。
CLI / WEBrick / 開発ツールは含めません。ブラウザー側のアプリケーション処理は Ruby です。

ローダーは [ruby/ruby.wasm#672](https://github.com/ruby/ruby.wasm/pull/672) の
`dc6b0ffd5800ed9bfc49268ed8021d456f10ddf8` からビルドした**未リリース版**を一時同梱しています。
`data-ruby-wasm-url` で同梱 wasm を指定し、Wani 側で JS を書き換えません。
出所、SHA-256、LICENSE / NOTICE、公式版への差し替え手順は [third_party/ruby-wasm-loader](third_party/ruby-wasm-loader/README.md)。
ローダーの再ビルドは `npm run build:loader` です。

| 実行時の gem | 固定した検証バージョン |
| --- | --- |
| kramdown | 2.5.2 |
| kramdown-parser-gfm | 1.1.0 |
| rexml | 3.4.4 |
| webrick | 1.9.2（gem依存は1.9系） |

ビルドツールは ruby_wasm 2.10.1。packするgemは最初の3つだけです。

## 開発・テスト

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

## 手動検証と既知の制約

自動検証環境は Linux / Ruby 4.0.7 / Node.js 24.22.1 / Chrome 156.0.8078.47。
通常ブラウザーの印刷ダイアログ、Windows・WSL2、Edge / Firefox / Safari はこの環境では未検証です。
以下を対象環境で確認してください。

1. WSL2 内で `wani serve` を起動し、Windows 側の Chrome / Edge で http://localhost:8000/ を開く。
   環境のポート転送設定に応じて `--bind 0.0.0.0` を指定する。
2. 全キー、F / Esc、N、ノートの同期とポップアップ拒否時の通知を確認する。
3. 「PDF」「ノート付き PDF」から保存し、16:9、ページ順、画像、フォント、フッターを確認する。
4. 長文・長いタイトル・複数画像・壊れた画像でレイアウトと警告を確認する。

コードフェンスとリスト／引用が複雑に入れ子になる全ての Markdown 方言、構文ハイライト、
最適な画像の自動配置、文書のライブリロードは対象外です。
発表者画面はメインの Ruby VM が制御するため、メインの終了・再読み込み後はノート画面を開き直してください。
将来の改善候補は追加ブラウザー検証、画像配置の改善、公式ローダーへの移行です。
