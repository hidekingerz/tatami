# tatami MVP 設計書

作成日: 2026-10-10
対象: hidekingerz/tatami — "Snap macOS windows into place with keyboard shortcuts"

## 1. 目的と成功条件

キーボードショートカットで最前面ウィンドウを決まった区画へ移動・リサイズする macOS 常駐ツール。
ウルトラワイドディスプレイでの利用を想定し、半分・最大化に加えて横 1/3・2/3 の区画を持つ。

MVP の成功条件:

- 下記 8 つのショートカットが、任意のアプリの最前面ウィンドウに対して動作する。
- 左右のショートカットは押すごとに「半分 → 1/3 → 2/3」をループする。
- Accessibility 権限が未許可のとき、ユーザーをシステム設定へ誘導できる。
- 設定画面で 8 つのショートカットを変更でき、再起動後も保持される。
- 純粋ロジック（レイアウト計算、座標変換、ループ判定、エンジン）が単体テストで検証されている。

## 2. 要件

### 2.1 ショートカットと動作

修飾キーは ⌃⌥（Control + Option）。

| キー | コマンド | 動作 |
|---|---|---|
| ⌃⌥b | cycleLeft | 左半分 → 左 1/3 → 左 2/3 → 左半分 …（ループ） |
| ⌃⌥f | cycleRight | 右半分 → 右 1/3 → 右 2/3 → 右半分 …（ループ） |
| ⌃⌥p | topHalf | 上半分 |
| ⌃⌥n | bottomHalf | 下半分 |
| ⌃⌥m | maximize | 最大化（visibleFrame いっぱい） |
| ⌃⌥z | leftThird | 左 1/3 |
| ⌃⌥x | centerThird | 中央 1/3 |
| ⌃⌥c | rightThird | 右 1/3 |

区画（`SnapAction`）は 10 種: leftHalf, rightHalf, topHalf, bottomHalf, maximize,
leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds。

### 2.2 画面の基準

- ウィンドウの中心点を含むディスプレイの `NSScreen.visibleFrame`（メニューバーと Dock を除いた領域）を基準にする。
- 中心点がどの画面にも含まれない場合は `NSScreen.main` を使う。

### 2.3 プラットフォームと配布

- 最低 macOS 26。Swift 6 言語モード（strict concurrency）。
- メニューバー常駐、Dock 非表示（`LSUIElement = YES`）。
- App Sandbox OFF（Accessibility API は Sandbox 下で動作しない）。Hardened Runtime ON（将来の notarization 用）。
- 配布は将来 Homebrew cask を想定。MVP では配布パッケージングは行わない。
- Bundle ID: `dev.hidekingerz.tatami`。

### 2.4 スコープ外（MVP では作らない）

- 四隅の区画、縦 1/3、カスタム区画。
- ログイン時に起動、アップデート確認、複数ディスプレイ間のウィンドウ移動。
- 他アプリとのショートカット衝突の検出（OS が情報を公開しないため不可能。対処はユーザーがキーを変更すること）。

## 3. アーキテクチャ

### 3.1 構成要素と依存方向

依存は上から下へ。下の層は上の層を知らない。

```
TatamiApp (SwiftUI App)
 ├─ MenuBarExtra ─ メニュー: 権限状態 / 設定を開く / 終了
 ├─ Settings シーン ─ SettingsView (KeyboardShortcuts.Recorder × 6)
 └─ ShortcutRegistrar ─ KeyboardShortcuts.onKeyDown → SnapEngine.perform(command)
       │
       ▼
 SnapEngine (@MainActor)   コマンドを受けて 1 回のスナップを実行する司令塔
   ├─ CycleResolver        純粋ロジック: コマンド + CycleMemory + 現在枠 → 次の SnapAction と新しい CycleMemory
   ├─ LayoutCalculator     純粋関数: SnapAction + 画面枠 → 目標枠
   ├─ CoordinateConverter  純粋関数: NSScreen 座標 ⇄ AX 座標
   ├─ ScreenLocator        ウィンドウ枠(NS 座標) → 対象画面の visibleFrame
   └─ WindowService (protocol)
        ├─ AccessibilityWindowService  AXUIElement 実装（本番）
        └─ FakeWindowService           テスト用
 PermissionGate            AXIsProcessTrusted の確認とシステム設定への誘導
```

