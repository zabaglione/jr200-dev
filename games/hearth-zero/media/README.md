# Media

固定エミュレータのROMなし合成profileから`--screenshot`で取得した320×224の画面です。
文字はSDKの自作字形、絵は作品の自作PCGで描いているため、メーカーROM／FONTは使っていません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `synthetic-title` | タイトル画面 |
| `play.png` | `synthetic-night` | 1日目に壁を作った夜。雪が降り、3夜の予報が見える |
| `clear.png` | `synthetic-first-wave` | 最初の寒波の12夜を生き延びた |

`goal.webm`は同じ固定エミュレータで`synthetic-first-wave`のreplayを1/30秒ごとに記録した映像と、同じ実行の
PCMから作った動画です（27.9秒、1.0倍速）。`tools/capture_video.py`と外部のffmpegで
生成し、映像フレームとPCMのSHA-256を`gallery.json`に残します。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
