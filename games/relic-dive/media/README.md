# Media

固定エミュレータのROMなし合成profileから取得した320×224の画面と動画です。
メーカーROM／FONTは読み込んでいないため、標準文字の字形（HUDやメッセージ）は画像に出ません。
HUD文字codeと属性は実行時のメモリ期待値で別に固定しています。`gallery.json`が各画像のPNG SHA-256と
framebuffer SHA-256、元のprofileを固定します。

| file | profile | PNG SHA-256 | framebuffer SHA-256 |
| --- | --- | --- | --- |
| `title.png` | `synthetic-title` | `901fe670316e7f753850c13a7d6e3a58553f55e3e26851e0082fc37897684f29` | `f973f097a350401d0cd7d6508e41d095ba57026ead2ca7350830a6a6f6110a51` |
| `gameplay.png` | `synthetic-gameplay` | `4ecd49fcb11a121d059df26cc9bf4489c11426a84fbc93fc1193869a03d66430` | `5d85b5a6a9c1987a90f76c3da42205a5c1630a6c523cc9c40c7358b3a68e4a1f` |
| `combat.png` | `synthetic-combat` | `ce866cc57f8721ff54ed1871db29a059f2968bcbaa26ce5d5ee002fe2cf74806` | `0726f8ab86ec3851ce99949ec31231b86e7fc90c7129e0d052c9f12cff1e5334` |

`goal.webm`は`synthetic-combat`のreplayを固定エミュレータで記録した映像と音（16.5秒、等速）です。
最初の戦闘までで、全階クリアの映像ではありません。

これは固定エミュレータの証拠です。物理JR-200表示、実機入力、実機音声は未確認です。
