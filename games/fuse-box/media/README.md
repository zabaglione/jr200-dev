# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。入と切のヒューズと切り替え中の形 |
| `play.png` | `synthetic-partial` | 1面で4個のスイッチを入れた途中。合った行と列の数字が緑に反転 |
| `clear.png` | `synthetic-first-clear` | すべての行と列の個数がそろって1面クリア |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（8.9秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
