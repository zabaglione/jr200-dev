# Three-voice chord sample

`sdk/audio.inc`で音源F・D・Cの3系統を同時に鳴らすサンプルです。Cメジャーの3声
（F: C5-E5-G5-C6、D: E4-G4、C: C3）を繰り返し、100 frame目にC系統の効果音を割り込ませて、
効果音の間だけC声部が止まり、終わると戻ることを示します。200 frameで停止してBASICへ戻ります。

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

固定runnerは、3声が鳴っている途中でPCMのpeakが21000以上（1系統の振幅7000の3倍）であることと、
100 frame目のドライバー状態が`tests/audio_model.py`の予測と一致することを検査します。
音程はエミュレータの分周式に基づく値で、物理JR-200での音程・音量は未確認です。
