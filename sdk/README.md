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

全routineは呼出元のSを初期化せず、`JSR`／`RTS` の範囲だけstackを使います。
IRQ vector、IRQ mask、BASIC work areaは変更しません。clobberと入力条件は各file先頭に記載します。
busy waitとtone周波数は固定エミュレータでの観測値であり、物理実機の時間・音程保証ではありません。
`joystick.inc` はJR-200 BASIC ROMの入力走査entryとdirect-page作業領域を使用するため、
ROMなしmemory injectionだけでは動作確認できません。