### 3.2 主要な型

```swift
enum SnapAction: CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
}

enum SnapCommand: CaseIterable {
    case cycleLeft, cycleRight, topHalf, bottomHalf, maximize, leftThird, centerThird, rightThird

    /// ループ系は複数要素、単発系は 1 要素の系列を返す。
    var sequence: [SnapAction]
    // cycleLeft  → [.leftHalf,  .leftThird,  .leftTwoThirds]
    // cycleRight → [.rightHalf, .rightThird, .rightTwoThirds]
    // topHalf    → [.topHalf] など
}

struct WindowHandle: Hashable { /* AXUIElement をラップ。Hashable は CFEqual/CFHash に委譲 */ }

protocol WindowService {
    /// 最前面アプリのフォーカスウィンドウ。取れなければ throw。
    func focusedWindow() throws -> WindowHandle
    /// AX 座標（左上原点）の枠。
    func frame(of window: WindowHandle) throws -> CGRect
    /// AX 座標で枠を設定。size → position → size の順で適用する。
    func setFrame(_ frame: CGRect, of window: WindowHandle) throws
}

struct CycleMemory: Equatable {
    let window: WindowHandle
    let action: SnapAction
    let appliedFrame: CGRect   // AX 座標。適用後に読み直した実枠
}
```

### 3.3 1 回のスナップの流れ

1. ショートカット押下 → `SnapEngine.perform(_ command: SnapCommand)`。
2. `PermissionGate.isTrusted` が false なら、プロンプト付きで再要求して終了（スナップしない）。
3. `WindowService.focusedWindow()` でウィンドウを取得し、`frame(of:)` で現在枠（AX 座標）を得る。
4. `CoordinateConverter.toScreen` で NS 座標へ変換し、`ScreenLocator` が中心点を含む画面の `visibleFrame` を返す。
5. `CycleResolver.resolve(command:memory:window:currentFrame:)` が次の `SnapAction` を決める。
6. `LayoutCalculator.frame(for:in:)` が `visibleFrame` を分割して目標枠（NS 座標）を返す。
7. `CoordinateConverter.toAccessibility` で AX 座標へ戻し、`WindowService.setFrame` で適用。
8. 適用後に `frame(of:)` で実枠を読み直し、`CycleMemory` を更新して保持する。
   最小サイズ制約で実枠が `visibleFrame` の右端・下端からはみ出した場合は、大きさはそのままに位置だけを内側へ戻す `setFrame` をもう一度行い、読み直した枠を記憶に使う。

### 3.4 CycleResolver（ハイブリッド判定）

記憶は `CycleMemory` を最大 1 件だけ保持する。

- コマンドの系列が 1 要素なら、その要素を返す。
- 系列が複数の場合、以下をすべて満たせば「記憶の action の次」（末尾なら先頭に戻る）を返す。
  1. 記憶が存在し、`memory.window == window`。
  2. `memory.action` がこのコマンドの系列に含まれる。
  3. `currentFrame` と `memory.appliedFrame` の原点（x, y）と大きさ（width, height）の差がそれぞれ 2pt 以内。辺そのものの比較ではないので、maxX / maxY は最大 4pt ずれうる。
- 満たさなければ系列の先頭を返す。
- 非ループ系の操作後も記憶は更新する（直後にループ系を押せば先頭から始まる）。
- 記憶はプロセス内メモリのみ。永続化しない。

### 3.5 座標変換

- AX 座標は左上原点、NSScreen 座標は左下原点。どちらもプライマリ画面を基準にする。
- プライマリ画面は `NSScreen.screens[0]`（原点 (0,0) を持つ画面）。`NSScreen.main` ではない。
- 変換式: `axY = primaryHeight - (nsY + height)`、x と size は共通。逆変換も同じ式。
- `CoordinateConverter` は `primaryHeight: CGFloat` を引数に取る純粋関数とし、NSScreen に依存しない。

### 3.6 LayoutCalculator

