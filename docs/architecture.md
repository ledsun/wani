# WANI のアーキテクチャ

WANI — Web Assembly Narrative Illustrator の内部構成と配布方式を説明します。
利用手順は [README](../README.md)、開発環境と検証手順は [開発ガイド](development.md) を参照してください。

## 構成と静的配信

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
`data-ruby-wasm-url` で同梱 wasm を指定し、WANI 側で JS を書き換えません。
出所、SHA-256、LICENSE / NOTICE、公式版への差し替え手順は [third_party/ruby-wasm-loader](../third_party/ruby-wasm-loader/README.md)。
ローダーの再ビルドは `npm run build:loader` です。

| 実行時の gem | 固定した検証バージョン |
| --- | --- |
| kramdown | 2.5.2 |
| kramdown-parser-gfm | 1.1.0 |
| rexml | 3.4.4 |
| webrick | 1.9.2（gem依存は1.9系） |

ビルドツールは ruby_wasm 2.10.1。packするgemは最初の3つだけです。

## フォントの配信

IBM 公式パッケージ `@ibm/plex-sans-jp@3.0.0` の Regular（400）と Bold（700）の
完成版 WOFF2 を `assets/fonts/` に保持し、gem に同梱します。合計は4,635,040 bytesです。
OS へのインストールや外部 CDN への接続は不要です。

非表示のタイトルも正しい字幅で計測するため、Ruby から FontFaceSet API を使って
通常・太字の両方を明示的に読み込み、その後で DOM を計測します。
コードは等幅書体を優先し、日本語の代替候補に IBM Plex Sans JP を指定します。

著作権表示・OFL 1.1 の原文・配布元・チェックサム・PDF文字抽出の注意点は
[フォントの同梱記録](../third_party/ibm-plex-sans-jp/README.md) を参照してください。

## 描画とレイアウト

ブラウザーが Markdown を取得し、共通パーサーから受け取ったモデルを Ruby で DOM に変換します。
kramdown の内部 AST は core 内に閉じ込め、モデルにはスライドのタイトル・本文・ノート・
解決済み脚注・画像パス・診断を持たせます。HTML は許可した要素・属性だけを生成します。
ページごとの脚注は `page-footnote` コメントで指定し、省略時は空になります。

論理サイズは1920×1080です。画像とフォントを待って幅・高さを計測し、文字サイズを二分探索します。
本文は16〜160px、タイトルは24〜220pxで、[Layout の定数](../lib/wani/browser/layout.rb) から調整できます。
画面にはスライド全体を縮尺変更して表示します。印刷は別の DOM と CSS の用紙サイズ指定を使い、
レイアウト寸法も縮める `zoom` によってページ内の欠落を防ぎます。

ページ移動・URLハッシュ・Fullscreen API・発表者画面の postMessage 同期も Ruby が担当します。
兎とワニの進捗はスライド番号から求め、印刷では元のスライド番号に対応する静止状態を使います。
アプリケーション独自の JavaScript は追加していません。

## 発表タイマー

Front Matter の `time_limit` は分単位の有限な非負数です。省略時は5分、0は無効です。
共通パーサーで検証してモデルに保持し、ブラウザーの読み込み・レイアウト完了後に計測します。
Ruby の `browser/presentation_timer.rb` が期限時刻との差を確認するため、
バックグラウンドでタイマー呼び出しが間引かれても経過時間は累積します。タブ復帰時にも確認します。
残り30秒から画面上に表示し、期限後は専用画面でスライドを覆います。
最終スライドでは一時停止し、戻ったときに停止時間を期限へ加えて残り時間を維持します。
左右キーや復帰ボタンで同じスライドへ戻し、その読み込み中は再発火しません。
添付されたキャラクター画像の右半分を CSS で表示し、印刷 DOM にはタイマーも専用画面も含めません。
