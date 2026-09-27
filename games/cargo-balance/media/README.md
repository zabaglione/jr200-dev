# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面。重さ別の色の木箱とクレーン |
| `play.png` | `synthetic-first-load` | 最初の4個を外側の船倉へ積んだ後 |
| `clear.png` | `synthetic-first-clear` | 12個を積み終えて1航海目のクリア |

`goal.webm`は`synthetic-first-clear`のreplayを固定エミュレータで記録した映像と音です（15.0秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
