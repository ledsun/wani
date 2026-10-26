# IBM Plex Sans JP

IBM の公式 npm パッケージ [`@ibm/plex-sans-jp@3.0.0`](https://www.npmjs.com/package/@ibm/plex-sans-jp/v/3.0.0)
から、以下の完成版 WOFF2 を変更せずに同梱する。

- `assets/fonts/IBMPlexSansJP-Regular.woff2`（400 / 2,282,284 bytes）
- `assets/fonts/IBMPlexSansJP-Bold.woff2`（700 / 2,352,756 bytes）

元ファイルは `fonts/complete/woff2/hinted/` にある。サブセット化・改名・フォントデータの加工はしていない。
出所・バージョン・配布アーカイブと各ファイルの SHA-256 は `provenance.json` に記録する。

Copyright © 2017 IBM Corp. with Reserved Font Name "Plex"。
SIL Open Font License 1.1 により配布され、著作権表示とライセンス全文を `LICENSE.txt` に保持する。
アプリの MIT ライセンスとは区別する。

## 取得の再現

```sh
npm pack @ibm/plex-sans-jp@3.0.0 --pack-destination /tmp
```

`provenance.json` のアーカイブ SHA-256 と照合して展開し、上記2ファイルとパッケージの `LICENSE.txt` を取り出す。
Wani の通常利用・ビルド時にフォントのダウンロードや OS インストールは不要。
参照元: [IBM 公式リポジトリ](https://github.com/IBM/plex/tree/master/packages/plex-sans-jp)。

## PDF の文字抽出

検証した Chromium の PDF では、同じグリフに対応する文字が互換部首として抽出される場合がある
（例: `日` → `⽇`）。表示の字形とフォント埋め込みは確認し、内容比較のテストでは NFKC 正規化する。
PDF のテキストコピーが常に元のコードポイントと一致することまでは保証しない。

## 動作検証 (2026-10-26)

Linux / Ruby 4.0.7 / Node.js 24.22.1 / Chrome 156.0.8078.47。
Ruby は12件・85アサーション、ブラウザーは13件成功（35.8秒）。
Chrome の実フォント情報で日本語の Regular / Bold と Web フォント使用を確認し、
日本語 PDF の文字内容・Regular / Bold と FontFile2 の埋め込みを検査した。
太字の取得先を壊すと実描画テストは失敗し、復元後はフォント検証3件が成功（9.2秒）。
隔離環境の gem インストールでも2フォントのハッシュ一致、ライセンス同梱、HTTP配信を確認した。
