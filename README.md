# tatami

Snap macOS windows into place with keyboard shortcuts.

キーボードショートカットで最前面ウィンドウを決まった区画へ移動・リサイズするメニューバー常駐アプリです。

## 動作環境

- macOS 26 以降
- アクセシビリティ権限（初回起動時に案内が出ます）

## ショートカット

修飾キーはすべて ⌃⌥（Control + Option）です。設定画面から変更できます。

| キー | 動作 |
|---|---|
| ⌃⌥b | 左半分 → 左 1/3 → 左 2/3 →（ループ） |
| ⌃⌥f | 右半分 → 右 1/3 → 右 2/3 →（ループ） |
| ⌃⌥p | 上半分 |
| ⌃⌥n | 下半分 |
| ⌃⌥m | 最大化 |
| ⌃⌥c | 中央 1/3 |

## ビルド

Xcode 26 以降が必要です。

```sh
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' build
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test
```

Xcode で `Tatami.xcodeproj` を開いて Run しても動きます。

## ライセンス

MIT
