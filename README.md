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

## 署名とアクセシビリティ権限

macOS はアクセシビリティ権限をアプリの署名に紐づけて保存します。署名が証明書ベースなら再ビルドしても権限は引き継がれますが、アドホック署名（`CODE_SIGN_IDENTITY = "-"`）ではビルドごとに署名が変わり、システム設定では許可済みのままなのに動かない状態になります。

このプロジェクトは `Apple Development` 証明書で署名する設定（`CODE_SIGN_STYLE = Automatic`、`DEVELOPMENT_TEAM` 指定）になっています。自分の環境でビルドする場合は、Xcode > Settings > Accounts に Apple ID を追加し（無料の Personal Team で可）、`Tatami.xcodeproj` の `DEVELOPMENT_TEAM` を自分のチーム ID に書き換えてください。証明書を用意しない場合は `CODE_SIGN_IDENTITY = "-"` に戻してアドホック署名でビルドできます。

### 権限が効かなくなったら

ショートカットを押してもビープ音が鳴るだけ、あるいはメニューに「アクセシビリティ権限が必要です…」が出続ける場合は、古い署名に紐づいた権限エントリが残っています。次のコマンドでエントリを消し、tatami を起動し直して許可し直してください。

```sh
tccutil reset Accessibility dev.hidekingerz.tatami
```

システム設定 > プライバシーとセキュリティ > アクセシビリティ で tatami を削除（−）して追加し直しても同じです。

### 署名時に「unable to build chain to self-signed root」が出たら

Apple の中間証明書（WWDR G3）がキーチェーンにありません。[Apple PKI](https://www.apple.com/certificateauthority/) から `AppleWWDRCAG3.cer` を取得してログインキーチェーンに追加してください。

```sh
curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security import AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
security find-identity -v -p codesigning   # 1 valid identities found になれば OK
```

## ライセンス

MIT
