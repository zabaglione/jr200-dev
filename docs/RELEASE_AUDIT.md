# 初版候補の公開前監査

## 結論

2026-09-22時点の初版候補は、ローカル開発・候補package・Wiki previewまで受入可能でした。
以下は当時の監査記録です。2026-09-23時点の差分は末尾の更新記録を参照してください。

公開不可の主因は次の3点です。

1. 現在のGit設定は、今後のGitHub向けcommitにnoreply identityを保証しません。
2. `SIDE CATCH 0.1.0` packageはdirty tree由来のcandidateで、`release_ready=false` です。
3. 固定エミュレータrunnerのRelease資産が未公開で、remote CI／fresh clone再現を実施できません。

## 監査範囲と結果

`tools/release_audit.py --strict` は、Git管理済みfileとignore対象外の未追跡file、全Git履歴、
catalogが指す固定packageを対象にします。既知credential形式、private key、個人absolute path、
禁止拡張子、symlink、未審査binary、UTF-8、BSD SPDX、package内fileとlicenseを検査します。

- current tree: candidate全fileを検査。検出値を表示するsecret候補や個人absolute pathはなし
- Git history: 現在の全refを検査。既存2 commitのauthorはGitHub noreply
- identity: 現在解決されるcommit emailはnoreplyではないため、新規commitのhard stop
- game asset: `SIDE CATCH` のPCGは自作。外部asset、ROM、メーカーFONT、録音を含まない
- screenshot: ROMなし合成profileの320×224 framebuffer。PNGと画素hashをcatalog／reportで照合
- package: CJR、README、metadata、BSD-3-Clause全文、build／runtime report、checksumを照合
- jrasm: 外部固定commitを実行するだけで、source／binary／上流sampleを再配布しない
- emulator: 固定WASM bundleはローカル利用のみで、repository／package／Wikiへ含めない
- physical JR-200: 未実施。エミュレータ合格を実機合格とは扱わない

監査toolは候補版であること自体をcredential事故と混同せず、`blocks` と
`publication_gates` を別に報告します。現在はnoreply identityがblock、候補状態とrunner資産が
publication gateです。「secretが存在しない」という無限定な保証ではなく、上記scopeで候補が
検出されなかったという結果です。

## remote状態のread-only確認

2026-09-22のGitHub API結果はrepositoryがprivate、Wiki機能がenabledでした。
一方、認証付きWiki cloneでも `jr200-dev.wiki.git` は取得できず、Wiki worktreeは未検証です。
初期page未作成または権限経路の問題を切り分けるまでWiki同期を実行しません。

未push変更に対するGitHub Actions、Linux runner、Release URL、Wiki linkのHTTP到達性は未検証です。
ローカルのActions相当検査をremote CI成功と読み替えません。

## 公開へ進む条件

1. 差分監査後、履歴で確認済みのGitHub noreply addressをone-offまたはrepository-localで指定する。
   global Git設定は変更しない。
2. 明示されたsource一覧だけをcommitし、commit後にidentityとclean treeを再確認する。
3. remote CIで文書のみ／単一作品／SDK共通変更／全件の必要caseを実測する。
4. 固定runnerを権利・provenance確認済みRelease資産として用意し、Linux CI実行を合格させる。
5. fresh cloneのMacでjrasm導入、template、4 sample、作品のbuild／run／packageを再現する。
6. clean commitから作品packageを再生成し、catalogを `verified`／公開指定へ変更して再監査する。
7. Release作成、Wiki初期化／push、visibility変更は対象を明示した別承認後に実行する。

履歴書換えとforce pushは本監査の範囲外です。

## 2026-09-23更新

- リポジトリ内だけのGit設定を、履歴で確認済みのGitHub noreplyへ変更した。
  global設定は変更していない。再監査ではidentityの`blocks`は解消した。
- private Wikiの初期化と基本案内4ページのpushを確認した。作品ページとゲーム実行リンクは未公開。
- 公開Webエミュレータには固定カタログからのワンクリック読込み機能が追加されたが、
  カタログは空で、CJRは配布していない。
- source 139ファイルをnoreply identityのcommit `211a64f`へ固定し、private `main`へpushした。
  [remote CI](https://github.com/zabaglione/jr200-dev/actions/runs/35818266477)は、
  repository契約、全8 targetのbuild・構造試験、required gateに合格した。
  ただし固定runner資産がないため、CIでのエミュレータ実行は`not_run`である。
- 別のfresh clone（Mac arm64）で`make check`の114件、固定jrasmのfixture、
  template・5 sample・2 gameの計8 targetのCJR buildが合格した。
  このfresh cloneではrunner実行と作品package生成は行っていない。
- `SIDE CATCH`の候補packageはdirty tree由来のまま。固定runnerのRelease資産もない。
  `publication_ready=false`のため、作品Releaseと開発リポジトリのpublic化は保留する。

この更新は2026-09-22の監査結果を遡って変更するものではない。上述のremote CIと
fresh cloneの確認はsource buildまでであり、ゲームのruntimeや物理JR-200の証拠ではない。

## 2026-09-25更新

`SIDE CATCH 0.1.0`はcleanなsource commit `f59e3d6`から候補ZIPを生成し、別のfresh cloneで
同じSHA-256へ再現した。合成2 profileと所有ROM／FONTを使う通常MLOAD・BASIC復帰profileを
収録し、ZIPの`release_ready`はtrueになった。ただし状態は`candidate`／`not-published`のままで、
固定runnerのRelease資産とremote runtimeは未提供、物理実機も未確認である。

監査では、開発中作品のWebM 6件を`gallery.json`のfile名・SHA-256・ROMなしprofileと照合し、
未知・破損・symlink・10MB超・既知形式のASCII秘密情報を検出した動画は引き続きblockする。一致した6件も動画の内容・生成由来を
独立に実証したわけではないため、各fileを`publication_gates`に残す。固定packageを置いた
ローカル監査では`blocks=[]`、`publication_ready=false`だった。WebMの確認と固定runner配布、
作品の公開指定が済むまで、Release配信やpublic化を実行しない。
