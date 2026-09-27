# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。帽子・眼鏡・ネクタイの組み合わせの6つの顔 |
| `play.png` | `synthetic-files` | 調書を2冊開き、食い違う容疑者が赤くなった場面 |
| `clear.png` | `synthetic-first-clear` | 犯人を告発してGOLD DETECTIVEで解決 |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（3.1秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
