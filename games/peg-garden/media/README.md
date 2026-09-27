# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。ペグが隣のペグを飛び越える図 |
| `play.png` | `synthetic-first-jump` | 最初の1手。上の石が中央の穴へ飛び込み、間の石が消えた |
| `clear.png` | `synthetic-clear` | 15回飛び越して残り5個でクリア |

`goal.webm`は`synthetic-clear`のreplayを固定エミュレータで記録した映像と音です（16.6秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
