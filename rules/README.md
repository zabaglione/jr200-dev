# JR-200開発ルール

このディレクトリは、ゲームを組み立てる前に機械的に検査する条件の正本です。
`jr200.json` はビルダーが読む値、本文書はその根拠と未確認範囲を示します。

## 根拠の区分

| 区分 | 根拠 | このリポジトリでの扱い |
| --- | --- | --- |
| 一次資料 | Panasonic JR-200U Service Manual、Motorola M6800 Programming Reference Manual | CPU、標準メモリマップ、表示領域、割込みベクタの基本条件 |
| 実装確認 | `jr200-web-emulator` commit `81e4174c550e20e166b0431b4235ba3b7650da76` | MN1271の詳細レジスタ、32 byteミラー、合成試験でのキー／音声挙動 |
| 暫定開発契約 | jrasmのCJR出力とBASICからの `USR` 呼出し | テンプレートのロード・起動・復帰手順。実機確認ではない |

一次資料の参照先:

- [Panasonic JR-200U Service Manual](https://vintagevolts.com/wp-content/uploads/Panasonic-JR-200U-Service-Manual.pdf)
  （取得した80ページ版のSHA-256: `1aaa089689510f50208f608bd1c6ed0a2a0e97e4f1df664c1bb27ed49fb7015e`）
- [Motorola M6800 Programming Reference Manual, M68PRM(D), 1976](https://www.bitsavers.org/components/motorola/6800/Motorola_M6800_Programming_Reference_Manual_M68PRM%28D%29_Nov76.pdf)
  （照合した130ページ版のSHA-256: `2e2844975198c7bdefe32abd57f8f1425b8b2e4d3a4a13135739b26d87d860fa`）
- [JR-200 Web Emulatorの周辺回路監査](https://github.com/zabaglione/jr200-web-emulator/blob/81e4174c550e20e166b0431b4235ba3b7650da76/docs/P05_PERIPHERAL_AUDIT.md)

サービスマニュアルはJR-200U版です。JR-200の地域差を実機で測定した証拠ではありません。

## CPUと命令

JR-200UのCPUはMN1800Aです。開発時はMotorola M6800の文書化された命令セットを使います。
M6800資料は72個のソース命令、197個の有効な機械語、59個の未割当機械語を示しています。

未文書opcode `$14` を `NBA` として扱う実装例はありますが、Motorola資料では未割当で、
JR-200実機での互換性も確認できていません。このため `NBA` は禁止命令です。
jrasmが受理しない命令に加え、ソース検査でも明示的に拒否します。データとしてのbyte値は
命令と区別できないため、`.db 0x14` 自体は拒否しません。

## メモリとスタック

| 範囲 | 一次資料の用途 | 開発規則 |
| --- | --- | --- |
| `$0000-$07FF` | BASIC work area | ロード禁止。BASICから呼ぶコードは破壊しない |
| `$0800-$7FFF` | User RAM area | CJRの通常ロード可能範囲 |
| `$8000-$9FFF` | expansion | 標準機を前提とする配布では使用しない |
| `$A000-$BFFF` | BASIC ROM area 1 | ロード禁止 |
| `$C000-$C7FF` | VRAM | 実行時I/O。初期CJRのロード領域にはしない |
| `$C800-$C9FF` | MN1271 | 実行時I/O |
| `$CA00-$CBFF` | CRTC | 実行時I/O |
| `$CC00-$CFFF` | expansion | 標準機を前提とする配布では使用しない |
| `$D000-$D7FF` | Character Generator RAM | 実行時に生成・転送し、メーカーFONTを同梱しない |
| `$D800-$DFFF` | expansion | 標準機を前提とする配布では使用しない |
| `$E000-$FFFF` | BASIC ROM area 2 | ロード禁止 |

M6800のスタック位置はソフトウェアが初期化するもので、CPU資料は特定アドレスを既定値にしていません。
BASICの内部stack位置を固定ABIとして仮定しないでください。`basic_usr` テンプレートはSレジスタを
変更せず、呼出元が積んだreturn addressを `RTS` で取り出します。独立起動コードで `LDS` を行う
場合は、コード・データ・BASIC作業領域と重ならない専用領域を別途宣言する必要があります。

## 割込み

M6800の上位8 byteは、IRQ `$FFF8`、SWI `$FFFA`、NMI `$FFFC`、RESET `$FFFE` から始まる
2 byteベクタです。JR-200UではROM2内にあり、ゲームから直接置換できません。サービスマニュアルでは
BREAKがNMIへ入り、MN1271がkeyboard、system、user、timer、serialのIRQを集約します。

割込みルーチンを導入する場合は、BASICの既存処理、レジスタ退避、acknowledge、`RTI` を含む経路を
エミュレータで個別に検証してください。最小テンプレートは割込みmaskやベクタを変更しません。

## 画面・入力・音声I/O

一次資料で確認できる表示領域は、表示code `$C100-$C3FF`、属性 `$C500-$C7FF`、
user pattern `$C000-$C0FF` と `$C400-$C4FF`、標準character RAM `$D000-$D7FF` です。
画面は32文字×24行、1文字8×8 dotです。属性byteは上位2 bitがmode、背景3 bit、前景3 bitです。
border色はCRTC領域へ書きます。

次の詳細アドレスは固定エミュレータ実装と合成試験で確認した値で、実機測定ではありません。

| 機能 | アドレス／レジスタ |
| --- | --- |
| key/joystick data | `$C801` |
| KTEST/KACK control | `$C803` |
| key IRQ status / mask | `$C81C` / `$C81E` |
| sound channel C | `$C812-$C813` |
| sound channel D | `$C814-$C815` |
| sound channel F | `$C819-$C81B` |
| MN1271 mirror | `$C800-$C9FF`、下位5 bitで32 byte反復 |
| border write | `$CA00-$CBFF`、下位3 bit |

属性mode 0x40では、code 0x00-0x1Fが`$C000-$C0FF`、code 0x80-0x9Fが`$C400-$C4FF`のpatternを使い、
mode 0x00は`$D000-$D7FF`の文字RAMを使います。mode 0x80／0xC0はcodeと属性の各3 bitで4分割の色を塗る
semigraphicsです。これらは固定エミュレータの描画実装で確認した値です。Key-Onの状態bitはmask `$C81E`
bit 0を立てた後の押下だけを記録し、読出しで解除されます。

`sdk/screen.inc`、`sdk/input.inc`、`sdk/sound.inc`、`sdk/timing.inc` が、この表に対応する
最小routineを提供します。作品側は利用moduleだけを `build.json` の `inputs.sdk` に宣言します。
これらは固定エミュレータで確認済みですが、物理JR-200のI/O測定結果ではありません。

## ロード、実行、BASIC復帰

最小契約はロード先とentryを `$1000` に置き、CJRをロードした後にBASICから
`A=USR($1000)` で呼び出すものです。routineはSレジスタを保ち、最後に `RTS` します。
これは開発用の暫定契約です。構造検査とjrasmによるCJR生成は、BASIC起動、エミュレータ実行、
実カセット、実機の成功を示しません。各段階の結果は生成される `build-report.json` で分離します。
