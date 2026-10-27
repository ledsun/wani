# Rouge導入の事前調査

調査日: 2026-10-27。対象: wani `5b88fdb`、Rouge 5.1.0、@ruby/4.0-wasm-wasi 2.10.1。

## 結論

既存のruby.wasmで動作する。SafeHTMLのコードブロック生成時にRougeを呼ぶ構成が適している。初回ロードに約1秒かかるため、言語指定付きコードブロックを初めて処理するときに遅延ロードする案を推奨する。

本調査ではアプリのコード・依存関係・既存WASMを変更していない。検証用WASMとブラウザーへの一時的なコード注入で確認した。追加したリポジトリ内ファイルはこの調査記録のみ。

## バージョンと互換性

RubyGems APIで取得した公開最新版は5.1.0。必要Rubyは3.0以上、実行時依存は`strscan ~> 3.1`。取得gemのSHA-256はAPIの値と照合した。

- gem SHA-256: `b77c632842ab7f5147940212f0345808cccfbce864fd5b631d7d12a35ac85452`
- ネイティブRubyとWASMの両方でStringScanner 3.1.6を確認。追加のC拡張ビルドは不要だった。
- 標準の`require "rouge"`で234個のlexerが登録される。各言語の定義ファイルをロードするため初期化コストがある。
- gemのライセンス表記はMITとBSD-2-Clause。配布物にはRougeのLICENSEも含める。

## 実測

同一のwaniソースと既存の3つのgemをパックした比較用WASMを新規作成し、Rougeの`lib`だけを追加したWASMと比較した。サイズは十進MB。

| 項目 | 追加前 | Rouge全体を追加 | 増分 |
| --- | ---: | ---: | ---: |
| WASM | 33,258,092 bytes | 35,165,730 bytes | 1,907,638 bytes（約5.7%） |
| gzip圧縮時 | 10,211,012 bytes | 10,749,508 bytes | 538,496 bytes（約5.3%） |

Rougeのライブラリ自体は1,864,846 bytes。テーマCSSの生成例（Github、`.highlight`スコープ）は2,210 bytes。現在のサーバーはgzip配信を実装していないので、gzip値は圧縮配信した場合の参考値。

Chromium headless 149、同じブラウザープロセス内で毎回新規コンテキストを作り、3条件を交互に5回測定した。ページ移動開始から「準備できました」までの時間。ローカル配信、PlaywrightによるWASM応答差し替えを使用。CPU制限は設定していない。

| 条件 | 中央値 | 最小〜最大 |
| --- | ---: | ---: |
| 比較用WASM、Rougeなし | 2.23秒 | 2.04〜2.41秒 |
| Rouge同梱、requireなし | 2.30秒 | 2.11〜2.65秒 |
| Rouge同梱、起動時requireあり | 2.85秒 | 2.57〜3.34秒 |
| require単体 | 0.96秒 | 0.85〜1.11秒 |

ページ起動時間にはWASMのコンパイル、読み込み、フォントやレイアウトなども含む。処理系のウォームアップと測定のばらつきがあるため、各中央値の差を厳密な追加コストとは解釈しない。低性能端末やネットワーク転送は未検証。

初期化後、20行のRubyコード×20ブロック（400行相当）を5回色付けした中央値は58.3ms（53.6〜80.0ms）。繰り返しの短いRubyサンプルであり、任意の言語・巨大な入力の性能保証ではない。ブラウザー検証ではRuby/JS/HTMLの一部を先に使用しており、個々のlexerの初回コストは独立に測れていない。

## 確認した動作

- Ruby、JavaScript、TypeScript、Python、Shell、JSON、YAML、HTML、CSS、SQL、プレーンテキストの11サンプルで、ネイティブRubyとChromium内WASMの出力HTMLが一致した。
- Node上でも検証用WASMを実行し、同じサンプルを処理できた。
- ブラウザーDOMに挿入後の`textContent`が原文と一致した。日本語も保持された。
- HTMLサンプル内の`<script>`や`<img onerror=...>`はテキストとしてエスケープされ、実際のscript/img要素にならなかった。これは代表例の確認であり包括的なセキュリティ監査ではない。
- SafeHTMLに一時的なprependを加える試作で、スライド・印刷用クローンにspan要素が生成された。
- 発表者ウィンドウのノートにもハイライト済みHTMLが届き、ページ移動時に同期した。メイン画面とノートに同じCSSを注入して表示を確認した。
- 未知の言語は従来のエスケープ済みプレーン表示へ戻せた。
- プレビューPNGとPDFを生成した。PDFの色・テキスト抽出の自動検査、ノート付きPDF、全既存テストの再実行は今回行っていない。

## 推奨する実装

