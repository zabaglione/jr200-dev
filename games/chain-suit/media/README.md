# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。4つのスート |
| `play.png` | `synthetic-redraw` | 1枚目と3枚目を引き直してスリーカードになった手札 |
| `clear.png` | `synthetic-first-clear` | 3回目の手札を採点して25点を超えたクリア |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（23.8秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
