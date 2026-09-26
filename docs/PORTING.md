# JR100dev作品のJR-200移植契約

JR100devの作品を、既存jrasmとJR-200 SDKで再実装するときの契約です。
作業状況はIssue（第1弾 #10〜#26、残り作品 #57〜#63）で管理し、この文書には移植の判断基準だけを置きます。

## 参照基準

| 対象 | revision |
| --- | --- |
| 参考作品・Wiki原稿 | `zabaglione/jr100dev@9a3921c4371d84c55fc468879dbed2f00fe42960` |
| 開発環境の着手時点 | `zabaglione/jr200-dev@92fc54dee29447b2de33a122fed2b26cf4e48bd9` |
| Webエミュレータ | `zabaglione/jr200-web-emulator@c4c0c30f98c5878480c31af8595b6307e66b8ef0` |

上流の作品一覧は [`porting/jr100-ledger.json`](porting/jr100-ledger.json) に固定します。
台帳は上流の`collection.json`、`library.json`、`SOURCES.md`と各作品の`game.json`から作った
メタデータ評価で、プレイ試験の結果ではありません。入力3ファイルのSHA-256を台帳に記録し、
`tests/test_porting_ledger.py`が51件の一意性、6ジャンル、手書きASM 7件／Pythonルール44件、
第1弾の境界を検査します。

## 引き継がないもの

- JR-100のPRG、BIN、MiSTer向け配布物、pyjr100emuのプレイURL、JR-100画面の画像。
- JR-100のVIA、PCG、キーボードmatrix、framebufferのアドレス、および`$0300`起動のABI。
- MB8861H固有命令（`ADX`など）と未文書opcode。JR-200では`rules/`の禁止命令検査に従う。
- JR100devの専用Pythonコンパイラ、`native/runtime.asm`、`common/`のコード。機能の仕様として読み、
  JR-200 SDKの規則で書き直す。汎用コンパイラやJR100のツールチェーンは新設しない。
- JR-100のCTRL+C、パッド配線、固定60 Hz clockの前提。JR-200で実測した方式に置き換える。

## 再実装の方針

1. 上流の`rules.py`と面データを仕様として読み、機種に依存しない検証用モデルを
   `tests/`へPythonで書く。モデルは8-bit演算を含めて上流の値の変化を再現する。
2. ゲーム本体はjrasmのM6800 assemblyで手書きする。面データは上流の値を`.db`で持ち、
   出典と上流のhashを作品の`UPSTREAM.md`へ記録する。
3. まず上流の規則・面・操作回数・勝敗を再現し、その後でJR-200の属性色と音を足す。
   色だけで状態を区別させず、文字や模様も変える。
4. 固定runnerの入力replayでRAM上の状態を観測し、検証用モデルの期待値と照合する。
   画面hashだけで規則の正しさを合格にしない。
5. 由来はMIT。作品directoryに上流`LICENSE`全文、`UPSTREAM.md`、組込みSDKのBSD noticeを置く。

## JR100devの実行処理とSDKの対応

| JR100devの`native/runtime.asm`等 | JR-200 SDK |
| --- | --- |
| タイトル／説明／面進行／CLEAR・LOSE・END、`CONFIRM_RESET` | `sdk/port.inc`（mode 0-5、確認は初期NO） |
| `FRAMEBUFFER`と`PRESENT` | `sdk/gfx.inc`の影画面と`jr_gfx_present` |
| ROM文字、`TEXT`、`NUMBER`、`digits` | `sdk/font.inc`の自作字形、`jr_gfx_text`、`jr_gfx_dec2`／`dec3` |
| PCGの2×2 `tile` | `sdk/pcg.inc`と`jr_gfx_tile`（属性mode 0x40） |
| VIA timerの`TICK`、`animate`、`hold` | `sdk/frame.inc`、`jr_port_animate`、`jr_port_hold` |
| 入力・tickと並行する演出 | `sdk/effect.inc`の`jr_effect_start`／`jr_effect_tick` |
| 押し続け・離上・リピート | `sdk/keyscan.inc`と`sdk/keyrepeat.inc`（一定間隔のpoll） |
| `sound(0-3)`とSFX表 | `sdk/sfx.inc`（第1弾）または`sdk/audio.inc`（3和音）、`jr_port_sound`、作品の`game_sfx_table` |
| 8-bitの乗除算 | `sdk/math.inc` |
| `rules.py`の`init`／`act`／`tick`／`draw` | 作品の`game_init`／`game_act`／`game_tick`／`game_draw` |

