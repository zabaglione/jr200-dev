# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面 |
| `play.png` | `synthetic-cut-play` | 計画した経路を刀が走り、標的を斬る場面 |
| `plan.png` | `synthetic-plan` | 経路を計画している場面（通った標的に四隅の印） |
| `clear.png` | `synthetic-first-clear` | 全標的を斬って1つ目の部屋を突破する |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（5.0秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
