# Wiki生成とローカル同期

## 現在の公開境界

`tools/wiki/generate.py` は、固定済みの作品packageを検査してWiki用fileを生成します。
このtool自身はclone、commit、push、Release作成、repositoryのvisibility変更を行いません。
現在の `SIDE CATCH 0.1.0` は `candidate`／`not-published` であり、公開対象ではありません。

2026-09-23、利用者のWiki作成依頼に従い、privateのままGitHubで初回`Home`を作成し、
`jr200-dev.wiki.git`をcloneできることを確認しました。初回Wiki commitはGitHub noreplyです。
生成した`Home`、`Games`、`Play`、`Licenses`の4ページをprivate Wikiの`master`へpushし、
[Playページ](https://github.com/zabaglione/jr200-dev/wiki/Play)の表示と操作順をブラウザで確認しました。
ゲームRelease配信、repositoryのpublic化、PagesへのゲームCJR追加は行っていません。

## 入力と検査

正本は `games/catalog.json`、各作品の `game.json`、README、`media/screenshot.png` です。
候補版を含める場合でも、generatorは次をすべて検査します。

- catalogと作品metadataのID、version、status、publication、license
- 固定ZIPのSHA-256、安全なmember path、内部 `SHA256SUMS`
- CJRのSHA-256と、合成／local-ROMのprofile別実行report
- screenshotのPNG SHA-256、320×224 RGBA画素hash、合成profileのframebuffer hash
- 公開指定時の `verified`、固定Release URL、clean sourceから作られたpackage

下書き、package欠落、hash不一致、不正path、構文上不正なHTTPS URLを拒否します。
外部URLのHTTP到達性検査は、公開URLがまだ存在しない現在の段階では行いません。

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

画面例を再取得する場合は、既存PNGを退避したうえでROMなしprofileだけを使用します。

```sh
python3 tools/emulator_runner.py run \
  --project games/side-catch \
  --bundle /absolute/path/to/fixed/emulator/bundle \
  --profile synthetic-screenshot \
  --screenshot games/side-catch/media/screenshot.png
```

runnerは既存fileを上書きせず、PNG画素hashと検証済みframebuffer hashが一致した後だけ
出力先へ移動します。ROM cassette profileからの画像出力は拒否します。

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

`apply` はlocal worktreeだけを変更します。管理manifestに記録された `Home.md`、`Games.md`、
`Play.md`、`Licenses.md`、`Game-<slug>.md`、`media/<slug>.png` だけを更新・削除し、手書きpageを保持します。
同名の未管理fileや、前回生成後に手編集されたfileには上書き・削除せず停止します。
2回目のdry-runでadd／update／deleteが0ならcommitやpushは不要です。

remote push用jobとゲームの初回公開は未実装です。公開packageと明示承認が揃った時点で、
PR検査とは別workflow、最小書込み権限、直列実行を追加します。公開指定pageの生成には
`--expected-commit "$GITHUB_SHA"` を必須とし、clean packageのsource commitが公開対象のmain commitの祖先であることを照合します。これにより、固定packageを作り直さずに説明文だけを更新できます。
