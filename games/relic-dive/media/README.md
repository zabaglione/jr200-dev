# Media

固定エミュレータのROMなし合成実行から取得した、320×224 RGBA framebufferです。
メーカーROM／FONTは読み込んでいないため、標準文字glyphは画像に出ません。HUD文字codeと属性は
runtime memory expectationで別に固定しています。PCGによるタイトルとゲーム盤面の配色を確認できます。

| file | profile | PNG SHA-256 | framebuffer SHA-256 |
| --- | --- | --- | --- |
| `title.png` | `synthetic-title` | `c745ebd09746b0b8f89972340c9df835c64b9640f4ea3449eed74b9177787d23` | `3820bd73678d67160afd9a8d08b9a7430de40352b403667dd7ace9145425e17f` |
| `gameplay.png` | `synthetic-gameplay` | `4ecd49fcb11a121d059df26cc9bf4489c11426a84fbc93fc1193869a03d66430` | `5d85b5a6a9c1987a90f76c3da42205a5c1630a6c523cc9c40c7358b3a68e4a1f` |

これは固定エミュレータの証拠です。物理JR-200表示、実機入力、実機音声は未確認です。
