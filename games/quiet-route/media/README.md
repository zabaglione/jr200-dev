# Media

所有するJR-200 ROM/FONTを固定エミュレータへローカル入力し、通常の
`MLOAD`→`A=USR($1000)`から撮影した320×224の画面です。画面は切り取りや
マスクをしていません。メーカーFONTの字形が出る場合も残し、ROM/FONTファイル
自体は同梱しません。

`gallery.json`はPNG・元のframebuffer・動画フレーム・PCMのhash、作品CJRと
固定profileを対応づけます。`receipts/`には画像に対応する通常カセット実行の
合格reportを保存し、期待値・CJR・画面hashの一致を確認します。ローカル資産の
bytesや個人pathは記録しません。

| file | profile | scene |
| --- | --- | --- |
| `title.png` | `local-rom-title` | タイトル |
| `play.png` | `local-rom-play` | 最初の経路 |
| `clear.png` | `local-rom-goal` | 1経路目の脱出 |

`goal.webm`は同じ通常カセットprofileのゲーム部分だけを30 fpsで録画し、
エミュレータが出したPCMとともに15.2秒・4倍速の動画へ符号化しました。
`tools/capture_video.py`と外部ffmpegを使用し、後から絵や音を描き足していません。

これは固定エミュレータの証拠であり、物理JR-200の動作・音声は未確認です。