- 入力は `visibleFrame`（NS 座標）、出力は NS 座標の目標枠。
- 1/3 分割では `floor(width / 3)` を基本幅とし、端数は右端の区画に寄せて隙間を作らない。
  - leftThird: x = minX, width = w
  - centerThird: x = minX + w, width = w
  - rightThird: x = minX + 2w, width = width - 2w
  - leftTwoThirds: x = minX, width = 2w
  - rightTwoThirds: x = minX + w, width = width - w
- 半分は `floor(width / 2)` / `floor(height / 2)` を基本とし、右・上の区画に端数を寄せる。
  - NS 座標は下が原点なので、topHalf は y = minY + floor(h/2)、height = height - floor(h/2)。
- maximize は `visibleFrame` そのもの。

### 3.7 AccessibilityWindowService

- `NSWorkspace.shared.frontmostApplication` → `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute`。
- 枠の読み取りは `kAXPositionAttribute` / `kAXSizeAttribute` を `AXValue` 経由で取得。
- 枠の設定は size → position → size の順。先に size を設定して、画面端で position がクランプされるのを避ける。
- AX のエラーコードは `WindowServiceError` にマップして throw する。

## 4. UI

### 4.1 メニューバー

`MenuBarExtra`（`.menu` スタイル）。項目:

- 権限が未許可のときだけ「アクセシビリティ権限が必要です…」を表示。クリックで
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` を開く。
- 「設定…」: Settings シーンを開く。
- 「tatami を終了」。

### 4.2 設定画面

`Settings` シーン上の `SettingsView`。`KeyboardShortcuts.Recorder` を 6 行並べたフォーム。
各行はコマンド名（左半分/1/3/2/3 ループ、右半分/1/3/2/3 ループ、上半分、下半分、最大化、左 1/3、中央 1/3、右 1/3）とレコーダー。
デフォルト値は `KeyboardShortcuts.Name` の `default:` で与える。保存先は KeyboardShortcuts が管理する UserDefaults。

## 5. 権限とエラー処理

- 起動時: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` を呼ぶ。未許可ならメニューに誘導項目を表示。
- ショートカット押下時: 権限を毎回判定する。未許可ならプロンプト付きで再要求し、スナップはしない。
- 権限の判定は `AXIsProcessTrusted()` が true、または実際の AX 呼び出し（Dock の役割属性の取得）が成功したとき許可済みとみなす。対象を Dock にするのは、常に動いていて前面アプリに左右されないため。システム全体要素の「フォーカス中アプリ」は Chromium 系アプリが前面だと断続的に値なしを返し、自プロセスへの問い合わせは権限がなくても通るので、どちらも判定に使えない。`AXIsProcessTrusted()` はプロセス内で結果をキャッシュし、システム設定で許可した瞬間に TCC が返す古い「拒否」をそのまま保持してしまうことがある（実機で確認済み）ため、実呼び出しで補う。
- 未許可の間は 1 秒おきに判定を読み直し、許可を検知したらメニューの誘導項目を消す（`TrustPoller`）。TCC の分散通知 `com.apple.accessibility.api` も購読するが、通知時点の判定は信頼しない。
- AX 呼び出しはメインスレッドで同期的に行うため、アプリ要素とウィンドウ要素の両方に `AXUIElementSetMessagingTimeout` で 1 秒の上限を設け、応答しない最前面アプリに tatami が止められないようにする。
- ウィンドウが取れない（フォーカスウィンドウなし、デスクトップ等）、AX エラー（リサイズ不可のウィンドウ等）: `NSSound.beep()` のみ。ダイアログは出さない。
- サイズ制約で目標枠にならない: エラー扱いしない。適用後の実枠を `CycleMemory` に保存するので、次回の判定は実枠と比較され、ループは進む。
- ログ: `os.Logger`、サブシステム `dev.hidekingerz.tatami`。ユーザー向け表示はしない。

## 6. ショートカットの衝突について

