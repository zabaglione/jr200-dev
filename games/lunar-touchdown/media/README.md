# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面 |
| `play.png` | `synthetic-demo-play` | 自動デモで降下中の着陸船 |
| `clear.png` | `synthetic-demo-clear` | 広い台に着陸して1つ目の着陸地をクリア |

`goal.webm`は`synthetic-demo-clear`のreplayを固定エミュレータで記録した映像と音です（5.6秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
