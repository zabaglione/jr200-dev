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

## 2026-09-25追記: 初期2作品の候補再検証

固定runner `runner-v0.3.0` の公開ZIPを新規Macクローンで取得し、source commit
`de48784eacbaa7e7d21a4c76ebe2facc4a20d6ec`からSIDE CATCHとRELIC DIVEを
再build、全profile実行、単体package化した。合成profileはSIDE CATCH 2件、
RELIC DIVE 9件、所有ROM／FONTをローカル指定した通常MLOAD/USR profileは
SIDE CATCH 1件、RELIC DIVE 2件で成功。
両ZIPの`source.tree_state=clean`、`release_ready=true`を確認した。固定hashは
`games/catalog.json`に記載し、候補Wikiのpackage／ライセンス／checksum照合も合格した。
ROM、FONT、録音はZIPやGitへ含めない。両作品は`candidate`／`not-published`のままで、
作品Release、PagesへのCJR配置、公開Wiki同期、物理JR-200試験は行っていない。

`release_audit.py --strict`は、既存のテストfixtureと履歴内の個人パス形式をblockとして報告し、
さらに6件のWebM由来と未公開候補をpublication gateに残す。そのため公開監査合格とは扱わない。
Issue #14の階層遷移・敗北からの再挑戦もJR-200版での受入証拠が不足しており、
候補ZIPの生成成功だけでIssue完了とはしない。

## 2026-09-25再追記: RELIC DIVEの受入範囲拡張

固定runnerの合成profileで、1階の階段到達時のviewport・画面コード・属性、
`DESCEND`後の2階生成、HPが0になった敗北状態、タイトル経由の再挑戦を状態値で固定した。
所有ROM／FONTを使う通常`MLOAD`→`A=USR($1000)`では、BASICの`POKE`で画面上・中・下に
非ゼロ文字を置き、ESC終了の最終`RTS`直前に3領域の退避値と復元値が一致することを確認した。
別profileでBASICに復帰した後の診断呼び出しも通過した。合成13件、所有ROM／FONT 3件は
ローカルで成功した。これは実機での動作証拠ではなく、作品ReleaseやPages公開もまだ行っていない。
新規Macクローンでsource commit `8905c77411d74e008086ed72c995f648139945ef`から
両作品を再buildし、SIDE CATCHの合成2件・所有ROM／FONT 1件、RELIC DIVEの合成13件・
所有ROM／FONT 3件を再実行した。clean source由来の候補ZIPはそれぞれ
`6a741173cd5534e0f1e82c0d0e07d9561e74d0f306dacb677dfcbdf5bc8846c6`、
`8d806acb332ab6dc8afac35aeec48711ddcc53940dd3ec7cf3633ca64f0589b2`で、
`games/catalog.json`に固定した。ZIP内の`release_ready=true`は候補packageの検証結果であり、
作品の公開許可や公開監査合格を意味しない。

## 2026-09-25追記: 7作品の固定版

所有ROM/FONTを与えた通常MLOAD/USRと全宣言profileを、cleanなソースcommit
`25c50409af8e8f4909c9dbb9bb64cdb71bb3c4ae`から7作品それぞれで再実行し、
`release_ready=true`のZIPを生成した。カタログcommit `50b9586b4a2399bb1309cf61ffaccaf52bee0cec`
はそのソースcommitの子で、両者を保持したままprivate `main`へマージした。
`make check`は257件合格、`release_audit.py --strict`は候補311ファイル・履歴598 text blob・
固定ZIP7件を調べ、`blocks=[]`、`publication_gates=[]`だった。既存履歴の非noreply
author metadataはwarningで、新しいcommitは確認済みnoreplyを使用した。

