# Third-party components

初期ソースには、第三者のプログラム・フォント・ROM・ゲーム素材を取り込んでいません。
本リポジトリのLICENSEは外部プロジェクトに適用されません。

| 外部プロジェクト | 用途 | 取扱い |
| --- | --- | --- |
| [ypsitau/jrasm](https://github.com/ypsitau/jrasm) | JR-200アセンブラ | 利用者が別途用意する外部実行ファイル。採用revisionとMac実行結果は導入Issueで確定。ソース／実行ファイルの再配布は未承認 |
| [jr200-web-emulator](https://github.com/zabaglione/jr200-web-emulator) | 実行・互換性確認、CJR/WAV検査 | 別リポジトリの固定版を利用する計画。ランナー配布契約は未実装 |
| [actions/checkout](https://github.com/actions/checkout) | GitHub Actionsでのcheckout | CIからcommit固定で参照。ゲーム配布物には含めない |

jrasmの[README](https://github.com/ypsitau/jrasm/blob/master/README.md)にはMac/Linuxビルド手順があります。
この記載だけで、現行macOSでの動作確認や改変・再配布条件の確認を済ませたとは扱いません。
コード・アセットを追加する際は、ファイル単位の出典、権利者、許諾条件を記録してください。
