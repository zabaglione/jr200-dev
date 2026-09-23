# Third-party components

本リポジトリには、MIT Licenseのゲームソース `RELIC DIVE` を出典とライセンスを保持して
取り込んでいます。第三者のメーカーFONT、ROM、商用テープ、録音は取り込んでいません。
本リポジトリのroot LICENSEは外部プロジェクトや個別ライセンス作品に適用されません。

| 外部プロジェクト | 用途 | 取扱い |
| --- | --- | --- |
| [ypsitau/jrasm](https://github.com/ypsitau/jrasm) | JR-200アセンブラ | `45d0ba18aed74bf09465db5dde3933618ae0b314`（banner 1.0.2）を外部実行ファイルとして利用。リポジトリ全体のライセンス宣言を確認できないため`NOASSERTION`とし、ソース／実行ファイル／上流sampleを再配布しない |
| [jr200-web-emulator](https://github.com/zabaglione/jr200-web-emulator) | 実行・互換性確認、CJR/WAV検査 | 固定source commitのWASM bundleをローカル利用。source・module hash・ABIを `emulator.lock.json` で固定するが、bundle自体は同梱せずRelease資産も未公開 |
| [zabaglione/jr100dev RELIC DIVE](https://github.com/zabaglione/jr100dev/tree/9a3921c4371d84c55fc468879dbed2f00fe42960/games/relic_dive) | JR-200版ローグライクの移植元 | revision `9a3921c4371d84c55fc468879dbed2f00fe42960` のMIT Licenseソースと独自PCGを改変して `games/relic-dive` に収録。上流hash、変換内容、MIT全文は作品内に保持 |
| [actions/checkout](https://github.com/actions/checkout) | GitHub Actionsでのcheckout | CIからcommit固定で参照。ゲーム配布物には含めない |
| [actions/cache](https://github.com/actions/cache) | GitHub Actionsのbuild／receipt cache | CIからcommit固定で参照。ゲーム配布物には含めない |

jrasmの[README](https://github.com/ypsitau/jrasm/blob/45d0ba18aed74bf09465db5dde3933618ae0b314/README.md)にはMac/Linuxビルド手順があります。
固定commitの現行macOSでの確認範囲と導入手順は[docs/JRASM.md](docs/JRASM.md)に記録します。
公開されていることやbuild可能であることを、改変・再配布の許諾とは扱いません。
コード・アセットを追加する際は、ファイル単位の出典、権利者、許諾条件を記録してください。
