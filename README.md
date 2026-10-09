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

ビルドしたアプリは Xcode の DerivedData 配下（`~/Library/Developer/Xcode/DerivedData/Tatami-*/Build/Products/Debug/Tatami.app`）にできます。
`/Applications` にコピーして起動すると、アクセシビリティ権限の登録先のパスが固定されます。

## 再ビルド後に動かなくなったら

このプロジェクトはアドホック署名（`CODE_SIGN_IDENTITY = "-"`）でビルドするため、再ビルドすると署名が変わり、macOS がそれまでのアクセシビリティ権限を認めなくなることがあります。
システム設定では tatami が許可済みのままなのに、ショートカットを押してもビープ音が鳴るだけ、あるいはメニューに「アクセシビリティ権限が必要です…」が出る場合はこれが原因です。

- システム設定 > プライバシーとセキュリティ > アクセシビリティ から tatami を削除（−）し、追加し直してください。
- 毎回の再登録を避けたい場合は、Xcode で `DEVELOPMENT_TEAM` を設定して自分の開発チームで署名すると、署名が安定します。

## ライセンス

MIT
