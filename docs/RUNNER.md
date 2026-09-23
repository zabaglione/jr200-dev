# 固定エミュレータrunner契約

## 固定対象

`emulator.lock.json` は `jr200-web-emulator` のcommit
`81e4174c550e20e166b0431b4235ba3b7650da76`、Emscripten 6.0.9、
codec API 1、system API 6を固定します。runnerは次の2ファイルを同じdirectoryから読み、
sizeとSHA-256が一致しないbundleを起動しません。

| ファイル | bytes | SHA-256 |
| --- | ---: | --- |
| `jr200_codec.mjs` | 16813 | `9b80046b09f058df7c9fddac4675a50be5a9ad0cb9256f5f37f0acb607eeb3d7` |
| `jr200_codec.wasm` | 82172 | `c79dc6843861a2358e54c11b73541db20e5adb8ea9c616c648357fb12932c846` |

このdigestは上記commitをクリーン展開し、Emscripten 6.0.9で作成した実ファイルから取得しました。
macOS arm64ではNode.jsからABI起動と最小CJRの実行を確認済みです。
Linux x86_64は契約試験だけで、同bundleの実行はまだ確認していません。

adapter 0.3.0はactive-lowの `joystick` replay eventを扱います。playerは`0`または`1`、
stateは`0x00`から`0xff`です。このeventの実行には
`jr200_system_set_joystick`を公開するsystem API 8 bundleが必要です。現在の固定lockはsystem API 6の
clean commitを指しているため、既存profileには利用できますがjoystick replayには利用できません。
system API 8側をclean commitとして固定できるまでは、API 8のローカルbundleと対応するローカルlockで
ROM／FONT試験を行い、固定bundle受入と混同しません。

現在はbundleのRelease資産を公開していないため、取得状態は `local_build_only` です。
`JR200_RUNNER_BUNDLE` または `--bundle` で既存のビルド済みdirectoryを明示します。
ゲームCIはエミュレータsourceをclone／buildするfallbackを持たず、bundle未提供を
`release_asset_not_published` として `emulator=not_run` に残します。Release資産と取得手段を
別途承認して用意するまでは、remote CIのruntime受入条件を満たしたとは扱いません。

## 実行

Node.js 20以降を使用します。runner自身はゲーム側のadapterであり、CPU、CJR、カセット処理は
固定WASM moduleのABIを呼び出します。

```sh
RUNNER_BUNDLE=/absolute/path/to/emulator/build/emscripten/web
make runner-doctor RUNNER_BUNDLE="$RUNNER_BUNDLE"
JRASM=/absolute/path/to/jrasm make template-build
make template-run RUNNER_BUNDLE="$RUNNER_BUNDLE"
```

利用者が権利を確認したローカルROM／FONTを使う通常 `MLOAD` profileは明示選択します。

```sh
python3 tools/emulator_runner.py run \
  --project templates/minimal \
  --bundle "$RUNNER_BUNDLE" \
  --profile local-rom-mload \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin
```

任意のゲームは対象を明示します。

```sh
make game-run PROJECT=games/my-game RUNNER_BUNDLE="$RUNNER_BUNDLE"
```

`tests/expectations.json` version 2がdefault profileと複数profile、mode、cycle上限、入力replay、breakpoint、
観測範囲、期待PC／memory／framebuffer hash／PCM frameを保持します。PCMはframe数、非0 sample数、
peakとdrop数を記録し、sample側で最低frame数・最低非0数・最大drop数を検査できます。
replayの `text` eventはASCII文字列を明示したpress／release列へ展開し、cycle、key duration、intervalを
固定します。`joystick` eventは0始まりのplayer番号とactive-low stateを保持します。
WASM runnerへ渡すrequestには展開後のkey eventとjoystick eventだけを含めます。
wall-clock timeoutは30秒、emulated cycle上限は
1回につき100,000,000です。requestとresultはversion 1のJSON契約で、runnerは次の終了codeを使います。

| code | 意味 |
| ---: | --- |
| 0 | 契約どおり実行しresultを生成 |
| 2 | request／引数が不正 |
| 3 | ローカルROM／FONT等がない |
| 4 | adapterのwall-clock timeout |
| 5 | runner／asset／ABIが非互換 |
| 6 | 期待値不一致用に予約 |
| 7 | runner内部エラー |

adapterは非0終了、timeout、result欠落、artifact hash不一致、期待値不一致を成功扱いにしません。
合格reportは最新の `build/runtime-report.json` に加え、profile別の
`build/runtime-reports/<profile>.json` に保存します。package時は同じartifactとexpectationsのhashへ
結び付くreportだけを使用します。

framebuffer hashはcoreの32-bit ARGB値をbrowser表示と同じ順序へ変換した、320×224の
canonical RGBA bytesに対して計算します。hostのendianには依存しません。
`--screenshot <new.png>` を指定すると、合成profileの検証済みcanonical RGBA framebufferだけを
決定的PNGとして保存できます。既存fileの上書き、ROM cassette profileからのcapture、
reportのframebuffer hashと一致しない画像を拒否します。これはWiki用画面例の由来を固定する機能で、
物理displayの証拠ではありません。

## 証拠の区分

### `synthetic-injection`

ROMなしで、検証済みCJRのdata blockをRAMへ直接配置し、user RAM上の合成caller trampolineが
安全なSを設定してentryを `JSR` します。対象routine自身はSを固定せず、`RTS` でcallerへ戻ります。
固定CPU／system ABIで入力replay、register、memory、framebuffer、PCM、cassette状態を
決定的に観測できます。これはエミュレータ実行の証拠ですが、BASICの `LOAD`／`MLOAD`、
通常カセット信号経路、実機動作の証拠ではありません。

### `rom-cassette`

利用者がローカル提供した16,384-byte結合ROMと2,048-byte FONTをWASMへ渡し、CJRを
`jr200_system_tape_mount` で通常カセットdeviceへmountしてreplayを実行します。
ROM／FONTのpathやbytesはrequest一時directoryとGit対象外のbuild report以外へコピーしません。
このmodeでも物理JR-200の確認にはなりません。対象ゲームごとのreplayと期待値を実測してから
合格記録に使用します。

最小テンプレートの `local-rom-mload` はMac上の固定bundleと利用者提供のローカルROM／FONTで
実行し、15,000,003 cycle後にcassette state `Finished`、playback mode、REMOTE off、
`$1000-$1001 = 01 39` を確認しました。これはJR BASICが通常 `MLOAD` とカセット信号経路を
通したエミュレータ結果です。ROM／FONTのbytes、hash、ローカルpathは成果物へ含めていません。

### `hardware`

runner reportは常に `hardware=not_run` です。実機LOAD／MLOAD、表示、操作、音声、WAV互換は
別の実測記録が必要です。
