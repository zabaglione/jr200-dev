# 選択的CIの契約

## 実装済み範囲と未実装の境界

`tools/ci_plan.py` は宣言済み入力と逆依存を使う分類器、`tools/ci_pipeline.py` は旧・新graph、
内容fingerprint、build cache、成功receipt、dynamic matrix、最終gateを扱う実行器です。
`minimal`、画面、入力、ジョイスティック、音声、game loopのsample、`SIDE CATCH`、`RELIC DIVE` の8 targetを登録し、
固定jrasmからCJRを作る実ジョブへ接続しています。
共有SDKは独立artifact targetではなく、各projectの `inputs.sdk` とtargetの `build_inputs` へ
正確なsource dependencyとして登録します。これによりmodule変更は、そのfileを使用するtargetだけを選択します。

固定WASM runnerのversion、source commit、module digest、request／result、timeout契約を実装し、
Macのローカルbundleで `minimal` のROMなしruntimeを確認しています。現在はCIから取得できる
Release資産が未公開のため、remote jobはエミュレータをbuildせず
`emulator=not_run`、`emulator_unavailable_reason=release_asset_not_published` をreceiptへ残します。
bundle配布後は `runtime_required=true` に切り替え、未提供や不一致をjob失敗にします。
ROMありBASIC/cassette試験はゲーム別のreplayを実測してから接続します。hardwareは常に別証拠です。

このworkflowはローカルで構文・planner・cache破損・gateを試験していますが、未pushの変更について
GitHub Actionsが成功したとは扱いません。remote実行結果はpush後のrun URLで別に記録します。

## 判定表

| 入力変更 | 必要な処理 |
| --- | --- |
| README／一般文書 | 文書検査のみ。ゲームビルドなし |
| ゲームAのsrc・組込みassets・build.json | Aのビルドと試験 |
| Aのtests | Aの再試験。ビルド入力が同じなら適合生成物を再利用 |
| AのREADME・game.json・media | Aの公開情報検査とWiki生成のみ |
| SDK共通モジュール | そのモジュールと推移的な逆依存先のビルド・試験 |
| jrasm採用版／共通build条件 | 影響する全ターゲットを再ビルド |
| テストランナー／テスト条件 | 影響する試験を再実行。ゲーム自体は入力不変なら再利用 |
| Wiki生成コード | Wiki試験と生成のみ |
| 判定器／CIポリシー／不明な入力パス | 保守的に対象を広げ、理由を出力。黙って除外しない |

宣言した入力パターンを拡張子による一般分類より優先する。埋め込むREADMEやPNGを文書として除外しない。
削除は旧パス、renameは旧・新パスの双方を扱い、base commitの旧graphと現在の新graphの和集合で
影響判定します。graphファイル自体の変更は保守的に全targetへ拡大し、削除されたtargetも別一覧へ残します。

## ターゲット登録形式（version 2）

`ci/targets.json` のtargetsには次の形式を使用する。以下は書式例であり実装済みゲームではない。

```json
{
  "id": "example-game",
  "kind": "game",
  "project": "games/example-game",
  "runner": "jr200-project",
  "depends_on": ["sdk-sound"],
  "build_inputs": ["games/example-game/src/**", "games/example-game/assets/**", "games/example-game/Makefile", "games/example-game/build.json"],
  "test_inputs": ["games/example-game/tests/**"],
  "doc_inputs": ["games/example-game/README.md", "games/example-game/game.json", "games/example-game/media/**"]
}
```

`project` はリポジトリ相対のproject root、`runner` は実行契約です。
依存先も同じ一覧に登録します。重複ID、未知依存、循環、絶対パス、`..`を拒否します。
初期パターンはPython `fnmatchcase` の一致規則を使う。シェルで展開しない。
入力の重複は全所有者を対象にする。SDKのテストだけの変更では依存ゲームを再ビルドしない。

`jr200-project` targetでは `build.json` の再帰includeとasset実依存を検出し、それぞれが
`build_inputs` に所有されていることをplanner開始前に検査します。拡張子だけでPNGやMarkdownを
分類せず、宣言したpathの役割を使います。

## Fingerprintと再利用

build fingerprintはtarget設定、build入力のpathとSHA-256、推移依存先のbuild fingerprint、
`toolchain.lock.json`、build tool、platform IDを含みます。test fingerprintはbuild fingerprint、
test入力、runner lock、emulator lock、test toolから計算します。testだけが変わった場合は同一build fingerprintの
CJRを再利用し、testを再実行できます。

