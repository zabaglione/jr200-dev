# Media

`gallery.json`の3枚と動画は、利用者が所有するJR-200 ROM/FONTをローカルで読み込み、
通常の`MLOAD`と`A=USR($1000)`を経た固定エミュレータの出力です。ROMやFONTのファイルと
その内容は本リポジトリ、package、動画に含めません。

ゲーム起動時にSDKの自作字形（`sdk/font_data.inc`）を文字RAMに設置します。
playerは緑、targetは黄で、異なる字形と色を使います。
撮影処理は文字RAMの自作字形と全768画面セルの文字code／属性を各フレームで照合し、
メーカー字形が画面に使われる場合は出力を拒否します。動画はBASIC起動・ロード中を飛ばし、
ゲーム画面の0.9秒だけを等速で記録しました。音声は同じエミュレータ実行のPCMです。

画像・動画のSHA-256、元CJR、replay profile、撮影開始cycle、自作字形sourceのSHA-256は
`gallery.json`に固定しています。WebMのbyte列はffmpegにより変わる場合があるため、
再現性はframeとPCMのhashで照合します。物理JR-200での表示・音声は未確認です。
