# WANI — Web Assembly Narrative Illustrator

Markdown からスライドを作り、ブラウザー内の Ruby でプレゼンテーションするツールです。
Rabbit へのオマージュとして、因幡の白兎に登場するワニ（鮫）にちなんだ名前です。

<p align="center">
  <img src="docs/images/wani-characters.png" alt="ノートパソコンを使う兎と、それを見守るワニ" width="640">
</p>

<p align="center">
  <img src="docs/images/rabbit.png" alt="ノートパソコンを持った兎" width="240">
  <img src="docs/images/wani.png" alt="笑顔のワニ" width="240">
</p>

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
gem install ./wani-0.1.8.gem

wani new my-talk
cd my-talk
wani check
wani serve
```

rbenv 環境でインストール後に `wani: command not found` となる場合は、
`rbenv rehash` を実行して実行ファイルの shim を更新してください。

表示された http://127.0.0.1:8000/ を Chrome または Edge で開きます。
`slides.md` を編集したらブラウザーを再読み込みしてください。
生成されるプロジェクトには、各種Markdown記法を紹介する10ページの `slides.md` と、`images/` 内のサンプルSVG画像が含まれます。
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
time_limit: 5
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

独立した `---` の行でスライドを分割し、各ページの最初の見出しをタイトルにします。
本文には段落、強調、リスト、引用、コード、リンク、画像、表を使えます。
`<!-- notes: ... -->` は発表者ノート、`<!-- page-footnote: ... -->` はページごとの脚注です。

設定、各記法の例、対応範囲と制約は [Markdown記法ガイド](docs/markdown.md) を参照してください。

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

スライドは1920×1080、16:9、白背景です。タイトル・本文・脚注を分け、画面に合わせて全体を拡大縮小します。
画像とフォントを読み込み、幅と高さに合わせて文字サイズを自動調整します。
画像は比率を維持して縦に配置し、画像だけの場合は本文領域を広く使います。
収まらない内容は分割・スクロールせず、番号と内容を含む警告を表示します。
画像の読み込みを最大15秒待ち、失敗やタイムアウトを通知します。

ツールバーの「PDF」「ノート付き PDF」から印刷ダイアログを開き、PDFとして保存します。
Ctrl+P でも印刷できます。
用紙は320×180mmを指定し、ブラウザーのヘッダー・フッターはオフにしてください。
通常版は1スライド1ページ、ノート付きは各スライドの次に対応するノートを置きます。
画像・フォントの完了後に印刷し、ページごとの脚注とページ番号を出力します。兎と鰐の装飾は常に非表示です。
装飾はページの進捗に連動します。前半ではワニが右から左へ増えて橋を作り、後半では兎が左の島からサメの背中を通って右の島へ渡ります。
1ページ目は総ページ数によらず必ずワニ1匹から始め、前半の終わりに橋が20匹で完成するように増やします。
1ページだけの場合は1匹のまま、2ページの場合は2ページ目で橋を完成させます。
ページを戻すと位置と橋も戻り、最終ページで兎が右端に到着します。
画面では動きを減らす設定にも対応します。

## 発表タイマー

スライドの読み込み完了から計測し、既定では5分で時間切れ画面を表示します。
Front Matter の `time_limit` に分数を指定して変更できます（小数も可）。
`time_limit: 0` でタイマーを無効にします。

残り30秒になると、全画面表示中もカウントダウンを表示します。
残り5秒は中央に数字を表示し、画面の短辺に対して20％・40％・60％・80％・100％と強調サイズを増やします。
各数字は0.8秒で通常サイズに戻ります。動きを減らす設定では拡大アニメーションを省略します。
時間切れになると、兎柄フードをくわえたワニ（さめ）の画像を表示します。
左右キーまたは「スライドに戻る」ボタンで、時間切れ直前のスライドに戻れます。
戻った後は通常通りページを移動でき、時間切れ画面は再表示しません。
最終スライドの表示中はタイマーを一時停止し、カウントダウンも時間切れ画面も表示しません。
前のスライドに戻ると、停止前の残り時間から再開します。1ページだけの場合も停止します。
ページを再読み込みするとタイマーも最初から始まります。
タイマーと時間切れ画面はPDFには含めません。

## 同梱フォント

日本語・英数字の標準書体は **IBM Plex Sans JP** です。
通常と太字のフォントを gem に同梱します。
OS へのインストールや外部 CDN への接続は不要です。

本文・タイトル・発表者画面・PDF に同じ書体を使います。
コードは等幅フォントを優先し、日本語の代替候補に IBM Plex Sans JP を指定します。
読み込みに失敗した場合は警告し、代替書体で表示を続けます。

フォントは SIL Open Font License 1.1 です。原文のライセンス・著作権表示と配布元・チェックサムは
[third_party/ibm-plex-sans-jp](third_party/ibm-plex-sans-jp/README.md) に保持しています。

## 動作環境と制約

確認済みの環境は Linux / Ruby 4.0.7 / Chrome 156.0.8078.47 です。
Windows・WSL2、Edge / Firefox / Safari、通常ブラウザーの印刷ダイアログ操作は未検証です。

WSL2 内で `wani serve` を起動した場合は、Windows 側のブラウザーで http://localhost:8000/ を開きます。
環境のポート転送設定に応じて `--bind 0.0.0.0` を指定してください。

複雑に入れ子になった Markdown 方言、構文ハイライト、最適な画像の自動配置、ライブリロードは対象外です。
発表者画面はメイン画面の終了・再読み込み後に開き直してください。

## 開発者向けドキュメント

- [アーキテクチャ](docs/architecture.md)：共通モジュール、静的配信、wasm・ローダー、フォント、レイアウトの設計
- [開発・検証](docs/development.md)：ビルド、テスト、パッケージ作成、手動検証の手順

### Fontsourceのフォントを使う

[Fontsource](https://fontsource.org/fonts)でフォントを検索・プレビューし、プレゼンテーションのディレクトリでインストールします。取得・管理はRuby CLIで行い、利用者の環境にNode.jsやnpmは不要です。

```sh
wani font add "Noto Sans JP"
# フォントIDまたは公式ページURLも指定できます
wani font add https://fontsource.org/fonts/jetbrains-mono
wani font list
wani font remove jetbrains-mono
```

インストールだけではMarkdownを変更しません。`slides.md`のFront Matterに指定すると、タイトルと本文に適用されます（コードの等幅フォントは従来どおりです）。

```yaml
---
font: Noto Sans JP
---
```

フォントは`fonts/ID/`、登録情報は`.wani/fonts.yml`に保存します。この両方をプロジェクトと一緒に保存・配布してください。登録情報には確定した配布バージョン、ライセンス種別、管理ファイル一覧とSHA-256を記録します。Variable版を優先し、通常版は利用可能な400・700を取得します。両方がない場合はエラーになります。利用可能なnormal・italicと、CSSが参照する全言語サブセットを保存するため、日本語フォントではファイル数が多くなります。

インストール後は外部CDNへの接続なしで、`wani serve`によるローカル配信とPDF出力ができます。ruby.wasmがCSSを登録し、全スライド・ノートの文字についてFont Loading APIで読み込みを待ってからサイズ計算します。未登録・読み込み失敗時は画面に警告し、既定フォントで描画します。PDFは準備完了後に印刷ボタンから出力してください。

同名フォントや既存ディレクトリは上書きしません。使用中フォントの削除には対話端末で確認が必要です。非対話実行では削除を拒否します。管理ファイルが変更されている場合も削除を拒否し、管理外のファイルは残します。自動更新、ローカルフォントのインポート、独自検索・プレビューUIはありません。

各フォントの実際のライセンスを`fonts/ID/LICENSE`に保存します。**Web公開・再配布・PDF配布時には、そのフォントのライセンス条件を確認してください。** すべてのフォントが同じライセンスとは限りません。

取得仕様の根拠: [Fonts API](https://fontsource.org/docs/api/fonts)、[配布バージョンAPI](https://fontsource.org/docs/api/version)、[公式配布・手動取得](https://fontsource.org/docs/getting-started/install)、[Variable CSS](https://fontsource.org/docs/getting-started/variable)、[公式CDN](https://fontsource.org/docs/getting-started/cdn)。CLIは公開APIとjsDelivrの固定バージョンの公式`@fontsource` / `@fontsource-variable`パッケージを直接HTTP取得します。通信は接続10秒・読み取り20秒・リクエスト全体60秒、単一ファイル32MiB・インストール合計256MiBを上限とします。

通常のテストは外部APIをモックします。実サービスとの統合確認は明示的に別実行します（指定先は新しいディレクトリにしてください）。

```sh
bundle exec rake test
bundle exec rake build:wasm
npx playwright test
bundle exec ruby test/integration/fontsource.rb /tmp/wani-fontsource-demo
WANI_FONTSOURCE_PROJECT=/tmp/wani-fontsource-demo npx playwright test test/browser/fontsource.spec.js
```

ビルド・ブラウザーテスト用のNode.js依存は従来どおり開発環境だけで使用します。必要に応じて`CHROMIUM_PATH`で既存のChrome/Chromiumを指定できます。
