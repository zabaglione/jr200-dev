# Media

所有ROM/FONTで通常`MLOAD`→`A=USR($1000)`を実行し、固定エミュレータから取得した
320×224の無加工の画面と動画です。撮影時はゲームが`$D100-$D2FF`へ
設置するSDK自作字形との一致を検査しました。メーカーFONTの字形が画面に映る場合も、
削除や置換はしません。
ROM/FONT本体、ローカルpath、起動前のBASIC画面と音は公開素材へ含めません。
`gallery.json`はCJR・字形源・replay profile・PNG/framebuffer・動画フレーム/PCMのhashを固定します。

| file | profile | PNG SHA-256 | framebuffer SHA-256 |
| --- | --- | --- | --- |
| `title.png` | `local-rom-title` | `36759249943e1e595d67bdd056760f555d13e8053159be07a9fb04f72e423445` | `edca690437f01b6ef1008b21636da555aed0def489bd7a2e6b688bd985041e9a` |
| `gameplay.png` | `local-rom-play` | `75949665e4d8b06363dc19c051529eaca8922acf223e2d9b5c25af34c9cf30c0` | `f3987b74b8ca7a1c52ca1fba8f00d55afe6c7b6d7e645be93b9487e7cc3aba21` |
| `combat.png` | `local-rom-goal` | `49f67eaba69a9fe7a39d9f1983a1943e0126b970af127d33c028f74e89d2362b` | `1c320916764ba9f1e0fa19818be4aa8b638d3fbf27e65eb7bfff1b08c1280c2a` |

`goal.webm`は`local-rom-goal`のreplayを固定エミュレータで記録した映像と実ゲームPCM
（15.6秒、等速）です。最初の敵1体を倒すまでで、全階クリアの映像ではありません。

これは固定エミュレータの証拠です。物理JR-200表示、実機入力、実機音声は未確認です。
