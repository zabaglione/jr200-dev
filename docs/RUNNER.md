# 固定エミュレータrunner契約

## 固定対象

`emulator.lock.json` は `jr200-web-emulator` のcommit
`c4c0c30f98c5878480c31af8595b6307e66b8ef0`、Emscripten 6.0.9、
codec API 1、system API 9を固定します。runnerは次の2ファイルを同じdirectoryから読み、
sizeとSHA-256が一致しないbundleを起動しません。

| ファイル | bytes | SHA-256 |
| --- | ---: | --- |
| `jr200_codec.mjs` | 17276 | `0da8182674173af74ec529e71b29384cb530e6834269e9d4b615788a1d3fcf9c` |
| `jr200_codec.wasm` | 83629 | `8b0153570c4e7d0bd267ad8d3ae65eaefb1b18d51e5019a44475e58a6364ec20` |

このdigestは上記commitをクリーン展開し、Linux x86_64のEmscripten 6.0.9で
`emcmake cmake -DCMAKE_BUILD_TYPE=Release`とbuildを実行して得た実ファイルの値です。
system API 9は`jr200_system_set_joystick`を公開するため、adapter 0.3.0のactive-low `joystick`
replay（playerは`0`または`1`、stateは`0x00`から`0xff`）をこの固定bundleで実行できます。
ただしjoystick入力はBASIC ROMの走査routineを使うため、ROMなし合成profileでは確認できません。

前回の固定版（commit `81e4174c550e20e166b0431b4235ba3b7650da76`、system API 6）は、同じ手順の
Linux buildでも以前macOS arm64で記録したdigestとバイト単位で一致しました。Emscriptenの出力が
hostに依存しないことの実例です。Linux x86_64では2026-09-24に、全target（sample 6、ゲーム2）の
全合成profileが新旧bundleの両方で合格しました。

2026-09-25、上記digestと一致する現行bundleをmacOS arm64で検査し、`minimal`の
`synthetic-ci`（31 cycle）とローカルROM／FONTを使う`local-rom-mload`（15,000,003 cycle）が
期待値に一致しました。`joystick-sample`の`local-rom-joystick`も通常MLOAD／USR経路で
28,006,298 cycle後に合格し、1P／2Pのrawは`EA/D5`、pressedは`15/2A`でした。
lockのmacOS行はこの固定bundleの**実行確認**を示す`verified`へ更新しました。
Macでのクリーン再ビルド、全作品のMac実行、物理JR-200動作を示すものではありません。
ROM／FONTのbytes・hash・ローカルpathは記録や配布へ含めていません。

固定bundleをエミュレータ側の
[runner-v0.3.0 Release](https://github.com/zabaglione/jr200-web-emulator/releases/tag/runner-v0.3.0)
で公開しました。ZIPの匿名取得は142,300 bytes、SHA-256
`860f99be69037a78c6dea557cd28994b83ba7fe05709d512d8e86cb44b6c77b0`と一致しました。
module生成元commitは上記の`c4c0c30...`、配布手順のRelease tag対象commitは`df031a53...`で
別です。ゲームCIはエミュレータsourceをclone／buildするfallbackを持ちません。
Mac arm64の新規クローンではこのURLから取得し、固定jrasmで作成した`minimal` CJRを
`synthetic-ci`で31 cycle実行しました。同じcloneで画面・入力・音声・game loop・port fixtureの
追加19合成profileも合格し、表示、入力、PCM、終了経路を確認しました。Linux x86_64の
[PR CI run 36075596458](https://github.com/zabaglione/jr200-dev/actions/runs/36075596458)
は同じ公開ZIPを取得し、`minimal`を含む13 targetの合成runtimeが`emulator=passed`、
ROM専用`joystick-sample`は`local_rom_only`で全ジョブ成功でした。いずれも実機動作の証拠ではありません。

取得adapter `tools/runner_fetch.py` は固定URLとZIP全体のSHA-256、
2つのmoduleと7つの権利表示ファイルそれぞれのsize／SHA-256を`emulator.lock.json`で固定します。
ZIPはその9ファイルだけを許し、ROM／FONT、余計なファイル、重複path、symlink、暗号化entry、
展開容量超過を拒否します。URLは当該リポジトリのGitHub Release、redirectは承認したHTTPS hostに
限り、取得上限8 MiB・経過60秒超過の検知・read timeout 10秒です。認証tokenは渡さず、
例外内のsigned URLもログへ出しません。
破損ZIPや不一致時に既存directoryを置換せず、エミュレータのsource buildへfallbackもしません。
現在のlockは公開ReleaseのURLとdigestを固定し、CIでadapterを呼ぶと検証済みZIPを取得します。
Mac新規クローンとLinux CIでの配布受入後、`runtime_required=true`に設定しました。
取得不能・不一致・合成runtime未実施はジョブ失敗とし、`not_run` receiptを受け入れません。
ROM専用の`joystick-sample`は
`ci/runner.lock.json`で`local_rom_only`と明示し、CIではbundle取得対象から除外します。
receiptも`emulator=local_rom_only`、evidence=`not_run`、reason=`requires_local_rom_font`
を保存し、合成runtimeの成功には数えません。joystickの実測は利用者提供ROM/FONTによる
別のMac/Linux受入記録で扱います。他のtargetが合成profileを失えば検査を失敗させます。

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
