# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。砂地、足跡、探検家、岩、光 |
| `play.png` | `synthetic-survey` | 岩にぶつかった後、東へ2歩進んで測り直した場面 |
| `clear.png` | `synthetic-first-clear` | 遺物を掘り当てた1地点目のクリア |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（5.4秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
