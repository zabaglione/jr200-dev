# jrasmの導入と固定

このプロジェクトはJR-200用アセンブラとして外部の
[ypsitau/jrasm](https://github.com/ypsitau/jrasm)を使用します。
jrasmのソース、実行ファイル、上流sampleは本リポジトリへ複製しません。

## 採用版

`toolchain.lock.json` が正本です。現在は上流`master`の次を固定しています。

- source revision: `45d0ba18aed74bf09465db5dde3933618ae0b314`
- jrasm banner version: `1.0.2`
- upstream repository: `https://github.com/ypsitau/jrasm.git`

上流にはリポジトリ全体へ適用されるライセンスファイルやGitHubのライセンス指定がありません。
したがってライセンスは`NOASSERTION`と記録し、このプロジェクトからソースやバイナリを再配布しません。
利用者は上流の条件を自身で確認したうえで外部ツールとして用意してください。

## Mac／Linuxでのビルド

必要なものはGit、CMake 3.16以降、C++コンパイラです。clone先は本リポジトリの外にします。

```sh
git clone https://github.com/ypsitau/jrasm.git /absolute/path/to/jrasm
git -C /absolute/path/to/jrasm checkout --detach 45d0ba18aed74bf09465db5dde3933618ae0b314
cd /absolute/path/to/jr200-dev
python3 tools/build_jrasm.py --source /absolute/path/to/jrasm
```

build helperはcheckoutのHEADが固定commitか検査し、`toolchain.lock.json`のplatform別設定で
CMakeを実行します。上流ソースは変更しません。

Ubuntu 24.04／GCC 13では上流ソースをそのままbuildすると標準ヘッダー不足で失敗し、
ヘッダーだけを補って最適化するとnull objectへのmember callに由来するSIGSEGVを確認しました。
Linux設定は`cstring`と`strings.h`を強制includeし、
`-fno-delete-null-pointer-checks`で固定版の未定義動作に対する最適化を抑止します。
これは上流不具合を修正したものではなく、この固定commitを利用するための既知の互換設定です。

macOSとLinuxの実行ファイルは通常`build/src/jrasm/jrasm`です。システム領域へのinstallは不要です。
パスを明示し、開発キット側から検査します。

```sh
export JRASM="/absolute/path/to/jrasm/build/src/jrasm/jrasm"
cd /absolute/path/to/jr200-dev
python3 tools/jrasm_tool.py verify-fixture
```

一度だけ別の実行ファイルを使う場合は`--jrasm`が`JRASM`と`PATH`より優先されます。
空白を含むパスは引用符で囲んでください。

```sh
python3 tools/jrasm_tool.py --jrasm "/path with spaces/jrasm" verify-fixture
```

`doctor`は版だけを検査し、`verify-fixture`はそれに加えて自作fixtureをCJRへ変換して
サイズとSHA-256を照合します。fixtureは最小命令、macro、include、MML、CJR出力を対象とします。
bannerが同じでも固定commitから作られた実行ファイルだとは証明できないため、導入時のcheckout確認は別途必要です。

## 確認済み範囲

2026-09-22にApple Silicon Macで固定commitをソースからビルドし、fixtureを確認しました。

| 項目 | 観測結果 |
| --- | --- |
| OS / architecture | macOS 26.6.2 / arm64 |
| compiler | Apple clang 21.0.0 |
| CMake | 4.4.3 |
| jrasm banner | `JR-200 Assembler 1.0.2 Copyright (C) 2018 ypsitau` |
| fixture CJR | 61 bytes |
| fixture SHA-256 | `7a6b2699a2412e7d1d1983d9293b0725e56b51a7dc923204a6171c5b5ea30601` |

同日、Docker上のUbuntu 24.04 / arm64、GCC 13.3.0、CMake 3.28.3でも、
lock済みLinux設定により同じ61 bytesとSHA-256を確認しました。
2026-09-23には別のfresh cloneをmacOS arm64で作り、固定jrasmのfixtureと8 targetの
CJR buildを再確認しました。[GitHub ActionsのUbuntu x64実行](https://github.com/zabaglione/jr200-dev/actions/runs/35818266477)
でも固定jrasmのbuild／fixtureと全8 targetのbuild・構造試験が成功しています。

これはCJR生成の合成試験です。エミュレータ起動、実ROMでのLOAD、実機動作は確認していません。
GitHub Actionsでは再buildが必要なtarget job内で同じ固定commitとfixtureを検査します。
上記remote workflowの成功はエミュレータ／実ROM／実機による動作確認ではありません。
