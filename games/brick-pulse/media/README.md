# Media

3枚のPNGと`goal.webm`は、所有ROM/FONTをローカルで読み込み、通常の`MLOAD`と
`A=USR($1000)`を経た固定エミュレータの実出力です。320×224の画面は切り抜き・
塗りつぶしをせず、動画はその画面と同じ実行のPCMから等速で作りました。
`gallery.json`には元CJR、自作ASCII字形source、replay、画像・framebuffer・
動画フレーム・PCMのSHA-256を固定しています。
`receipts/`には3場面の固定エミュレータ実行reportを保存し、CJR・期待値・画面hashを照合します。
ROM/FONTの実体やローカルpathは含めません。

| file | profile | 場面 |
| --- | --- | --- |
| `title.png` | `local-rom-title` | 起動後のタイトル |
| `play.png` | `local-rom-hold-left-release` | 第1面のプレイ中 |
| `clear.png` | `local-rom-demo-clear` | 第1面の自動デモクリア |

`goal.webm`は同じ固定エミュレータで`local-rom-demo-clear`のreplayを1/30秒ごとに記録した映像と、同じ実行の
PCMから作った動画です（45.4秒、等速）。`tools/capture_video.py`と外部のffmpegで
生成し、映像フレームとPCMのSHA-256を`gallery.json`に残します。前半のBASIC起動・ロード画面と音は含めません。

メーカーFONTの字形が画面に映る場合がありますが、ROM/FONTファイル本体はリポジトリ、
作品package、画像・動画へ組み込んでいません。これは固定エミュレータの証拠です。
物理JR-200の表示、入力、音声は未確認です。