第1弾の作品は、code `$1000-$2FFF`、影画面`$3000-$35FF`、保存領域`$3600-$45FF`、
`JR_RT` `$4600`、状態`$4640-`、stack top `$4FFF`の同じ配置を使います。
各作品は`JR_SHADOW`（page境界の1536 bytes）、`JR_SAVE`（4096 bytes）、`JR_RT`（64 bytes）、
`GAME_STATE`〜`GAME_STATE_END`、専用stackを`build.json`のdata領域内に宣言します。
USR入口で`jr_session_enter`がBASICの画面・PCG・文字RAM・key maskとSを保存し、
ESC／CTRL+Cで`jr_session_leave`が戻します。演出（`jr_port_animate`）中に届いたキーは
終了以外を捨て、次の手を誤って確定しません（上流作品READMEの「演出中に押したキーで結果を飛ばさない」に合わせる）。
この演出待ちは同期処理で、効果音の進行と終了キーは処理しますが、通常入力やゲームtickを
並行処理する非ブロッキング演出ではありません。並行演出には`sdk/effect.inc`の
待機しないphase stepperを使い、作品のtick loopで入力・状態更新・描画を続けます。
stepの間隔は呼出元が決めるため、固定60fpsを前提にしません。

## 期待値の作り方

作品の`tests/model.py`は上流`rules.py`の値の変化を8-bitで再現し、`tests/port_model.py`が
`sdk/port.inc`の画面遷移（タイトル、説明、確認、次の面）を再現します。`tests/expectations.json`の
RAM期待値はこのモデルの予測値で、`tests/test_<作品>.py`がreplayからモデルを再実行して一致を検査します。
固定runnerは同じreplayをエミュレータで実行し、RAMが予測値と一致しなければ失敗します。
画面hashだけは実出力から固定し、Wikiの画像と同じ由来にします。

リアルタイム作品では、キーとtickの時間関係がエミュレータのcycleに依存するため、replayの状態を
モデルで予測できません。BRICK PULSEはタイトルの隠しキー`T`で自己試験を行い、固定状態から1 tick
進めたfixtureと、自動操縦で全面を遊んだ結果をRAMへ書き出します。入力がゲーム内で決まるため、
結果はモデルと1 byteまで一致しなければなりません。キー操作の試験はtickの位置に依存しない値
（パドルの最終位置など）だけを観測します。

描画1回は約2.5 frame（約56,000 cycle）かかるため、各作品は`GAME_RENDER_FRAMES`を2とし、
`jr_port_animate(n)`は描画後に`n-2` frameだけ待ちます。反転などの演出は上流より約2割遅くなります。

## 操作の対応

JR-200のキーは押下時のKey-On eventで読みます（`sdk/keys.inc`）。data latchは離上後も前の値を
保持するため、ターン制作品は押下eventだけを使います。押し続けが必要な作品（BRICK PULSE）は
`sdk/keyscan.inc`でキーボードMCUに今押しているキーを問い合わせ、上流の`held()`に当てます。
押下・リピート・離上を区別する作品は`sdk/keyrepeat.inc`を併用します。`jr_keyscan_init`後に
`jr_keyrepeat_init`し、一定周期で`jr_keyrepeat_poll`を呼びます。戻り値はAがraw key、
Bがevent（0なし、1押下、2リピート、3離上）です。単一キー契約で、キーを切り替えたときは
新しい押下だけを通知します。リピート遅延4回・周期2回はpoll回数であり、実時間や
固定60fpsを保証しません。ターン制の`keys.inc`とは混ぜず、作品の入力契約を選びます。

| JR100dev | JR-200版 |
| --- | --- |
| W/A/S/D、パッド方向 | W/A/S/D。ジョイスティックは作品ごとに実測してから掲載 |
| RETURN、パッドボタン | RETURN |
| SPACE（面のやり直し確認） | SPACE。確認の初期選択はNO |
| CTRL+C（BASICへ戻る） | ESCまたはCTRL+C |

## 第1弾の固定仕様

上流revisionは上記のとおりです。作品ごとのJR-200側の変更は表示・入力・音だけに限ります。

