# JR-200 minimal SDK

このdirectoryは、JR-200用M6800 assemblyから直接includeする最小共通moduleです。
各projectは使用するfileを `build.json` の `inputs.sdk` と `ci/targets.json` の
`build_inputs` に明記します。moduleはobject libraryではなく、jrasmの再帰include入力です。

| module | 提供機能 | 主な制約 |
| --- | --- | --- |
| `jr200.inc` | JR-200のmemory／I/O定数 | 最初に1回だけinclude |
| `screen.inc` | 画面消去、1 cell描画、自作文字8 byte転送 | `jr200.inc` 必須。IRQからの再入不可 |
| `input.inc` | key latch読出し、timeout付き待機 | `jr200.inc` 必須。IRQ mask／ackは変更しない |
| `joystick.inc` | BASIC ROM走査による1P／2P joystick読出し、active-low変換 | `jr200.inc`と初期化済みROM／FONT環境が必須 |
| `sound.inc` | channel Cのtone開始／停止、全channel停止 | `jr200.inc` 必須。count 0は禁止 |
| `timing.inc` | cycle基準のbusy wait | 実時間保証ではなく、Xを破壊 |
| `session.inc` | USR入口でのstack・IRQ mask・PCG・画面・文字RAMの保存と復元、高速copy | ゲーム専用stackへ切替える唯一のmodule |
| `keys.inc` | Key-On eventからW/A/S/D・RETURN・SPACE・ESC/CTRL+Cへの変換 | 押下1回=1 event。保持状態は返さない |
| `keys_ext.inc` | `keys.inc`と同じ操作1〜6に加え、作品の`game_key_table`（小文字キーと操作番号の組）で操作7以上を返す | `keys.inc`とは併用しない。上流の操作7=X、8=F、9=Q、10=E、11=Z、12=Cに合わせる |
| `keyscan.inc` | キーボードMCUのKTEST/KACK走査で「今押しているキー」を読む | 手順は固定エミュレータのMN1544実装に基づく。状態は`JR_RT+50..51`でcopy用領域と分離。ROMなし実行では起動時にfont転送を読み捨てる |
| `keyrepeat.inc` | `keyscan.inc`の現在キーから押下・保持リピート・離上eventを作る | `jr_keyscan_init`後に初期化し、一定周期でpoll。遅延4回・周期2回はpoll回数であり実時間ではない |
| `gfx.inc` | RAM影画面への文字・数値・2×2 tile描画と一括転送 | `JR_SHADOW`はpage境界。転送中はSを使用 |
| `font.inc` / `font_data.inc` | 自作5×7字形を`$D100-$D2FF`へ設置 | メーカーFONTを使わない。終了時に元へ戻す |
| `pcg.inc` | user pattern（code 0x00-0x1F／0x80-0x9F）の転送 | attribute mode 0x40で表示 |
| `frame.inc` | 約1/60秒のbusy-wait frame | 固定エミュレータのCPU clock基準 |
| `effect.inc` | 待機しない演出step／phase管理 | 呼出元がtickごとに進め、表示・入力・音声を並行処理する。実時間保証なし |
| `math.inc` | 8-bit乗除算、X+A | M6800命令のみ |
| `sfx.inc` | channel Cのnon-blocking効果音列 | frameごとに進める |
| `audio.inc` / `audio_notes.inc` | 音源F・D・Cの3声の曲とジングル、channel Cの効果音（`sfx.inc`と同じAPI） | `sfx.inc`とは併用しない。28 bytesの`JR_AUDIO`が必要。テンポは`jr_sfx_tick`の回数 |
| `port.inc` | タイトル・説明・面進行・クリア/失敗・やり直し確認・演出待ちの共通loop | 作品側hookを呼ぶ。演出待ちは同期処理で、効果音と終了キーだけを継続する |

`session.inc` と `gfx.inc` 以外の全routineは呼出元のSを初期化せず、`JSR`／`RTS` の範囲だけstackを使います。
`session.inc` はゲーム全体のSとIRQ maskを預かり、終了時に元へ戻します。`gfx.inc` の転送と
`jr_copy` はその間だけSをcopy元に使います。IRQ vectorとBASIC work areaは変更しません。
jrasmのsymbolは大文字小文字を区別しないため、作品側labelはmodule名と重ならない接頭辞を付けてください。
移植用moduleの使い方は [移植契約](../docs/PORTING.md) と `samples/port-fixture` を参照してください。clobberと入力条件は各file先頭に記載します。
busy waitとtone周波数は固定エミュレータでの観測値であり、物理実機の時間・音程保証ではありません。
`joystick.inc` はJR-200 BASIC ROMの入力走査entryとdirect-page作業領域を使用するため、
ROMなしmemory injectionだけでは動作確認できません。
