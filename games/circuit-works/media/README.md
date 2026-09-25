# Media

所有するJR-200 ROM/FONTを固定エミュレータに読み込み、通常のMLOAD→A=USR($1000)で起動して撮影した320×224の画面です。
画面は切り取り・マスクをせず、メーカーFONTの字形が画面に出る場合もそのまま残しています。ROM/FONTファイル自体は同梱しません。
`gallery.json`が各画像のPNG SHA-256とframebuffer SHA-256、元のprofileを固定します。
`receipts/`には各撮影profileの固定エミュレータ実行reportを保存し、CJR・期待値・画面hashを照合します。ROM/FONTの実体やローカルpathは含めません。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `local-rom-gallery-title` | タイトル画面 |
| `play.png` | `local-rom-gallery-play` | ステージ2の試験中。信号が配線を流れ、真理値表に結果が並ぶ |
| `clear.png` | `local-rom-gallery-goal` | ステージ1で8行すべてが一致 |

`goal.webm`は同じROM/FONT起動から`local-rom-gallery-goal`のreplayを1/30秒ごとに記録した映像と、同じ実行の
PCMから作った動画です（6.5秒、1.0倍速）。画面全体を無加工で収録しました。`tools/capture_video.py`と外部のffmpegで
生成し、映像フレームとPCMのSHA-256を`gallery.json`に残します。

これは固定エミュレータの証拠です。物理JR-200の表示、入力、音声は未確認です。