| 作品 | 上流版 | 維持する遊び | JR-200で変えるもの | Issue |
| --- | --- | --- | --- | --- |
| LUMEN CROSS | 2.0.0 | 5×5盤、十字反転、18面の初期配置式、60回上限、PAR表、PERFECT表示 | 盤面の色分け、影響範囲の予告記号、反転音 | #21 |
| CORNER CROWN | 1.5.1 | 8×8盤、8方向の挟み返し、パス、双方手なしで終局、最大捕獲を選ぶ相手、同数は敗北 | 石の色と形、返す演出、効果音 | #22 |
| CIRCUIT WORKS | 2.1.0 | 3段ゲート（AND/OR/XOR）、全8入力の試験、22問の目標表、TESTS回数 | 信号の色、一致・不一致の記号、効果音 | #23 |
| HEARTH ZERO | 2.1.0 | 薪・食料・火・壁、3種類の寒波×12日、3夜の予報、上限30/24、壁は最大2 | 資源記号と色、炎と雪の表示、効果音 | #24 |
| BRICK PULSE | 2.3.1 | 12面、各3球、装甲、ドローン（3面目から）、爆弾（6面目から）、W/S/G | 色分け、JR-200の保持入力、効果音 | #25 |
| RELIC DIVE | 1.6.1 | 既存移植（`games/relic-dive/UPSTREAM.md`） | 既存の属性色 | #14 |

SIDE CATCHはJR-200向け自作の導線確認作品で、JR100devの台帳には含めません。

## 残り作品の移植（第2弾）

台帳の残り45作品は`wave: 2`です。QUIET ROUTEとSEED MERGEは移植済みで、残る43作品を
次の順に1作品ずつ移植します（#57）。

| 段階 | Issue | 対象 |
| --- | --- | --- |
| ターン制・難度low | #59 | 18作品（QUIET ROUTE、SEED MERGEを含めて20） |
| ターン制・難度medium | #60 | 8作品（多面の解答replay） |
| リアルタイム | #61 | 11作品（作品内の自己試験と自動操縦） |
| JR-100手書きASM | #62 | 6作品 |

台帳の`status`は`planned`（未着手）、`ported-dev`（作品directoryあり・未公開）、
`ported`（`games/catalog.json`で`verified`）で、`tests/test_porting_ledger.py`が実際の
directoryとcatalogとの一致を検査します。

## JR-200の色と3和音

第2弾の作品は、JR-200の機能を次のように使います。

- **色**: 属性RAMの前景・背景8色と、PCGの色付きタイルで状態を示します。同じ情報を文字や模様でも示し、
  色だけに頼りません。作品のREADMEに「どの状態をどの色と記号で示すか」を書きます。
- **3和音**: `sdk/audio.inc`で音源F・D・Cを同時に鳴らします。タイトル曲（ループ）と、クリア・失敗の
  3声ジングルを持ちます。移動などの効果音はC系統で鳴り、その間だけ曲のC声部が止まって、終わると戻ります。

`sdk/audio.inc`は`sdk/sfx.inc`と同じ`jr_sfx_play`／`jr_sfx_tick`／`jr_sfx_stop`を持つため、
`sdk/port.inc`を変えずに置き換えられます。`game_sfx_table`のphraseの先頭を`0xfe`にすると、
その後の曲定義を3声ジングルとして鳴らします。作品は28 bytesの`JR_AUDIO`（標準配置では`$4700`）を宣言し、
`jr_session_enter`の後で`jr_audio_init`を呼びます。音符は`sdk/audio_notes.inc`（C2〜B6、
`tools/audio_notes.py`で生成）を使います。

音程はエミュレータの分周式で、F系統は最大17セント（低音域の整数Hz化による）、C・D系統は最大24セント
（A3付近）ずれます。旋律は精度の高いF系統に置きます。テンポは`jr_sfx_tick`の呼出し回数で進むため、
描画中は遅れます。3声の同時発音は、固定runnerのPCM peakが21000以上（1系統の振幅7000の3倍）で確認します
（`samples/chord`）。物理JR-200での音程・音量は未確認です。

公開済みの第1弾作品は`sdk/sfx.inc`のままです。`sfx.inc`と`port.inc`を変えないことで、公開済みCJRを
作り直さずに済みます。
