# BRICK PULSE 第12面・Safari追加受入（Issue #47）

2026-09-25。macOS 26.6.2、MacBook Pro / Apple M3 Max、native Safari 26.6.2。
所有するJR-200 ROM（16 KiB）とFONT（2 KiB）をブラウザのファイル選択で読み込んだ。
ROM/FONTはGit、公開サイト、計測用HTTPサーバー、ログへ渡していない。

## 対象と方法

- 公開Pagesの`game-catalog.json`、`backend.json`（Emscripten）、固定CJRをHTTP取得し、ローカル正本catalogと一致、CJRはSHA-256
  `427068c12442ccfe04673e9a5ab30036f7d1b6b004061ba4d9c83ccc2ff85ba1`と一致することを計測前に検査した。
- `tools/brick_pulse_browser_bench.py`は、公開Pagesの資産をlocalhostへ読み取り専用で中継する。
  `app.mjs`だけに計測用のメモリ参照・時間計測hookを追加する。公開CJR、WASM、
  ゲーム処理、ブラウザ入力経路は変更しない。したがって公開サイトそのものにhookが存在するという主張ではない。
- `?game=brick-pulse&launch=1`から通常のカセット`MLOAD`と`A=USR($1000)`を実行し、
  タイトル表示を確認した後にEnterで第1面を開始した。第12面の負荷だけを短時間で測るため、
  診断hookで現在の面番号とクリア状態を設定し、通常の「次の面」操作で第12面を初期化した。
  第1〜11面を連続プレイして到達した測定ではない。12面のルール全体は既存の固定runner自己試験で検証済み。
- CPU速度は既定の100%。`codec.machine.run`の1回の実行時間を`performance.now()`で採取。
  パドル遅延はDOMのkeydownからゲームRAMの`BP_PADDLE`変化までを`requestAnimationFrame`で観測した。
  画面の物理表示遅延や入力装置側の遅延は含まない。

再現コマンド（Safariのリモートオートメーションを有効化し、別端末で`safaridriver -p 4447`を起動）:

```sh
python3 tools/brick_pulse_browser_bench.py \
  --emulator /absolute/path/to/jr200-web-emulator --pages \
  --webdriver http://127.0.0.1:4447 \
  --rom /private/path/to/JR200.rom --font /private/path/to/FONT.bin
```

## 観測値と判定

第12面の更新は3回合計903回、1回の処理時間は各回p95・最大とも1ms
（Safariの計時分解能は約1ms）。初期の入力遅延集計では各回5押下中1回の
未応答を除外してしまい、最大87 / 89 / 87msと過小報告したため、
この値は受入値として採用しない。修正版の押下別検査では、
第12面の`d`短押し（180ms）がDOMのkeydownに到達しても
パドルが動かない事象を複数回再現した。発生時は`JR_PORT_MODE=1`（プレイ中）、
パドル12で、端にいたためではない。
更新処理は1フレーム16.7ms未満、入力は2〜3ゲームtick（13tick/sの約154〜231ms）
を目安に200ms以下を暫定許容値とした。更新処理時間は満たしたが、
入力の未応答により総合判定は未達。アニメーション待機中に押下を消費する
可能性を調査・修正し、同じ測定をやり直す。

短押しでパドル12→14、離上後は位置固定。長押しで左へ継続移動した。
フォーカス喪失は再挑戦後、中央付近のパドル10・`BP_HELD=3`でAを押し続けたまま
新タブへ明示切替した。キー解放命令を送る前に元タブで`BP_HELD=0`、
パドル6で停止したことを確認した。切替から観測までに少し移動したため、
フォーカス喪失と同じ瞬間の停止を保証する値ではない。
3球喪失後の再挑戦は、Enterで確認dialogを開き、DでYESを選んでEnterを押し、
第12面の初期位置12へ復帰した。押しっぱなし残留は観測されなかった。

Chrome 153／Firefox 155／Playwright WebKit 26.6で既に確認した第1面の
短押し・保持・離上・フォーカス喪失と、native Safariの結果に機能差は見られなかった。
Safariの第12面数値を他ブラウザの第1面数値と同条件の速度比較としては扱わない。
物理JR-200の入力・映像・音声を試験した結果ではない。