復元cacheは次を満たした場合だけ使います。

1. target、platform、期待fingerprintが `ci-build.json` と一致する。
2. CJRとbuild reportのsize／SHA-256が記録と一致する。
3. build reportがassembler／CJR layout合格を記録し、CJRを再parseしてentryと宣言領域を満たす。
4. test省略には、上記artifactと完全なtest fingerprintへ結び付いた成功receiptも必要。

cache miss、内容破損、失敗・取消でreceiptがない場合は再実行します。cache hit表示だけでは省略しません。
破損したimmutable keyは上書きせず、そのrunでは再buildします。必要なら `cache_contract` を更新して
全keyを切り替えます。

PRはdefault branchのcacheをrestoreできますが、save step自体をmain pushに限定します。
GitHubの低信頼triggerに対するread-only cache制限も維持し、`pull_request_target` は使用しません。

## 現在のパイプライン

1. `repository-contracts` が構造とCI自身の回帰試験を実行する。
2. plannerがtracked入力、実依存、旧・新graphを照合し、fingerprintとmatrixを作る。
3. target jobが完全一致のbuild cacheと成功receiptを内容hashまで検査する。
4. 不足するbuildだけ固定jrasmを外部sourceから作り、対象targetだけをbuildする。
5. 完全receiptがなければtarget testを実行し、成功後だけreceiptを作る。
6. main pushだけがbuild／receipt cacheを保存する。
7. `required-gate` がplanner・必要jobの失敗／取消／想定外skipを失敗にする。

直前commitとの差だけでは、失敗／取消を挟んだ変更を見逃す。全ターゲットの現在fingerprintを信頼済み記録と照合する。
キャッシュ欠落・hash不一致・toolchain更新は再実行し、キャッシュhitだけを合格根拠にしない。
PRは読取り専用で検証し、公開資格情報や信頼済み記録の書込み権限を渡さない。
fork PRが生成したコード・成果物を権限付き `pull_request_target` 等で実行しない。

ゲームCIは別配布の固定エミュレータWASMを使用し、浮動mainや暗黙の再ビルドに依存しません。
bundleが利用できる場合はdefaultだけでなく、対象が宣言した全synthetic profileを実行し、
全件合格したprofile一覧を成功receiptへ記録します。local-ROM profileはローカル資産が必要な別gateです。
現在のworkflowにはエミュレータsourceのcheckout/build stepも、取得失敗時のfallbackもありません。
配布資産未公開の間はruntime未実施を明記し、構造試験成功をエミュレータ成功へ読み替えません。
runner lockやadapterだけの変更はtest fingerprintを無効化し、build fingerprintを変えません。

2026-09-23の[private main CI](https://github.com/zabaglione/jr200-dev/actions/runs/35818266477)では、
repository契約、全8 targetのbuild・構造試験、required gateが成功しました。
固定runner Release資産はまだなく、各targetのエミュレータ実行は`not_run`です。

## トリガー・公開・費用

初期トリガーはmainへのpush、main向けPR、手動実行のみ。作業branchのpushとPRを二重起動しない。
同一PRの古い検査は取り消せる。公開処理は別groupで直列化し、途中取消で配布物を壊さない。
必須workflow全体をpathsでskipせず、不要jobだけを内部条件でskipする。
全件実行はtoolchain／全体共通変更・リリース受入・明示手動実行に限定し、定期的な全件buildは設けない。

Wiki処理はゲームbuildの後処理に固定しない。紹介文変更だけならゲームbuild候補0件となり、
文書検査と差分同期で完結する。候補packageの検査とローカル同期は `tools/wiki/generate.py` が扱う。
成果物が未検証／未公開ならゲームページを公開しない。検査と公開の権限を分離する。

## CI自体の受入

文書のみ、単一ゲーム、共有・推移依存、testのみ、組込み素材と紹介画像、rename／削除、graph変更、
未分類パス、失敗／取消を挟む変更、キャッシュ欠落・破損、toolchain／runner更新、空matrixを検査する。
単体テストはパス・逆依存・旧新graph・Git差分、build/test fingerprint分離、成功receipt、
cache欠落・破損、失敗結果の再利用拒否、空matrixとgateを対象にします。固定runnerのMac実行は
別途確認しますが、remote Actions、Linux runner実行、実ROM、Wiki公開はこのローカル試験に含みません。

## 一次資料

- [動的matrix](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations)
- [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [必須チェックとskip](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)
- [Dependency caching](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching)
- [Cache access and `cache-mode`](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