1. `wani.gemspec`にRougeの固定バージョンを追加してlockfileを更新する。
2. `scripts/build_wasm.rb`の同梱gemにRougeを追加し、`assets/bootstrap.rb`のロードパスに`/wani/bundle/rouge/lib`を追加する。ブラウザー側でのrequireは遅延させる。
3. `SafeHTML#render`の`:codeblock`処理で`node.options[:lang]`を取得する。言語指定なしは従来表示、指定ありは`Rouge::Lexer.find`で解決する。
4. `Rouge::Formatters::HTML`で色付けし、固定の`<pre class="highlight"><code>…</code></pre>`で包む。未知の言語はプレーン表示へ戻す。自動言語推定は初期実装では行わない。
5. ビルド時にテーマCSSを生成し、スライドと発表者ノートの双方が読む`style.css`へ組み込む。レイアウト計算前にテーマを適用する。
6. ノート・印刷用ページ・通常ページは共有のパーサー出力を使う。postMessage同期プロトコルを変更する必要はない。

Kramdownは`node.options[:lang]`に`ruby`や`rb`を保持することを確認した。現在のGFMパーサーでは`ruby linenos`のような複数語のフェンス指定はコードブロックにならなかったので、初期仕様は単純な言語名に限定するのが自然。

Kramdownの`syntax_highlighter: :rouge`だけを設定しても、waniは標準HTMLコンバーターを経由せずSafeHTMLで出力しているため反映されない。SafeHTMLからRougeを直接使う。

Rougeの通常HTML formatterではコードをエスケープする。raw HTMLを通すescape機能は有効にせず、利用者入力をHTML属性へそのまま埋め込まない。インラインコードは従来どおりでよい。

## 実装時に残る確認

- ノート付き印刷、言語未指定・未知・空ブロック、長い行、HTML文字、各言語エイリアスの回帰テスト。
- テーマの太字・斜体とフォント読み込み、レイアウト計算の整合性。
- 長大なコードや複雑な構文での処理時間。必要ならサイズ上限やプレーン表示へのフォールバックを検討する。
- サーバーのフォント診断と`font remove`もParserを使用するため、コード付きMarkdownではネイティブ側でもハイライト処理が発生する。不要な解析を分離するかは実装時に判断する。
- 全言語の同梱削減は未検証。個別lexerの依存関係やRougeの内部ロード構成への追従が必要になるため、まず全体同梱＋遅延ロードが単純。
- `build.json`のsource digestは現在core/browserのRubyファイルだけが対象。依存バージョンだけの更新も鮮度判定したいなら、lockfileなどを入力に含める。

## 検証資料

一時ディレクトリ: `/tmp/wani-rouge-investigation/`

- `pack.rb`: 既存のパック手順を使う比較用・Rouge同梱WASMの作成
- `probe.rb`, `run-node.cjs`: 言語サンプルと性能測定
- `browser.cjs`: Chromiumでの5回比較、ネイティブとの一致、ノート同期などの検証
- `native.json`, `wasm-node.json`, `browser.json`, `size.json`: 実測値
- `preview.png`, `preview.pdf`: 試作表示

検証コマンド（リポジトリルートから、一時ディレクトリに検証ファイルと展開済みgemがある状態）:

```sh
bundle exec ruby /tmp/wani-rouge-investigation/pack.rb
ruby -I/tmp/wani-rouge-investigation/rouge/lib -e 'puts eval(File.read("/tmp/wani-rouge-investigation/probe.rb"))' > /tmp/wani-rouge-investigation/native.json
node /tmp/wani-rouge-investigation/run-node.cjs
# 別ターミナルで起動
bundle exec ruby -Ilib exe/wani serve test/fixtures/talk/slides.md --port 18041
node /tmp/wani-rouge-investigation/browser.cjs
```

検証用WASM生成時刻: baseline 2026-10-27 20:38:26 JST、Rouge追加版 20:38:42 JST。ブラウザーのルート差し替えにより、この新規生成ファイルを実行した。

- baseline SHA-256: `e7cd52e50f438bea43ff2494c50fcd957be733c44ef0161a17bb350da3654de6`
- Rouge追加版 SHA-256: `69d8834555a275428a85e99045d29566d7702e503684ba295906b44ef5ab9b9d`

## 公式資料

- [Rouge README](https://github.com/rouge-ruby/rouge): formatter、lexer、テーマの基本API。
- [RubyGems Rouge 5.1.0](https://rubygems.org/gems/rouge/versions/5.1.0): バージョン、依存関係。
- [RubyGems API](https://rubygems.org/api/v1/gems/rouge.json): 今回の取得版とチェックサム確認に使用。
- [Kramdown Rouge連携](https://kramdown.gettalong.org/syntax_highlighter/rouge.html): 標準コンバーター経由の連携方式。
