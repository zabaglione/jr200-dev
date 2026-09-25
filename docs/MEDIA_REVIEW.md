# 7作品の動画公開レビュー（2026-09-25）

対象は `tools/release_audit.py` の `REVIEWED_GALLERY_VIDEOS` に列挙した7つの
`goal.webm` の**固定バイト列だけ**です。リスト外やハッシュ変更後の動画は、
たとえ `gallery.json` を更新しても再レビューまで公開ゲートに残ります。

各動画について、FFmpegで冒頭付近と終了付近のフレームを抽出して目視し、
`ffprobe` の再生時間を `gallery.json` と照合しました。いずれもJR-200の
ゲーム画面全体であり、外部作品の映像、個人情報、起動前のBASIC画面は
見当たりませんでした。終了場面はSIDE CATCHの捕獲、RELIC DIVEの最初の戦闘、
LUMEN CROSSの第1面クリア、CORNER CROWNの39対25、CIRCUIT WORKSの8/8一致、
HEARTH ZEROの12日目、BRICK PULSEの第1面クリアと一致しました。

`gallery.json` は動画バイト列、生成時のフレーム列とPCM、対象CJR、通常
`rom-cassette` profileを固定しています。`media/receipts/` の実行結果は
所有ROM/FONTを与えた固定エミュレータでの通常MLOAD/USR成功と画面ハッシュを記録し、
`tools/wiki/generate.py` が画像・動画・receiptの整合性を再検査します。
ゲーム本体と字形源はこのリポジトリの自作ソースです。メーカーFONTの字形が
撮影画面に現れる場合は加工せず残していますが、ROM/FONTファイルそのものは
画像・動画・ZIP・Gitへ格納していません。

このレビューは抽出した場面と生成経路・固定ハッシュの確認であり、
全フレームの人手確認や実機動作の証明ではありません。動画を差し替えた場合、
再度内容・来歴を確認してから固定ハッシュを更新します。
