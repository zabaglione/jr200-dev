# Wiki生成とローカル同期

## 現在の公開境界

`tools/wiki/generate.py` は、固定済みの作品packageを検査してWiki用fileを生成します。
このtool自身はclone、commit、push、Release作成、repositoryのvisibility変更を行いません。
7作品は `verified`／公開指定の固定版となり、private Releaseにclean-source ZIPを登録しました。
Pagesの配信・所有ROM/FONTによる実起動を確認後、private Wikiに7作品ページと媒体を同期しました。
開発リポジトリのpublic化と、Release/Wikiへの匿名アクセスは未実施です。

2026-09-23、利用者のWiki作成依頼に従い、privateのままGitHubで初回`Home`を作成し、
`jr200-dev.wiki.git`をcloneできることを確認しました。初回Wiki commitはGitHub noreplyです。
生成した`Home`、`Games`、`Play`、`Licenses`の4ページをprivate Wikiの`master`へpushし、
[Playページ](https://github.com/zabaglione/jr200-dev/wiki/Play)の表示と操作順をブラウザで確認しました。
この2026-09-23の時点では、ゲームRelease配信、repositoryのpublic化、PagesへのゲームCJR追加は行っていませんでした。

## ページ構成

| page | 内容 |
| --- | --- |
| `Home` | 入口、6ジャンルと公開件数、公開／候補版／開発中を分けた作品カード |
| `_Sidebar` | 全ページ共通のナビゲーション |
| `All-Games` | タイトル順の一覧 |
| `Genre-Puzzle`ほか6ページ | `tools/wiki/genres.json`のジャンル説明と作品カード。公開作品がなければ「公開作品準備中」 |
| `Game-<slug>` | パンくず、状態・版・ライセンス、遊ぶ、画面（全scene）、動画、READMEの各節、版と検証、ソース |
| `Controls` | 共通の注意と、各READMEの「操作」節をそのまま並べた作品別の表 |
| `Play` | ROM／FONTとCJRのセット、`MLOAD`／`USR`、うまく動かないとき |
| `Presentation` | 全作品の画面と動画 |
| `Quality-Review` | 検証方法と作品別の検証区分（ROMなし合成、所有ROM/FONT、物理JR-200） |
| `Licenses` | 共通SDK、作品別ライセンス、移植元、エミュレータ |
| `Games` | 旧URLの維持。全作品とジャンル別ページへ案内 |

JR100 Wikiの構成を参考にしていますが、文章は複製せず、作品の正本（`game.json`、README、
`media/gallery.json`）から生成します。作品ページ名は現行の`Game-<slug>`のままです。

## 入力と検査

正本は `games/catalog.json`、各作品の `game.json`、README、catalogで指定した代表画像、
`media/gallery.json`、`tools/wiki/genres.json` です。
候補版を含める場合でも、generatorは次をすべて検査します。

- catalogと作品metadataのID、version、status、publication、license
- 固定ZIPのSHA-256、安全なmember path、内部 `SHA256SUMS`
- CJRのSHA-256と、合成／local-ROMのprofile別実行report
- 代表画像のPNG SHA-256、320×224 RGBA画素hash、対応profileのframebuffer hash
- 公開指定時の `verified`、固定Release URL、clean sourceから作られたpackage

- `gallery.json`の各画像のPNG SHA-256、320×224の画素hash、対応profileの期待framebuffer hash、
  動画のSHA-256とWebM形式。ROM撮影の場合はCJRと、ゲームが設置するASCII自作字形sourceの
  hashも固定します（画面上の全字形の由来を示すものではありません）。
  schema 3では`media/receipts/`に保存した実行reportと、CJR・現在の期待値・画面hash・通常カセット経路も照合します。
  古い版の画像が残っていれば停止します
- ジャンルが`genres.json`にあること。catalog外の作品は`draft`／`not-published`に限ります
- 生成した全ページのリンク：Wiki内ページ、`media/`、リポジトリ内file（`blob/main`・`tree/main`の
  対象が実在すること）、許可したURL（Webエミュレータ、固定revisionのjr100dev、固定Release）。
  それ以外のURL、JR-100のプレイURL（`pyjr100emu`）、PRGへの言及、altのない画像、先頭がH1でない
  ページを拒否します

下書き、package欠落、hash不一致、不正path、構文上不正なHTTPS URLを拒否します。
generator自体は外部URLのHTTP到達性を検査しません。初回7作品については、
公開Pagesのcatalog・CJRをHTTP取得してhashを照合し、所有ROM/FONTで起動した後に
private Wikiの「遊ぶ」リンクを有効化しました。

## 開発中の作品のpreview

移植中の作品（catalog外の`draft`）は、ローカルpreviewだけに出せます。packageやROMは不要です。

```sh
make wiki-preview-dev   # build/wiki-preview-dev/
```

各作品にはREADMEの「目的と勝敗」「操作」「起動」「検証の範囲」「ライセンス」節と、
`gallery.json`（3場面以上）が必要です。開発中の作品には「遊ぶ」リンクを出さず、
`sync`に`--include-development`を渡すと停止します。

## 候補版preview

先に作品packageを生成してから実行します。

```sh
JRASM=/absolute/path/to/jrasm make game-package PROJECT=games/side-catch
make wiki-check
make wiki-preview
```

出力はGit対象外の `build/wiki-preview/` です。候補版banner、手動CJR読込み案内、
エミュレータと実機の検証境界を含みます。候補版にはPagesへの一般リンクだけを置き、
ゲームIDのセット用リンクは公開CJRの存在と動作を確認するまで生成しません。
公開版の`play_url`には、手動起動用の`?game=<id>`に加え、起動支援用の
`?game=<id>&launch=1`を許可します。後者を選んだ作品ページだけ
「遊ぶ（起動支援）」と表示します。固定済み7作品のページには、この起動支援リンクを掲載済みです。

画面例を再取得する場合は、既存PNGを退避したうえで所有ROM/FONTの通常MLOAD/USR profileを
優先します。ゲームが設置する自作字形sourceを指定して一致を検査します。
画面は切り抜き・塗りつぶしをせずに記録し、メーカーFONTの字形もそのまま映る場合があります。

```sh
python3 tools/emulator_runner.py run \
  --project games/side-catch \
  --bundle /absolute/path/to/fixed/emulator/bundle \
  --profile local-rom-title \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin \
  --self-font sdk/font_data.inc \
  --screenshot games/side-catch/build/new-title.png
```

runnerは既存fileを上書きせず、PNG画素hashと検証済みframebuffer hashが一致した後だけ
出力先へ移動します。ROM cassette profileの撮影では、ゲームが設置した自作字形の一致を
検査します。ROM/FONTファイルはGitやpackageへ追加しません。

## 作品の画面と動画

各作品の`media/gallery.json`が紹介画像と動画の正本です。画像はタイトル（`title`）、プレイ中（`play`）、
最初の目標（`goal`）の3場面以上で、どれも`tests/expectations.json`の対応profileの
framebuffer hashと一致しなければなりません（`tests/test_gallery.py`）。JR-100の画像や描き起こしの
絵で代用しません。

動画は同じprofileのreplayを固定bundleで1/30秒ごとに記録した映像と、同じ実行のPCMから作ります。
後から演出や音を足さず、短縮する場合は倍速を`gallery.json`とcaptionに書きます。
ROM/FONTあり撮影では、自作字形が有効になり、起動前のBASIC画面が消えたcycleから切り出します。

```sh
export FFMPEG=/absolute/path/to/ffmpeg   # libvpx-vp9とlibopusを含む外部ツール
python3 tools/capture_video.py --project games/relic-dive \
  --profile local-rom-goal --bundle /absolute/path/to/fixed/bundle \
  --rom /absolute/local/path/to/JR200.rom \
  --font /absolute/local/path/to/FONT.bin \
  --self-font sdk/font_data.inc --start-cycle 163500000 \
  --output games/relic-dive/build/new-goal.webm
```

出力には映像フレームとPCMのSHA-256、秒数、倍速が付きます。WebMのbyte列はffmpegの版で変わり得るため、
再現の照合はフレームとPCMのhashで行います。

## Wiki worktreeへの同期

`WIKI_DIR` は、originが正規の `jr200-dev.wiki.git` であるcleanなGit worktree rootに限ります。
`wiki-sync-*`は検証済み・公開指定の作品だけを同期し、候補版は`wiki-preview`に限定します。
初回作成された`Home.md`だけは生成内容とbyte一致する場合に限って管理下へ取り込めます。
まずdry-runで差分を確認します。

```sh
make wiki-sync-dry-run WIKI_DIR=/absolute/path/to/jr200-dev.wiki
make wiki-sync-apply WIKI_DIR=/absolute/path/to/jr200-dev.wiki
git -C /absolute/path/to/jr200-dev.wiki diff --stat
```

`apply` はlocal worktreeだけを変更します。管理manifestに記録された上記のページと
`media/<slug>*.png`／`media/<slug>*.webm` だけを更新・削除し、手書きpageを保持します。
同名の未管理fileや、前回生成後に手編集されたfileには上書き・削除せず停止します。
2回目のdry-runでadd／update／deleteが0ならcommitやpushは不要です。

remote push用jobは未実装です。今回の初回7作品は、Pagesの到達性を確認してから
別Git worktreeで生成差分だけを手動同期しました。将来の自動化では
PR検査とは別workflow、最小書込み権限、直列実行を追加します。公開指定pageの生成には
`--expected-commit "$GITHUB_SHA"` を必須とし、clean packageのsource commitが公開対象のmain commitの祖先であることを照合します。これにより、固定packageを作り直さずに説明文だけを更新できます。

## Webエミュレータのカタログへのエクスポート

`tools/web_export.py`は、`games/catalog.json`で`verified`かつ公開指定の1作品1版だけを、
`jr200-web-emulator`のsiteへ取り込むためのstaging directoryにします。エミュレータのリポジトリを
変更・pushせず、Release作成も行いません。

`--approve`は入力した作品ID・版の取り違えを防ぐ選択文字列であり、利用者による一般公開の
承認を証明するものではありません。公開先への配置には、作品・版・配信先の別の明示指定と
公開前監査が必要です。`--expected-commit`を必須として固定packageのclean source祖先を検査します。

現在の7作品は検証済みの固定版なので公開用exportの対象です。未公開候補を
ローカルで確認するときだけ`--preview-candidate`を追加します。これはmanifestに
`mode=preview`と記録し、公開側の取込み対象にはできません。非semverの開発版は
ローカルWebカタログ上で`0.0.0`を使い、元の版をタイトルとmanifestに残します。

```sh
python3 tools/web_export.py \
  --game side-catch --version 0.1.2 --approve side-catch@0.1.2 \
  --site-catalog /absolute/path/to/jr200-web-emulator/web/game-catalog.json \
  --site /absolute/path/to/current/site --packages /absolute/path/to/fixed/packages \
  --expected-commit "$(git rev-parse HEAD)" --title-marker 'SIDE CATCH'
# 差分を確認してから
python3 tools/web_export.py ...同じ引数... --output /absolute/path/to/empty/staging
```

所有ROM/FONTで実際のタイトル画面を確認し、固定版CJRの起動支援を有効にする場合は
`--title-marker 'SIDE CATCH'`のようにその画面に表示される6〜32文字の英大文字・数字・空白を指定します。
catalogの`titleMarker`と`EXPORT.json`の`title_marker`に同じ値を記録し、Web側の取り込み時にも
一致を検査します。省略した版は`?game=id&launch=1`でもマウントのみです。

| 検査 | 内容 |
| --- | --- |
| 承認 | `--approve <id>@<version>`が選択と一致しない場合は拒否 |
| 状態 | `status=verified`、`wiki.publish=true`、clean sourceのpackage、公開commitの祖先 |
| package | `load_package`の全検査（hash、実行report、ライセンス、SHA256SUMS） |
| CJR | package内CJRのSHA-256、1 MiB以下、entryがload block内、`A=USR($XXXX)`と一致 |
| カタログ | エミュレータの`validateGameCatalog`と同じ規則。重複ID、不正path、他作品の変更を拒否 |
| 不変性 | `--site`に同じ版のfileがあり内容が異なれば停止。同一なら`unchanged` |

出力は`games/<id>/<version>/`のCJR、`LICENSE.txt`、MIT作品では`THIRD_PARTY_NOTICES.md`と
`LICENSES/BSD-3-Clause.txt`、由来を記した`EXPORT.json`、更新後の`game-catalog.json`、
`export-manifest.json`です。manifestには全ファイルのsize・SHA-256、CJRのentry／実行条件、
必要runner／SDK契約、作品ライセンス、元packageのhashも固定します。Webカタログは1 IDにつき
推奨版1件だけを持ち、`?game=<id>`はその版を開きます。
過去版のfileは同じpathに残して上書きしません。版指定リンクは現行の`game-launch.mjs`にないため、
必要になった時点でエミュレータ側のschema拡張として別途合意します。

初回7作品については、エミュレータ側の`scripts/stage_web.py`のallow-list、SBOM、noticeを
更新して固定CJRを配信済みです。Pages上のcatalogとCJRの到達性・SHA-256および通常起動を
確認してから、private Wikiの「遊ぶ」を有効にしました。次版でも同じ順序を守ります。
