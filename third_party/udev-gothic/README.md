# UDEV Gothic

[公式v2.2.0リリース](https://github.com/yuru7/udev-gothic/releases/tag/v2.2.0) の通常版Regular・Boldを同梱します。
半角1:全角2の等幅で、日本語と英数字に同じ書体を使用します。リガチャ・Nerd Fontsなしの版です。

- `assets/fonts/UDEVGothic-Regular.ttf`（400）
- `assets/fonts/UDEVGothic-Bold.ttf`（700）

公式ZIP内の完成版TTFを変換・サブセット化・改名せずに保存しています。
配布元・バージョン・アーカイブと各ファイルのSHA-256・サイズは `provenance.json` に記録します。
同じタグの `LICENSE` を `LICENSE.txt` として保持します。SIL Open Font License 1.1で配布し、アプリのMITライセンスとは区別します。

## 取得の再現

`provenance.json` のURLからZIPを取得し、SHA-256を照合して記録したパスの2ファイルを取り出します。
ライセンスは https://raw.githubusercontent.com/yuru7/udev-gothic/v2.2.0/LICENSE から取得します。
通常利用・ビルド時にダウンロードやOSへのインストールは不要です。