7本のWebMは[動画レビュー](MEDIA_REVIEW.md)で固定ハッシュ・実行receipt・場面を照合した。
ZIPにはCJR・必要なMIT/BSD全文・notice・検証reportを含み、ROM/FONTファイル本体、
録音、秘密情報は含めない。privateの[Release](https://github.com/zabaglione/jr200-dev/releases/tag/games-2026-09-25)
へ7件を登録し、GitHubのasset digestがローカルのカタログ固定値と一致した。
[PR #48](https://github.com/zabaglione/jr200-dev/pull/48)のCIは成功した。
Webエミュレータには[PR #24](https://github.com/zabaglione/jr200-web-emulator/pull/24)で
7作品のCJR・ライセンス・noticeを取り込んだ。所有ROM/FONTを使うlocalhostのChromeでは
7件ともカタログ経由のMLOAD/USRと開始入力後の画面変化を確認した。
Pagesの正式Emscriptenビルド・公開URL、private Wikiのremote同期、一般公開後の匿名ZIP取得、
物理JR-200はこのローカル・private監査の合格範囲外である。

その後、Webエミュレータのmain `41fe1ecfe36e7d21596d6f677143dee13cab75d9`に対し、
[source-and-codec CI](https://github.com/zabaglione/jr200-web-emulator/actions/runs/36121921425)
と[Pagesのbuild/deploy](https://github.com/zabaglione/jr200-web-emulator/actions/runs/36122124483)が
ともに成功した。公開サイトの`backend.json`は正式Emscriptenを示し、7件のCJRを含む
33配布fileのHTTP取得バイトは`game-assets.json`のSHA-256と一致した。
公開PagesをChromeで開き、所有ROM/FONTのローカル選択から7作品すべてで通常MLOAD/USRと
開始入力後の画面変化を確認した。検査時は外部への予期しないrequestを拒否した。

固定packageとWebリンクが合致する7作品ページ・35媒体をprivate Wikiへ同期し、
remote `master`のcommit `7a1f8fd406ade3d0ff90430a7179db1eff80daff`を確認した。
再生成dry-runのadd/update/deleteはすべて0。開発リポジトリ自体はprivateのままで、
ReleaseとWikiの匿名到達性はpublic化後に確認が必要。物理JR-200の動作も未確認である。

## 2026-09-25追記: public化後の到達性

利用者の明示依頼により`zabaglione/jr200-dev`をpublicに変更した。変更前にremote全24ブランチと
tagを取得し、現行ツリー・Git履歴・固定packageを再監査した。`release_audit.py --strict`は
履歴609 text blob、7 packageで`blocks=[]`、`publication_gates=[]`、`make check`は257件成功。
非noreplyの旧著者metadata 1種類はwarningとして残し、履歴は書き換えていない。

認証なしのHTTPでリポジトリ、Wiki一覧・作品ページ、Releaseページが200となった。
Wikiの22ページ・35媒体は公開raw URLから全57 fileを取得し、同期済みworktreeとbyte一致した。
Releaseの7 ZIPは公開URLから取得し、catalog固定SHA-256と全件一致した。
Webエミュレータの公開Pagesでは、所有ROM/FONTをローカル選択して7作品の通常MLOAD/USRと
開始入力を確認済み。ROM/FONTファイル本体と物理JR-200の動作は公開・検証対象外である。

## 2026-09-26追記: 公開ZIPのfresh clone再現とスナップショット差異

所有ROM/FONTをローカル指定し、公開ZIP内の`source.commit`からMacでfresh cloneを作成した。
初回6作品の固定commit `25c50409af8e8f4909c9dbb9bb64cdb71bb3c4ae`では全profileを再実行し、
各候補ZIPのSHA-256が公開Releaseと完全一致した。BRICK PULSE 0.1.1の固定commit
`42a0f00010036c247d130766b5fb8747acb20238`でも全17 profile（所有ROM/FONT 5件を含む）と
`release_ready=true`まで再現したが、ZIP全体のSHA-256は一致しなかった。

BRICK PULSEのZIP同士を全memberで比較すると、CJR・検証report・README・ライセンス等のbyteは一致し、
差異は`RELEASE.json`の`source.snapshot_sha256`と、それを記載する`SHA256SUMS`だけだった。
旧生成器がGit無視対象の`tests/__pycache__/*.pyc`までソース・スナップショット計算に含めたことが原因で、
当時のローカルbytecode 2件のhashを加えると公開値と一致した。`.pyc`本体は公開ZIPへ含まれていない。
以後の生成器ではGit追跡済みと無視されない新規fileだけを計算対象にし、無視対象のbytecodeが
ハッシュへ影響しない回帰試験を追加した。公開済みZIP・CJR・カタログの固定hashは変更も上書きもせず、
過去版のスナップショット値と新方式の値は区別する。これは実機JR-200の検証ではない。
