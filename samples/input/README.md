# Direct key input sample

`$C801` の現在のkey-data latchをtimeout付きでpollし、小文字 `a` を検出するとstatusを1にします。
SDKはBASICのkeyboard bufferを提供せず、IRQ maskやacknowledgeも変更しません。
ジョイスティックの3 byte走査は行わないため、`samples/joystick`と`sdk/joystick.inc`を使用してください。

```sh
JRASM=/absolute/path/to/jrasm make build
RUNNER_BUNDLE=/absolute/path/to/emulator/bundle make run
```

固定runnerのreplayで入力経路を確認します。物理keyboardの電気的・timing確認ではありません。