- KeyboardShortcuts は Carbon `RegisterEventHotKey` を使う。同じ組み合わせを複数アプリが登録した場合、イベントは一方にしか届かない。
- 実機での確認結果（2026-10-10、macOS 26）。⌃⌥b を登録する最小の CLI プログラム（`docs/superpowers/plans/2026-10-10-tatami-mvp.md` Task 9 Step 9）と tatami を組み合わせて 3 通り試した。
  - tatami を先に起動し、後から CLI を登録: tatami が受け取り、CLI には届かない。
  - CLI を先に登録し、後から tatami を起動: tatami が受け取り、CLI には届かない。
  - CLI 単独: CLI が受け取る（CLI 自体は受信できる）。
  - つまり登録順では決まらない。この組み合わせでは常に tatami（バンドルされた GUI アプリ）が優先された。どちらが優先されるかの規則は macOS 側の実装に依存し、公開仕様はない。GUI アプリ同士の競合は未検証。
- 利用者への指針: 他のアプリでショートカットが効かなくなった、または tatami が効かない場合は、どちらかの設定画面でキーを変える。tatami 側は設定画面から変更できる。
- システム標準ショートカットは Carbon ホットキーより優先される。⌃⌥ + p/n/b/f/m/c はシステム標準では未使用。
- `KeyboardShortcuts.Recorder` はシステム予約キーと自アプリのメニュー項目との衝突を録音時に警告する。他社アプリとの衝突は検出不可。対処は設定画面でのキー変更。

## 7. テスト

Swift Testing を使う。AX API 本体と SwiftUI はテスト対象外（手動確認）。

- `LayoutCalculatorTests`: 10 区画 × 代表的な画面サイズ（偶数・奇数・3 で割り切れない幅）。区画同士に隙間と重なりがなく、visibleFrame の範囲内に収まること。
- `CoordinateConverterTests`: 往復変換が元に戻ること。プライマリ画面上、プライマリの右側、左側（負の x）、上側の画面を含む。
- `CycleResolverTests`: 記憶なしで先頭、系列の進行、末尾から先頭へのループ、別ウィンドウでリセット、手で動かした後（枠不一致）のリセット、許容値 2pt 以内の誤差は一致扱い、非ループ系コマンド後にループ系を押すと先頭。
- `SnapEngineTests`: `FakeWindowService` と固定の画面枠で、コマンド → `setFrame` に渡る枠の検証。権限未許可時に `setFrame` が呼ばれないこと。ウィンドウ取得失敗時に beep 相当のフックが呼ばれること。

## 8. プロジェクト構成

```
Tatami.xcodeproj
Tatami/
  App/        AppModel.swift, MenuBarView.swift, SettingsView.swift, ShortcutRegistrar.swift,
              TatamiApp.swift
  Engine/     CoordinateConverter.swift, CycleResolver.swift, LayoutCalculator.swift,
              ScreenLocator.swift, SnapEngine.swift
  Model/      CycleMemory.swift, SnapAction.swift, SnapCommand.swift, WindowHandle.swift
  System/     AccessibilityWindowService.swift, NSScreenProvider.swift, PermissionChecking.swift,
              PermissionGate.swift, ScreenProviding.swift, WindowService.swift
  Resources/  Assets.xcassets
TatamiTests/
  CoordinateConverterTests.swift, CycleResolverTests.swift, LayoutCalculatorTests.swift,
  ScreenLocatorTests.swift, SnapCommandTests.swift, SnapEngineTests.swift
  Fakes/      FakePermission.swift, FakeScreenProvider.swift, FakeWindowService.swift
```

- Info.plist ファイルは置かない。`GENERATE_INFOPLIST_FILE = YES` と `INFOPLIST_KEY_LSUIElement = YES` のビルド設定で生成する（Dock に出さないメニューバー常駐アプリにする）。
- ビルド構成は Xcode プロジェクト（`.xcodeproj` をコミット）。pbxproj は手書きで作成し、Xcode で開いて保存すれば正規化される。
- 依存: sindresorhus/KeyboardShortcuts を Xcode の Package Dependencies で追加。`Package.resolved` をコミット。
- `SnapEngine`、`CycleMemory` の保持、`PermissionGate` は `@MainActor`。
- ビルドとテストは `xcodebuild -scheme Tatami -destination 'platform=macOS'` で実行できること。
