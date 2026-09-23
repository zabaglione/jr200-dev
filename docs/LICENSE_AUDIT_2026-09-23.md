# ライセンス・配布境界の確認（2026-09-23）

## 確認結果

| 対象 | 確認した表示と根拠 | 現在の配布判断 |
| --- | --- | --- |
| jr200-dev共通コード・SDK、SIDE CATCH | root [`LICENSE`](../LICENSE) はBSD-3-Clause。SIDE CATCHの固定候補ZIPにも同一全文を収録 | 候補版。公開Releaseではない |
| RELIC DIVE固有コード・自作PCG | JR-100版の固定revision `9a3921c4371d84c55fc468879dbed2f00fe42960` の[`LICENSE`](https://github.com/zabaglione/jr100dev/blob/9a3921c4371d84c55fc468879dbed2f00fe42960/games/relic_dive/LICENSE) と移植先[`LICENSE`](../games/relic-dive/LICENSE) のSHA-256はともに`057589caa530c3b20e5b988e8cfa6445ac3a8f0c8474584326afce89550ec070`。MIT著作権表示と[出典・変換記録](../games/relic-dive/UPSTREAM.md)を保持 | 開発版。公開Releaseではない |
| RELIC DIVEに組み込むSDK | [`THIRD_PARTY_NOTICES.md`](../games/relic-dive/THIRD_PARTY_NOTICES.md)に`jr200.inc`と`sound.inc`を記載。ローカル候補ZIPにMIT全文、BSD-3-Clause全文、noticeを収録し、BSD全文はroot `LICENSE`と同じSHA-256 `6ea139690174f1e10416b8423dd798f5253b451de678e98681be12559d5cc4c4` | MITだけの単独成果物とは表示しない |
| jrasm | 固定commit `45d0ba18aed74bf09465db5dde3933618ae0b314` のroot treeにライセンス全文を確認できず、[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)では`NOASSERTION`。外部ツールとして実行するだけ | ソース・バイナリ・上流sampleを再配布しない |
| JR-200 Web Emulator | [配布物の第三者表記](https://zabaglione.github.io/jr200-web-emulator/THIRD_PARTY_NOTICES.md)に、FIND VJR-200、MAME MC6800、Emscripten 6.0.9、libc++abi 6.0.9を個別記載。BSD-3-Clause、FIND原文、Emscripten MIT/UIUC、libc++abi Apache-2.0 WITH LLVM-exceptionの全文は公開PagesでHTTP 200を確認 | エミュレータとゲームのライセンスを混同しない |
| ROM・メーカーFONT・商用テープ・利用者録音 | 両リポジトリの配布対象外。Pages側でも利用者のローカル選択だけ | Wiki・CJR・Pagesへ同梱しない |

エミュレータの[SPDX SBOM](https://zabaglione.github.io/jr200-web-emulator/SBOM.spdx.json)では、Playwrightとその依存はCI用途として区別している。`make test` の`license_guard`とPagesの各ライセンスURLのHTTP 200を確認した。この確認は対象ファイルと現在の配布境界に限り、あらゆる上流著作物や法的権利関係の保証ではない。

## 公開ゲート

`python3 tools/release_audit.py --strict` は、現在のtree・未追跡ファイル145件、履歴text blob 18件、SIDE CATCH候補ZIPを走査した。高確度のsecret候補は報告しなかった。初回監査では通常のGit commit identityがnoreplyではなくblockだったが、リポジトリ内だけの設定を確認済みnoreplyへ変更した後の再監査では`blocks=[]`になった。固定runner Release資産がなく、SIDE CATCHはdirty tree由来のcandidateで`release_ready=false`のため、`publication_ready=false`のままである。RELIC DIVEも開発版であり、このauditの固定公開package対象には登録していない。

このため、非公開Wikiには配布可能な作品ページと作品IDの実行リンクを掲載しない。Webエミュレータの`?game=<id>`は、公開済みCJRを同一Pagesの固定カタログへ登録し、SHA-256とROM/FONTを使うブラウザ動作を確認した作品にだけ使う。現在の公開カタログは空である。

Wikiの初回ページ作成では、GitHubのweb操作で記録されたcommitの著者が、履歴で確認済みのGitHub noreplyであることを確認した。その後、メインリポジトリのrepository-local設定もnoreplyに変更した。global設定は変更していない。
