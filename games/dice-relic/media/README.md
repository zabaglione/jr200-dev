# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面 |
| `play.png` | `synthetic-attack` | 攻撃に使ったダイスと、使用済みダイスの拒否 |
| `workshop.png` | `synthetic-workshop` | 工房で面を鍛えた後の画面 |
| `goal.png` | `synthetic-first-victory` | 最初の守護者を倒して工房へ入る |

`goal.webm`は`synthetic-first-victory`のreplayを固定エミュレータで記録した映像と音です（8.3秒、等速、音源F・D・Cの出力を混合したPCM）。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
