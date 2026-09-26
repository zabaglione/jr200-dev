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

## BRICK PULSE 0.1.1 の差し替えレビュー

修正版CJR `ed27d003afab3adda49d722514bed00ffe10575cac8cfc0f9bcfb34e15f86972`
を所有ROM/FONTと固定runner v0.3.0の通常MLOAD/USR経路で実行し、
`tools/capture_video.py`の`local-rom-demo-clear` profile、30 fps、開始cycle
83,500,000から新しい`goal.webm`を生成した。生成時のフレーム列SHA-256は
`f70b15e49f84730649557d0af7b10325bfcd0716de3f874fb14837de53dc9da0`、
PCMは`315568d9e91c1d284b8b68ff7eaeda44ab796c515d0478f7bdf4e5bc8f67266c`、
WebMは`f288f5c24b133b403b01640c628725a122f8694e19c517b05d29dfa5d6e0ccf8`。
ffprobeではVP9 640×448、Opus mono、45.33秒。1秒、22秒、44秒のフレームを
抽出して目視し、BRICK PULSEの第1面が進行してクリアするゲーム画面のみを確認した。
起動前のBASIC画面、他作品の映像、個人情報は観測していない。
代表3場面も新CJR＋ROM/FONTで再撮影し、元のPNGと3件ともバイト一致したため、
既存PNGをそのまま保持した。メーカーROM/FONTのバイトは配布物へ含めていない。

## SIDE CATCH 0.1.3 の差し替えレビュー

捕獲累計を3桁表示するCJR `afb7532fb0add608acc147e1c8c96600357e455fe9ae183a61484493f691816b`を
所有ROM/FONTと固定runnerの通常MLOAD/USR経路で実行した。title/playのPNGは新CJRで
再撮影して旧版とバイト一致したため保持し、goalだけ無加工の実画面で差し替えた。
`local-rom-goal`から30 fps、開始cycle 82,800,000で動画を生成した。フレーム列SHA-256は
`8566c300950711229582b235c907278d3b1f08093a45c261573bb7332d7b4b3d`、
PCMは`14e645410798cb743abf42c266d76e94b74108fe114f29535900f6ce388c306d`、
WebMは`6737e0b01cf8813519a613f0e48081e16db13199d6893b3e0cf1b5db39327ff7`。
ffprobeはVP9 640×448、Opus mono、0.9秒を示した。冒頭と終了付近のフレームを目視し、
SIDE CATCHのゲーム全画面と累計`001`のみを確認した。起動前BASIC画面や個人情報は
見当たらず、メーカーFONTの字形も切り抜き・塗りつぶしをしていない。
この確認は物理JR-200の画面・音声を実測した証拠ではない。
