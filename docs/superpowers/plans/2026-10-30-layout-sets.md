# レイアウトセット 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 複数アプリのウィンドウを「どの窓を、どの区画に、どのデスクトップで」の行の並び（レイアウトセット）として保存し、ピッカーまたはショートカット一発でまとめて配置する。別デスクトップに散った窓は Rectangle Pro 方式（タイトルバーを掴んだまま ⌃N）で連れ戻す。

**Architecture:** Model に `LayoutSet` / `LayoutRow` を足し、App 層の `LayoutSetStore` が UserDefaults に JSON で保存する。Engine 層は純粋な `LayoutSetPlanner`（行と窓の照合）、`SnapEngine` から切り出した `WindowPlacer`（区画の適用）、それらを順に実行する `LayoutSetRunner`、取り込み用の `RegionMatcher` / `LayoutCapture`。System 層に AX の窓列挙 `AccessibilityWindowEnumerator`、CGEvent でデスクトップを越える `CGEventSpaceMover`、Mission Control と Dock の設定を読む `MissionControlShortcuts` / `DockPreferences`。UI はピッカー（NSPanel + SwiftUI）、設定の「セット」タブ、結果 HUD。

**Tech Stack:** Swift 6 言語モード、SwiftUI / AppKit（NSPanel、NSHostingView）、ApplicationServices（AXUIElement、CGEvent、CGWindowList）、sindresorhus/KeyboardShortcuts 2.4.0、Swift Testing、Xcode 26 / xcodebuild。

**Spec:** `docs/superpowers/specs/2026-10-30-layout-sets-design.md`

## Global Constraints

- 最低 macOS 26、Swift 6 言語モード（strict concurrency）。既存のビルド設定は変えない。
- 非公開 API（SkyLight / CGS 系）は使わない。デスクトップ間移動は「タイトルバーの `leftMouseDown` → Mission Control の『デスクトップ N へ切り替え』キー → `leftMouseUp`」のみ。
- 保存キー: セットは `layoutSets.v1`（JSON Data）、壊れた JSON の退避先は `layoutSets.v1.corrupt`。ピッカーのキー名は `layoutSets.picker`、セットのキー名は `layoutSet.<uuid>`。いずれも既定キーなし。
- `SnapAction` はケース名で保存する（`String` rawValue）。既存ケースの改名禁止。
- `LayoutRow.desktop` は 1...10。範囲外はデコード時に nil へ丸める。`action` と `desktop` がともに nil の行は「何もしない行」として保存を許し、適用では無視する。
- Mission Control のショートカット ID はデスクトップ 1〜10 が 118〜127。Dock の `mru-spaces` は未設定なら true（自動並べ替えオン）。
- 自動並べ替えがオンのときはデスクトップ移動を飛ばし、区画の配置だけ行う。`defaults write com.apple.dock mru-spaces -bool false` + `killall Dock` は設定画面の確認後にしか実行しない。
- ピッカーや設定画面など tatami 自身が前面（`NSApp.isActive`）のとき、既存 27 コマンドは beep して何もしない。`SnapEngine` の外から見える振る舞いはそれ以外変えない。
- 座標は `WindowService` の境界で AX 座標（左上原点）、`LayoutCalculator` / `ScreenLocator` は NS 座標（左下原点）。
- 新規ファイルはフォルダに置くだけで対象に入る（`PBXFileSystemSynchronizedRootGroup`）。`project.pbxproj` は触らない。
- ビルドとテストは `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS'` で通ること。
- ソースと設計書のコメントは日本語。識別子は英語。テスト名も日本語（既存に合わせる）。
- 各 Task の最後にコミットする。コミットメッセージ末尾に `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` と `Claude-Session: https://claude.ai/code/session_01F24vRzYsuyCh65qeW55Avs` を付ける。
- 作業ブランチは `feature/layout-sets`（作成済み、設計書をコミット済み）。

## Review Focus

1. **同じアプリの窓が 2 枚あり、行も 2 つあるセット**: 2 行が別々の窓に当たり、同じ窓を 2 回置かないこと（Task 5 `LayoutSetPlannerTests` の「同じアプリの 2 行は別の窓に当たる」で検証）。
2. **壊れた保存データ（手で編集した JSON、将来の形式）**: 空で起動し、元データを退避キーに残し、再保存で上書きしないこと（Task 4 `LayoutSetStoreTests` の「壊れた JSON は退避して空で起動」で検証）。
3. **適用中にデスクトップ切替キーが効かない（ショートカットがオフ、押下中の修飾キーが混ざる）**: その行だけ失敗にし、次の行へ進み、HUD に理由が出ること（Task 7 `LayoutSetRunnerTests` の「spaceMover が投げたら failed に入り次の行へ進む」と `summary` の文言テストで検証。修飾キーの解放待ちは Task 2 の実機確認）。
4. **「いまの配置を保存」で区画に当てはまらない自由サイズの窓**: `action = nil` の行として残り、適用では触らないこと（Task 8 `RegionMatcherTests` の「自由サイズは nil」、Task 5 の「何もしない行は照合されない」で検証）。
5. **tatami 自身が前面のときの単発コマンド**: ピッカーや設定画面を区画に置かず beep すること（Task 9 の実機確認項目。ハンドラ側の判定なので単体テストは書かない）。

---

## ファイル構成

```
Tatami/
  Model/SnapAction.swift               Task 3（String rawValue、Codable、title）
  Model/LayoutSet.swift                Task 3（新規: LayoutSet, LayoutRow）
  System/MissionControlShortcuts.swift Task 1（新規: KeyCombo, 読み取りと純粋な解析）
  System/DockPreferences.swift         Task 1（新規: mru-spaces の読み書き）
  System/WindowEnumerating.swift       Task 2（新規: WindowInfo, プロトコル）
  System/AccessibilityWindowEnumerator.swift  Task 2（新規: AX + CGWindowList 実装）
  System/WindowService.swift           Task 2（unminimize / raise を追加）
  System/AccessibilityWindowService.swift     Task 2（同上の実装）
  System/SpaceMover.swift              Task 2（新規: SpaceMoving, CGEventSpaceMover）
  App/DebugMenu.swift                  Task 2（新規: フラグ付きのデバッグ項目）
  App/MenuBarView.swift                Task 2（デバッグ項目）, Task 9（レイアウトセット…とセット一覧）
  App/LayoutSetStore.swift             Task 4（新規）
  Engine/LayoutSetPlanner.swift        Task 5（新規: 純粋な照合）
  Engine/WindowPlacer.swift            Task 6（新規: SnapEngine から切り出し）
  Engine/SnapEngine.swift              Task 6（WindowPlacer を使う、clearMemory）
  Engine/LayoutSetRunner.swift         Task 7（新規: 実行と結果、summary）
  Engine/RegionMatcher.swift           Task 8（新規: IoU で区画へ丸める）
  Engine/LayoutCapture.swift           Task 8（新規: いまの配置 → 行）
  App/ShortcutRegistrar.swift          Task 9（picker / セットごとの登録、isActive ガード）
  App/AppModel.swift                   Task 9（Store / Runner / Picker / HUD を保持）
  App/ResultHUD.swift                  Task 9（新規: 結果 HUD）
  App/RegionGlyph.swift                Task 10（複数区画を 1 枚に）
  App/PickerPanel.swift                Task 10（新規: NSPanel とキー処理）
  App/PickerView.swift                 Task 10（新規: SwiftUI）
  App/LayoutSetsTab.swift              Task 11（新規: セット一覧、行エディタ、取り込みシート、警告）
  App/SettingsView.swift               Task 11（タブ追加、幅 640）
  App/TatamiApp.swift                  Task 11（model を渡す）
TatamiTests/
  Fakes/FakeWindowEnumerator.swift     Task 2（新規）
  Fakes/FakeWindowService.swift        Task 2（unminimize / raise）
  Fakes/FakeSpaceMover.swift           Task 7（新規）
  Fakes/FakeDockPreferences.swift      Task 7（新規）
  MissionControlShortcutsTests.swift   Task 1（新規）
  DockPreferencesTests.swift           Task 1（新規）
  LayoutSetTests.swift                 Task 3（新規）
  LayoutSetStoreTests.swift            Task 4（新規）
  LayoutSetPlannerTests.swift          Task 5（新規）
  WindowPlacerTests.swift              Task 6（新規）
  SnapEngineTests.swift                Task 6（変更なしで通ること）
  LayoutSetRunnerTests.swift           Task 7（新規）
  RegionMatcherTests.swift             Task 8（新規）
  LayoutCaptureTests.swift             Task 8（新規）
README.md                              Task 12
docs/superpowers/specs/2026-10-30-layout-sets-design.md   Task 2（スパイク結果で §5 の待ち時間と掴む点を更新）
```

テストの実行コマンド（以下「テスト実行」と書いたらこれ）:

```bash
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test -only-testing:TatamiTests/<SuiteName> 2>&1 | grep -E "Test run with|Suite .* (passed|failed)|✘|error:" | tail -40
```

全テストは `-only-testing:` を外す。Swift Testing の結果は `✔ Test run with N tests` の行で見る（XCTest 側の「Executed 0 tests」は無視してよい）。

Task 2 のスパイクは利用者が手元で動かして結果を報告する。Task 3〜8 はスパイクと独立なので、報告を待つ間に進めてよい。Task 9 以降はスパイク結果（§5 の待ち時間と掴む点）を反映してから進める。

---

### Task 1: Mission Control と Dock の設定を読む

**Files:**
- Create: `Tatami/System/MissionControlShortcuts.swift`
- Create: `Tatami/System/DockPreferences.swift`
- Test: `TatamiTests/MissionControlShortcutsTests.swift`, `TatamiTests/DockPreferencesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct KeyCombo: Equatable, Sendable {
      let keyCode: CGKeyCode
      let modifiers: CGEventFlags
  }

  protocol MissionControlShortcutReading: Sendable {
      /// 「デスクトップ desktop へ切り替え」が有効ならそのキー。無効・未設定・範囲外なら nil。
      func switchToDesktopShortcut(_ desktop: Int) -> KeyCombo?
  }

  struct MissionControlShortcuts: MissionControlShortcutReading {
      /// com.apple.symbolichotkeys の AppleSymbolicHotKeys を読む。キャッシュしない。
      func switchToDesktopShortcut(_ desktop: Int) -> KeyCombo?
      /// 純粋な解析。hotKeys は AppleSymbolicHotKeys 辞書（キーは "118" のような文字列）。
      static func shortcut(forDesktop desktop: Int, in hotKeys: [String: Any]) -> KeyCombo?
      static func hotKeyID(forDesktop desktop: Int) -> Int   // 117 + desktop
  }

  protocol DockPreferencesReading: Sendable {
      var rearrangesSpacesAutomatically: Bool { get }
      func disableAutomaticRearrangement() throws
  }

  struct DockPreferences: DockPreferencesReading {
      static func rearrangesSpacesAutomatically(from value: Any?) -> Bool   // nil → true
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/MissionControlShortcutsTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tatami

struct MissionControlShortcutsTests {
    /// システム設定が保存する形。parameters は [文字コード, キーコード, 修飾キー]。65535 は文字なし。
    static func entry(enabled: Bool, keyCode: Int, modifiers: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, keyCode, modifiers], "type": "standard"]]
    }

    @Test func デスクトップ1は118でctrl1になる() {
        let hotKeys = ["118": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000)]
        let combo = MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys)
        #expect(combo == KeyCombo(keyCode: 18, modifiers: .maskControl))
    }

    @Test func デスクトップ2から10は119から127() {
        #expect(MissionControlShortcuts.hotKeyID(forDesktop: 2) == 119)
        #expect(MissionControlShortcuts.hotKeyID(forDesktop: 10) == 127)
        let hotKeys = ["127": Self.entry(enabled: true, keyCode: 29, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 10, in: hotKeys)?.keyCode == 29)
    }

    @Test func 無効ならnil() {
        let hotKeys = ["118": Self.entry(enabled: false, keyCode: 18, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys) == nil)
    }

    @Test func 項目がなければnil() {
        #expect(MissionControlShortcuts.shortcut(forDesktop: 3, in: [:]) == nil)
    }

    @Test func 範囲外のデスクトップはnil() {
        let hotKeys = ["117": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 0, in: hotKeys) == nil)
        #expect(MissionControlShortcuts.shortcut(forDesktop: 11, in: hotKeys) == nil)
    }

    @Test func 修飾キーはcontrol_option_shift_commandだけ拾う() {
        // control + option + shift + command + 無関係なビット
        let hotKeys = ["118": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000 | 0x80000 | 0x20000 | 0x100000 | 0x1)]
        let combo = MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys)
        #expect(combo?.modifiers == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }
}
```

`TatamiTests/DockPreferencesTests.swift`:

```swift
import Testing
@testable import Tatami

struct DockPreferencesTests {
    @Test func 値がなければ自動並べ替えはオン() {
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: nil))
    }

    @Test func falseが保存されていればオフ() {
        #expect(!DockPreferences.rearrangesSpacesAutomatically(from: false))
        #expect(!DockPreferences.rearrangesSpacesAutomatically(from: 0))
    }

    @Test func trueが保存されていればオン() {
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: true))
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: 1))
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`MissionControlShortcutsTests`、`DockPreferencesTests`）。
Expected: コンパイルエラー（型が未定義）。

- [ ] **Step 3: 実装する**

`Tatami/System/MissionControlShortcuts.swift`: Interfaces のとおり。

- `switchToDesktopShortcut` は `CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)` を `[String: Any]` にして `shortcut(forDesktop:in:)` へ渡す。
- `shortcut(forDesktop:in:)`: desktop が 1...10 でなければ nil。`hotKeys["\(hotKeyID)"]` の `enabled`（Bool または NSNumber）が真で、`value.parameters` が 3 要素の数値配列なら、`keyCode = CGKeyCode(parameters[1])`、`modifiers = CGEventFlags(rawValue: UInt64(parameters[2])).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])`。
  システム設定の修飾キービットは CGEventFlags と同じ値（control 0x40000、option 0x80000、shift 0x20000、command 0x100000）なので変換は不要。

`Tatami/System/DockPreferences.swift`: Interfaces のとおり。

- `rearrangesSpacesAutomatically` は `CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString)` を `rearrangesSpacesAutomatically(from:)` に通す。`from:` は `Bool` / `NSNumber` を受け、nil なら true。
- `disableAutomaticRearrangement()` は `CFPreferencesSetAppValue("mru-spaces", false, "com.apple.dock")` → `CFPreferencesAppSynchronize` → `Process` で `/usr/bin/killall Dock` を実行し `waitUntilExit`。終了コードが 0 でなければ `DockPreferencesError.restartFailed(status:)` を投げる。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`MissionControlShortcutsTests`、`DockPreferencesTests`）。
Expected: 9 件 PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/System/MissionControlShortcuts.swift Tatami/System/DockPreferences.swift TatamiTests/MissionControlShortcutsTests.swift TatamiTests/DockPreferencesTests.swift
git commit -m "feat: read Mission Control desktop shortcuts and Dock mru-spaces"
```

---

### Task 2: 窓の列挙・raise・デスクトップ移動（System 層）とスパイク

OS に依存する部分をまとめて作り、フラグ付きのデバッグメニューから利用者が手元で確かめる。
結果で設計書 §5 の待ち時間と掴む点を確定する。

**Files:**
- Create: `Tatami/System/WindowEnumerating.swift`
- Create: `Tatami/System/AccessibilityWindowEnumerator.swift`
- Modify: `Tatami/System/WindowService.swift`（プロトコルに 2 メソッド追加）
- Modify: `Tatami/System/AccessibilityWindowService.swift`
- Create: `Tatami/System/SpaceMover.swift`
- Create: `Tatami/App/DebugMenu.swift`
- Modify: `Tatami/App/MenuBarView.swift`
- Create: `TatamiTests/Fakes/FakeWindowEnumerator.swift`
- Modify: `TatamiTests/Fakes/FakeWindowService.swift`
- Test: `TatamiTests/SpaceMoverTests.swift`（掴む点の純粋関数だけ）

**Interfaces:**
- Consumes: Task 1 の `MissionControlShortcutReading`, `KeyCombo`。
- Produces:
  ```swift
  struct WindowInfo: Hashable, Sendable {
      let handle: WindowHandle
      let pid: pid_t
      let bundleIdentifier: String
      let appName: String          // NSRunningApplication.localizedName ?? bundleIdentifier
      let title: String            // kAXTitleAttribute。なければ ""
      let frameAX: CGRect
      let isMinimized: Bool
  }

  @MainActor
  protocol WindowEnumerating {
      /// 起動中の通常アプリ（activationPolicy == .regular）の窓を AX が返す順で。全デスクトップ、最小化を含む。アプリが起動していなければ []。
      func windows(ofBundleIdentifier id: String) -> [WindowInfo]
      /// いまのデスクトップで画面に見えているレイヤー 0 の窓を前面から順に。tatami 自身は除く。
      func onScreenWindows() -> [WindowInfo]
  }

  struct AccessibilityWindowEnumerator: WindowEnumerating { init() }

  // WindowService に追加
  func unminimize(_ window: WindowHandle) throws       // kAXMinimizedAttribute = false
  func raise(_ window: WindowHandle) throws            // アプリを activate し、kAXMainAttribute = true、kAXRaiseAction

  enum SpaceMoveError: Error, Sendable {
      case shortcutDisabled(desktop: Int)
      case eventPostFailed
  }

  struct SpaceMoverTiming: Sendable {
      var modifierReleaseTimeout: Duration = .seconds(1)
      var afterMouseDown: Duration = .milliseconds(80)
      var afterKey: Duration = .milliseconds(400)
      var afterMouseUp: Duration = .milliseconds(100)
  }

  @MainActor
  protocol SpaceMoving {
      /// window は表示中のデスクトップにあり前面に出ていること。
      func move(_ window: WindowHandle, frameAX: CGRect, toDesktop desktop: Int) async throws
  }

  @MainActor
  final class CGEventSpaceMover: SpaceMoving {
      init(shortcuts: any MissionControlShortcutReading, timing: SpaceMoverTiming = SpaceMoverTiming())
      /// 掴む点。x = minX + 80、y = minY + 10。幅 200 未満なら x = midX。
      static func grabPoint(for frameAX: CGRect) -> CGPoint
  }

  // テスト用
  @MainActor final class FakeWindowEnumerator: WindowEnumerating {
      var windowsByBundle: [String: [WindowInfo]] = [:]
      var onScreen: [WindowInfo] = []
  }
  // FakeWindowService に追加
  private(set) var unminimizeCalls: [WindowHandle]
  private(set) var raiseCalls: [WindowHandle]
  var raiseError: WindowServiceError?
  ```

- [ ] **Step 1: 掴む点のテストを書く**

`TatamiTests/SpaceMoverTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct SpaceMoverTests {
    @Test func 掴む点は信号機の右のタイトルバー() {
        let frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        #expect(CGEventSpaceMover.grabPoint(for: frame) == CGPoint(x: 180, y: 60))
    }

    @Test func 幅が狭ければ中央を掴む() {
        let frame = CGRect(x: 100, y: 50, width: 150, height: 600)
        #expect(CGEventSpaceMover.grabPoint(for: frame) == CGPoint(x: 175, y: 60))
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`SpaceMoverTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: WindowEnumerating と AX 実装を書く**

`Tatami/System/WindowEnumerating.swift`: `WindowInfo` と `WindowEnumerating`。

`Tatami/System/AccessibilityWindowEnumerator.swift`:

- `windows(ofBundleIdentifier:)`: `NSWorkspace.shared.runningApplications` から `bundleIdentifier` が一致し `activationPolicy == .regular` のものを取り（複数あれば全部）、`AXUIElementCreateApplication(pid)` に `AXUIElementSetMessagingTimeout(_, 1)` を掛けて `kAXWindowsAttribute` を読む。各要素について `kAXTitleAttribute`（String、なければ ""）、`kAXMinimizedAttribute`（Bool、なければ false）、位置と大きさ（既存 `AccessibilityWindowService.frame(of:)` と同じ読み方。読めない要素は捨てる）。
- `onScreenWindows()`: `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` を前面順に走査し、`kCGWindowLayer == 0`、`kCGWindowOwnerPID` が tatami 自身でないものについて、`kCGWindowBounds` を `CGRect` にし、その pid の AX 窓一覧（上と同じ読み方）から `frameAX` が一致（各辺 ±2pt）するものを探して `WindowInfo` にする。一致しなければ捨てる。pid ごとの AX 一覧は 1 回だけ読む。
- `WindowHandle` は `Hashable` だが `WindowInfo` の `Hashable` はそれに委ねてよい。

`Tatami/System/WindowService.swift` と `AccessibilityWindowService.swift`: `unminimize` は `kAXMinimizedAttribute` に `kCFBooleanFalse` を書く。`raise` は `AXUIElementGetPid` で pid を取り `NSRunningApplication(processIdentifier:)?.activate()`、`kAXMainAttribute` に `kCFBooleanTrue`、`AXUIElementPerformAction(kAXRaiseAction)`。AX の失敗は `WindowServiceError.axError` で投げる。

`TatamiTests/Fakes/FakeWindowEnumerator.swift` と `FakeWindowService.swift` の追加は Interfaces のとおり（`raise` は `raiseError` があれば投げ、なければ `raiseCalls` に積む）。

- [ ] **Step 4: SpaceMover を書く**

`Tatami/System/SpaceMover.swift`: Interfaces のとおり。`move` の手順:

1. `shortcuts.switchToDesktopShortcut(desktop)` が nil なら `SpaceMoveError.shortcutDisabled(desktop:)`。
2. 修飾キーが離されるまで待つ: `CGEventSource.flagsState(.combinedSessionState)` に control / option / shift / command が立っている間、20 ms ずつ `Task.sleep`。`modifierReleaseTimeout` を超えたらそのまま進む（ホットキー直後は利用者がまだ ⌃⌥ を押しているため）。
3. `CGEvent(source: nil)?.location` でマウス位置を保存。
4. `grabPoint(for: frameAX)` へ `mouseMoved` → `leftMouseDown` を `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` で作り `post(tap: .cghidEventTap)`。作れなければ `eventPostFailed`。
5. `afterMouseDown` 待つ。
6. `CGEvent(keyboardEventSource:virtualKey:keyDown:)` で keyDown / keyUp を作り、`flags = combo.modifiers` を立てて post。
7. `afterKey` 待つ。
8. `leftMouseUp` を同じ点に post。
9. `CGWarpMouseCursorPosition` で 3 の位置へ戻す。
10. `afterMouseUp` 待つ。

4 以降で例外や `eventPostFailed` になった場合も `leftMouseUp` を必ず post してから投げる（`defer` で押しっぱなしを防ぐ）。待ち時間は `SpaceMoverTiming` にまとめ、スパイクで調整する。

- [ ] **Step 5: デバッグメニューを足す**

`Tatami/App/DebugMenu.swift`: `UserDefaults.standard.bool(forKey: "debugMenu")` が true のときだけ `MenuBarView` に出る `Menu("デバッグ")`。項目:

- 「最前面の窓をデスクトップ N へ」（N = 1...5 のサブメニュー）: 3 秒待ってから（利用者が対象アプリへ切り替える時間）、`AccessibilityWindowService().focusedWindow()` → `frame(of:)` → `CGEventSpaceMover(shortcuts: MissionControlShortcuts()).move(...)`。結果を `Logger(subsystem: "dev.hidekingerz.tatami", category: "Debug")` に `.public` で出す。
- 「最前面アプリの窓一覧をログ」: 3 秒待ってから、最前面アプリの bundle id で `AccessibilityWindowEnumerator().windows(ofBundleIdentifier:)` を呼び、各窓の title / frameAX / isMinimized をログに出す。
- 「最前面の窓を raise（3 秒後）」: 3 秒待ってから、直前に記録した窓（1 つ前の項目で最後にログした窓一覧の先頭）を `raise`。別デスクトップの窓で切り替わるかを見る。
- 「画面に見えている窓をログ」: `onScreenWindows()` を即時にログ。
- 「Mission Control / Dock の設定をログ」: デスクトップ 1〜10 の `switchToDesktopShortcut` と `rearrangesSpacesAutomatically` をログ。

ログは利用者が `log stream --predicate 'subsystem == "dev.hidekingerz.tatami" AND category == "Debug"' --level debug` で見る。

- [ ] **Step 6: ビルドとテストが通ることを確認する**

テスト実行（全テスト）。Expected: 既存 86 件 + Task 1 の 9 件 + `SpaceMoverTests` 2 件がすべて PASS。

- [ ] **Step 7: コミット**

```bash
git add Tatami/System Tatami/App/DebugMenu.swift Tatami/App/MenuBarView.swift TatamiTests/Fakes TatamiTests/SpaceMoverTests.swift
git commit -m "feat: enumerate windows, raise, and move windows across desktops via Mission Control shortcuts (debug menu)"
```

- [ ] **Step 8: スパイクを利用者に依頼し、結果を待つ**

利用者に次の手順を渡す。結果は確認表の形で返してもらう。

手順:

```bash
defaults write dev.hidekingerz.tatami debugMenu -bool YES
# Xcode でビルドして Tatami.app を起動（署名が変わっていればアクセシビリティ権限を取り直す）
log stream --predicate 'subsystem == "dev.hidekingerz.tatami" AND category == "Debug"' --level debug
```

システム設定 → キーボード → キーボードショートカット → Mission Control で「デスクトップ 1〜3 へ切り替え」をオンにしておく。
システム設定 → デスクトップと Dock → Mission Control の「最新の使用状況に基づいて…」は、この確認の間だけオフにする（番号を安定させるため）。

確認表（各行、○ / × と気づいたことを記入）:

| # | 操作 | 期待 | Chrome | WezTerm | LINE | Discord | Teams |
|---|---|---|---|---|---|---|---|
| 1 | デスクトップ 1 でそのアプリを前面にし、メニュー「最前面の窓をデスクトップ 2 へ」→ 3 秒以内にそのアプリをクリック | 窓ごとデスクトップ 2 に移り、利用者もデスクトップ 2 にいる | | | | | |
| 2 | 1 の直後、マウスカーソルが元の位置に戻っている | 戻っている | | | | | |
| 3 | 1 で、掴んだ場所の部品（タブ、ボタン）が反応していない | 何も開かない、タブが切り替わらない | | | | | |
| 4 | デスクトップ 2 にそのアプリの窓を置いたまま、デスクトップ 1 で「最前面アプリの窓一覧をログ」（3 秒以内にそのアプリをクリック） | ログにデスクトップ 2 の窓も出る | | | | | |
| 5 | 4 の続きで「最前面の窓を raise（3 秒後）」→ 3 秒以内に Finder をクリック | デスクトップ 2 へ切り替わり、その窓が前面に出る | | | | | |
| 6 | 「Mission Control / Dock の設定をログ」 | デスクトップ 1〜3 のキーが出る（⌃1 = keyCode 18 など）、4〜10 は nil、mru-spaces の値が設定どおり | | | | | |
| 7 | 1 を、ホットキーのつもりで ⌃⌥ を押したままメニューを選んで試す | 修飾キーを離すまで待ってから動く | | | | | |

結果の反映:

- 1 が × のアプリ: `grabPoint` の x を `minX + 120`、`minY + 6` などに変えて再試行。全滅なら設計書 §8 のとおり利用者に相談する（スペース移動を落とすか）。
- 切替が間に合わない（窓が移らずデスクトップだけ切り替わる）: `afterMouseDown` を 150 ms、`afterKey` を 600 ms に増やして再試行。
- 5 が ×: `raise` を `activate(options: [.activateIgnoringOtherApps])` だけにして再試行。それでも × なら設計書 §2.4 の手順 4 を「アプリをアクティブにする」に書き換える。
- 確定した値を `SpaceMoverTiming` の既定値と `grabPoint` に入れ、設計書 §5 を更新してコミットする:

```bash
git add Tatami/System/SpaceMover.swift docs/superpowers/specs/2026-10-30-layout-sets-design.md
git commit -m "chore: tune space mover timing and grab point from spike results"
```

---

### Task 3: Model（LayoutSet / LayoutRow、SnapAction の保存と表示名）

**Files:**
- Modify: `Tatami/Model/SnapAction.swift`
- Create: `Tatami/Model/LayoutSet.swift`
- Test: `TatamiTests/LayoutSetTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum SnapAction: String, CaseIterable, Codable, Sendable { /* 既存 27 ケース。rawValue はケース名 */ }
  extension SnapAction {
      /// 設定画面とピッカーに出す区画名。単発コマンドの SnapCommand.title と同じ文字列。
      var title: String
  }

  struct LayoutRow: Identifiable, Codable, Hashable, Sendable {
      static let desktopRange = 1...10
      let id: UUID
      var bundleIdentifier: String
      var appName: String
      var titleFilter: String
      var action: SnapAction?
      var desktop: Int?
      init(id: UUID = UUID(), bundleIdentifier: String, appName: String,
           titleFilter: String = "", action: SnapAction? = nil, desktop: Int? = nil)
      /// action も desktop もない「何もしない行」。
      var isNoOp: Bool
  }

  struct LayoutSet: Identifiable, Codable, Hashable, Sendable {
      let id: UUID
      var name: String
      var rows: [LayoutRow]
      init(id: UUID = UUID(), name: String, rows: [LayoutRow] = [])
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/LayoutSetTests.swift`:

```swift
import Foundation
import Testing
@testable import Tatami

struct LayoutSetTests {
    @Test func SnapActionはケース名で保存される() throws {
        let data = try JSONEncoder().encode([SnapAction.leftTwoThirds, .topLeftQuarter])
        #expect(String(data: data, encoding: .utf8) == #"["leftTwoThirds","topLeftQuarter"]"#)
    }

    @Test func 区画名は単発コマンドと同じ() {
        #expect(SnapAction.leftHalf.title == "左半分")
        #expect(SnapAction.leftTwoThirds.title == SnapCommand.leftTwoThirds.title)
        #expect(SnapAction.topLeftQuarter.title == SnapCommand.topLeftQuarter.title)
        #expect(SnapAction.center.title == SnapCommand.center.title)
        for command in SnapCommand.allCases where !command.isCycle {
            #expect(command.sequence[0].title == command.title)
        }
    }

    @Test func セットはJSONで往復する() throws {
        let set = LayoutSet(name: "作業", rows: [
            LayoutRow(bundleIdentifier: "com.github.wez.wezterm", appName: "WezTerm",
                      titleFilter: "herdr", action: .leftTwoThirds, desktop: nil),
            LayoutRow(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome",
                      action: .rightThird, desktop: 3),
        ])
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(LayoutSet.self, from: data)
        #expect(decoded == set)
    }

    @Test func デスクトップの範囲外はnilに丸める() throws {
        let json = #"{"id":"6B7B6B4C-0000-0000-0000-000000000001","bundleIdentifier":"a","appName":"A","titleFilter":"","action":null,"desktop":11}"#
        let row = try JSONDecoder().decode(LayoutRow.self, from: Data(json.utf8))
        #expect(row.desktop == nil)
        let zero = json.replacingOccurrences(of: "\"desktop\":11", with: "\"desktop\":0")
        #expect(try JSONDecoder().decode(LayoutRow.self, from: Data(zero.utf8)).desktop == nil)
    }

    @Test func 何もしない行の判定() {
        #expect(LayoutRow(bundleIdentifier: "a", appName: "A").isNoOp)
        #expect(!LayoutRow(bundleIdentifier: "a", appName: "A", action: .maximize).isNoOp)
        #expect(!LayoutRow(bundleIdentifier: "a", appName: "A", desktop: 2).isNoOp)
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutSetTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`Tatami/Model/SnapAction.swift`: `enum SnapAction: String, CaseIterable, Codable, Sendable` にし、「ケース名で保存するので改名禁止」のコメントを足す。`title` は `SnapCommand.title` の単発コマンドの文字列を区画側へ移し、`SnapCommand.title` は単発なら `sequence[0].title` を返すよう書き換える（ループ系 2 つの文字列だけ `SnapCommand` に残す）。

`Tatami/Model/LayoutSet.swift`: Interfaces のとおり。`LayoutRow` は `init(from:)` を手書きし、`desktop` を読んだあと `desktopRange.contains` でなければ nil にする。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutSetTests`、`SnapCommandTests`）。Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Model TatamiTests/LayoutSetTests.swift
git commit -m "feat: add LayoutSet and LayoutRow models with Codable SnapAction"
```

---

### Task 4: LayoutSetStore（保存）

**Files:**
- Create: `Tatami/App/LayoutSetStore.swift`
- Test: `TatamiTests/LayoutSetStoreTests.swift`

**Interfaces:**
- Consumes: Task 3 の `LayoutSet`, `LayoutRow`。
- Produces:
  ```swift
  @MainActor @Observable
  final class LayoutSetStore {
      static let key = "layoutSets.v1"
      static let corruptKey = "layoutSets.v1.corrupt"
      init(defaults: UserDefaults = .standard)
      private(set) var sets: [LayoutSet]
      var onChange: (([LayoutSet]) -> Void)?
      func set(id: UUID) -> LayoutSet?
      func add(_ set: LayoutSet)
      func update(_ set: LayoutSet)            // id が一致する要素を置き換える。なければ何もしない
      func remove(id: UUID)
      func move(fromOffsets: IndexSet, toOffset: Int)
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/LayoutSetStoreTests.swift`（`CommandSettingsTests` と同じ suite 付き UserDefaults の作り）:

```swift
import Foundation
import Testing
@testable import Tatami

@MainActor
final class LayoutSetStoreTests {
    let suiteName = "dev.hidekingerz.tatamiTests.LayoutSetStore.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    func row(_ app: String) -> LayoutRow {
        LayoutRow(bundleIdentifier: "com.example.\(app)", appName: app, action: .maximize)
    }

    @Test func 何もなければ空() {
        #expect(LayoutSetStore(defaults: defaults).sets.isEmpty)
    }

    @Test func 追加と更新と削除が保存され別インスタンスで読める() {
        let store = LayoutSetStore(defaults: defaults)
        var set = LayoutSet(name: "作業", rows: [row("a")])
        store.add(set)
        set.name = "作業2"
        set.rows.append(row("b"))
        store.update(set)
        store.add(LayoutSet(name: "連絡"))
        #expect(LayoutSetStore(defaults: defaults).sets == store.sets)
        #expect(store.sets.map(\.name) == ["作業2", "連絡"])
        #expect(store.set(id: set.id)?.rows.count == 2)

        store.remove(id: set.id)
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["連絡"])
    }

    @Test func 並び替えが保存される() {
        let store = LayoutSetStore(defaults: defaults)
        store.add(LayoutSet(name: "a"))
        store.add(LayoutSet(name: "b"))
        store.add(LayoutSet(name: "c"))
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["c", "a", "b"])
    }

    @Test func 壊れたJSONは退避して空で起動する() {
        defaults.set(Data("not json".utf8), forKey: LayoutSetStore.key)
        let store = LayoutSetStore(defaults: defaults)
        #expect(store.sets.isEmpty)
        #expect(defaults.data(forKey: LayoutSetStore.corruptKey) == Data("not json".utf8))
        store.add(LayoutSet(name: "new"))
        #expect(defaults.data(forKey: LayoutSetStore.corruptKey) == Data("not json".utf8))
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["new"])
    }

    @Test func 変更のたびにonChangeが呼ばれる() {
        let store = LayoutSetStore(defaults: defaults)
        var counts: [Int] = []
        store.onChange = { counts.append($0.count) }
        let set = LayoutSet(name: "a")
        store.add(set)
        store.update(set)
        store.remove(id: set.id)
        #expect(counts == [1, 1, 0])
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutSetStoreTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`Tatami/App/LayoutSetStore.swift`: Interfaces のとおり。`init` で `defaults.data(forKey: key)` を `JSONDecoder` で読み、失敗したら `corruptKey` に同じ Data を書いて `Logger(subsystem: "dev.hidekingerz.tatami", category: "LayoutSetStore")` にエラーを出し、`sets = []`。変更メソッドはすべて `sets` を書き換えてから `save()`（`JSONEncoder` → `defaults.set(data, forKey: key)`）し、`onChange?(sets)`。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutSetStoreTests`）。Expected: 5 件 PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App/LayoutSetStore.swift TatamiTests/LayoutSetStoreTests.swift
git commit -m "feat: persist layout sets in UserDefaults with corrupt-data fallback"
```

---

### Task 5: LayoutSetPlanner（行と窓の照合）

**Files:**
- Create: `Tatami/Engine/LayoutSetPlanner.swift`
- Test: `TatamiTests/LayoutSetPlannerTests.swift`

**Interfaces:**
- Consumes: Task 2 の `WindowInfo`、Task 3 の `LayoutSet` / `LayoutRow`。
- Produces:
  ```swift
  enum SkipReason: Equatable, Sendable { case appNotRunning, noMatchingWindow }
  struct PlannedStep: Equatable, Sendable { let row: LayoutRow; let window: WindowInfo }
  struct SkippedRow: Equatable, Sendable { let row: LayoutRow; let reason: SkipReason }
  struct LayoutPlan: Equatable, Sendable { let steps: [PlannedStep]; let skipped: [SkippedRow] }

  enum LayoutSetPlanner {
      /// 行の順に照合する。何もしない行は無視。使った窓は次の行の候補から外す。
      static func plan(_ set: LayoutSet, windowsByBundle: [String: [WindowInfo]]) -> LayoutPlan
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/LayoutSetPlannerTests.swift`:

```swift
import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

struct LayoutSetPlannerTests {
    /// テスト用の窓。pid ごとに別の AXUIElement を作って handle を区別する。
    static func window(_ bundle: String, _ title: String, pid: pid_t, minimized: Bool = false) -> WindowInfo {
        WindowInfo(handle: WindowHandle(element: AXUIElementCreateApplication(pid)), pid: pid,
                   bundleIdentifier: bundle, appName: bundle, title: title,
                   frameAX: CGRect(x: 0, y: 0, width: 100, height: 100), isMinimized: minimized)
    }
    static let wez1 = window("wez", "host.local: herdr", pid: 1)
    static let wez2 = window("wez", "host.local: tatami", pid: 2)
    static let chrome = window("chrome", "GitHub", pid: 3)
    static let windows = ["wez": [wez1, wez2], "chrome": [chrome]]

    func row(_ bundle: String, filter: String = "", action: SnapAction? = .maximize, desktop: Int? = nil) -> LayoutRow {
        LayoutRow(bundleIdentifier: bundle, appName: bundle, titleFilter: filter, action: action, desktop: desktop)
    }

    @Test func 絞り込みなしなら先頭の窓() {
        let plan = LayoutSetPlanner.plan(LayoutSet(name: "s", rows: [row("wez")]), windowsByBundle: Self.windows)
        #expect(plan.steps.map(\.window) == [Self.wez1])
        #expect(plan.skipped.isEmpty)
    }

    @Test func 絞り込みは大文字小文字を無視した部分一致() {
        let set = LayoutSet(name: "s", rows: [row("wez", filter: "TATAMI")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.steps.map(\.window) == [Self.wez2])
    }

    @Test func 同じアプリの2行は別の窓に当たる() {
        let set = LayoutSet(name: "s", rows: [row("wez"), row("wez")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.steps.map(\.window) == [Self.wez1, Self.wez2])
    }

    @Test func 3行目は窓が尽きてnoMatchingWindow() {
        let set = LayoutSet(name: "s", rows: [row("wez"), row("wez"), row("wez")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.steps.count == 2)
        #expect(plan.skipped.map(\.reason) == [.noMatchingWindow])
        #expect(plan.skipped[0].row == set.rows[2])
    }

    @Test func 起動していなければappNotRunning() {
        let set = LayoutSet(name: "s", rows: [row("slack"), row("chrome")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.skipped.map(\.reason) == [.appNotRunning])
        #expect(plan.steps.map(\.window) == [Self.chrome])
    }

    @Test func 最小化の窓も候補になる() {
        let minimized = Self.window("chrome", "GitHub", pid: 3, minimized: true)
        let plan = LayoutSetPlanner.plan(LayoutSet(name: "s", rows: [row("chrome")]),
                                         windowsByBundle: ["chrome": [minimized]])
        #expect(plan.steps.map(\.window) == [minimized])
    }

    @Test func 何もしない行は照合されず結果にも出ない() {
        let set = LayoutSet(name: "s", rows: [row("wez", action: nil, desktop: nil), row("wez")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.steps.map(\.window) == [Self.wez1])
        #expect(plan.skipped.isEmpty)
    }

    @Test func 行の順が計画の順() {
        let set = LayoutSet(name: "s", rows: [row("chrome"), row("wez")])
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: Self.windows)
        #expect(plan.steps.map(\.row) == set.rows)
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutSetPlannerTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`Tatami/Engine/LayoutSetPlanner.swift`: Interfaces のとおり。使用済みの窓は `Set<WindowHandle>` で持つ。絞り込みは `window.title.localizedCaseInsensitiveContains(row.titleFilter)`（`titleFilter` が空なら常に一致）。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutSetPlannerTests`）。Expected: 8 件 PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Engine/LayoutSetPlanner.swift TatamiTests/LayoutSetPlannerTests.swift
git commit -m "feat: add LayoutSetPlanner that matches rows to windows"
```

---

### Task 6: WindowPlacer（SnapEngine から区画の適用を切り出す）

**Files:**
- Create: `Tatami/Engine/WindowPlacer.swift`
- Modify: `Tatami/Engine/SnapEngine.swift`
- Test: `TatamiTests/WindowPlacerTests.swift`、既存 `TatamiTests/SnapEngineTests.swift`（変更なし）

**Interfaces:**
- Produces:
  ```swift
  enum PlacementError: Error, Equatable, Sendable { case noScreen }

  @MainActor
  struct WindowPlacer {
      init(windowService: any WindowService, screens: any ScreenProviding)
      /// 窓がいまある画面（なければ mainScreen）で action の枠を計算して適用し、はみ出しを補正する。適用後の AX 枠を返す。
      @discardableResult
      func place(_ window: WindowHandle, action: SnapAction) throws -> CGRect
  }

  // SnapEngine に追加
  func clearMemory()
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/WindowPlacerTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct WindowPlacerTests {
    let windows = FakeWindowService()
    let screens = FakeScreenProvider.single
    let visibleAX = CGRect(x: 0, y: 25, width: 1920, height: 1010)

    @Test func 最大化はvisibleFrameをAX座標で適用する() throws {
        let placer = WindowPlacer(windowService: windows, screens: screens)
        let applied = try placer.place(windows.window, action: .maximize)
        #expect(windows.setFrameCalls == [visibleAX])
        #expect(applied == visibleAX)
    }

    @Test func 中央に配置は大きさを変えず中央へ() throws {
        windows.currentFrame = CGRect(x: 0, y: 25, width: 800, height: 600)
        let placer = WindowPlacer(windowService: windows, screens: screens)
        try placer.place(windows.window, action: .center)
        // NS: x = floor((1920-800)/2) = 560, y = floor(45 + (1010-600)/2) = 250 → AX y = 1080 - (250+600) = 230
        #expect(windows.setFrameCalls == [CGRect(x: 560, y: 230, width: 800, height: 600)])
    }

    @Test func 最小幅で右端からはみ出したら画面内へ戻す() throws {
        windows.minimumWidth = 800
        let placer = WindowPlacer(windowService: windows, screens: screens)
        let applied = try placer.place(windows.window, action: .rightThird)
        #expect(applied == CGRect(x: 1120, y: 25, width: 800, height: 1010))
        #expect(windows.setFrameCalls.count == 2)
    }

    @Test func 画面が見つからなければmainScreenにフォールバックする() throws {
        windows.currentFrame = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        try WindowPlacer(windowService: windows, screens: screens).place(windows.window, action: .maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 画面もmainScreenもなければnoScreen() {
        let empty = FakeScreenProvider(primaryHeight: 1080, screens: [], mainScreen: nil)
        let placer = WindowPlacer(windowService: windows, screens: empty)
        #expect(throws: PlacementError.noScreen) {
            try placer.place(windows.window, action: .maximize)
        }
        #expect(windows.setFrameCalls.isEmpty)
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`WindowPlacerTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: WindowPlacer を書き、SnapEngine をそれを使う形にする**

`Tatami/Engine/WindowPlacer.swift`: 現在の `SnapEngine.perform` の「現在枠の読み取り → NS 変換 → `ScreenLocator.region` → `LayoutCalculator.frame` → AX 変換 → `setFrame` → 読み直し → `originKeptInside` → 再適用」を `place` に移す。`originKeptInside` も `WindowPlacer` の private static に移す。

`Tatami/Engine/SnapEngine.swift`: `init` で `WindowPlacer(windowService:screens:)` を作って保持。`perform` は 権限確認 → `focusedWindow` → `frame(of:)`（`CycleResolver` 用の現在枠）→ `CycleResolver.resolve` → `placer.place(window, action:)` → `memory` 更新。`PlacementError.noScreen` は `fail(.noScreen)` に、`WindowServiceError` は `fail(.window(_))` に対応させる。`clearMemory()` は `memory = nil`。`SnapFailure` は変えない。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`WindowPlacerTests`、`SnapEngineTests`、`CycleResolverTests`）。Expected: 新規 5 件と既存がすべて PASS。`SnapEngineTests` は 1 行も変えない。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Engine/WindowPlacer.swift Tatami/Engine/SnapEngine.swift TatamiTests/WindowPlacerTests.swift
git commit -m "refactor: extract WindowPlacer from SnapEngine"
```

---

### Task 7: LayoutSetRunner（適用の実行と結果）

**Files:**
- Create: `Tatami/Engine/LayoutSetRunner.swift`
- Create: `TatamiTests/Fakes/FakeSpaceMover.swift`, `TatamiTests/Fakes/FakeDockPreferences.swift`
- Test: `TatamiTests/LayoutSetRunnerTests.swift`

**Interfaces:**
- Consumes: Task 2 の `WindowEnumerating` / `WindowService.unminimize` / `raise` / `SpaceMoving` / `SpaceMoveError`、Task 1 の `DockPreferencesReading`、Task 5 の `LayoutSetPlanner`、Task 6 の `WindowPlacer`、既存 `PermissionChecking`。
- Produces:
  ```swift
  struct FailedRow: Sendable { let row: LayoutRow; let error: any Error }

  struct LayoutRunResult: Sendable {
      let set: LayoutSet
      let placed: [LayoutRow]
      let skipped: [SkippedRow]
      let failed: [FailedRow]
      /// 自動並べ替えがオンでデスクトップ移動を飛ばした。
      let skippedDesktopMoves: Bool
      /// HUD の文言（§2.5）。
      var summary: String
  }

  @MainActor
  final class LayoutSetRunner {
      init(enumerator: any WindowEnumerating, windowService: any WindowService, placer: WindowPlacer,
           spaceMover: any SpaceMoving, dockPreferences: any DockPreferencesReading,
           permission: any PermissionChecking,
           onFinished: @escaping @MainActor (LayoutRunResult) -> Void)
      private(set) var isRunning: Bool
      /// 実行中・権限なしなら何もせず false。権限なしのときは requestAccess を呼ぶ。
      @discardableResult
      func apply(_ set: LayoutSet) async -> Bool
  }

  // テスト用
  @MainActor final class FakeSpaceMover: SpaceMoving {
      private(set) var calls: [(window: WindowHandle, desktop: Int)]
      var error: SpaceMoveError?
  }
  struct FakeDockPreferences: DockPreferencesReading {
      var rearrangesSpacesAutomatically: Bool
      func disableAutomaticRearrangement() throws {}
  }
  ```

`summary` の文言（`set.name` を先頭に）:

| 状況 | 文言 |
|---|---|
| 全件成功（3 件） | `連絡: 3 件を配置` |
| 一部飛ばし | `連絡: 3 件中 2 件を配置 ・ Teams は起動していません` |
| 合う窓がない | `… ・ WezTerm に合う窓がありません` |
| 失敗（一般） | `… ・ Discord の配置に失敗しました` |
| 失敗（`SpaceMoveError.shortcutDisabled(desktop: 3)`） | `… ・ デスクトップ 3 へ切り替えるショートカットがオフです` |
| `skippedDesktopMoves` | 末尾に ` ・ 自動並べ替えがオンなのでデスクトップ移動を飛ばしました` |
| 対象行が 0 | `連絡: 配置する行がありません` |

「N 件」は何もしない行を除いた行数。理由は行の順に「 ・ 」でつなぐ。同じ文言が重なっても 1 つにまとめない。

- [ ] **Step 1: テストを書く**

`TatamiTests/LayoutSetRunnerTests.swift`:

```swift
import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct LayoutSetRunnerTests {
    let windows = FakeWindowService()
    let enumerator = FakeWindowEnumerator()
    let mover = FakeSpaceMover()
    let permission = FakePermission()

    static func window(_ bundle: String, _ app: String, pid: pid_t, minimized: Bool = false) -> WindowInfo {
        WindowInfo(handle: WindowHandle(element: AXUIElementCreateApplication(pid)), pid: pid,
                   bundleIdentifier: bundle, appName: app, title: app,
                   frameAX: CGRect(x: 0, y: 25, width: 800, height: 600), isMinimized: minimized)
    }
    static let line = window("line", "LINE", pid: 1)
    static let discord = window("discord", "Discord", pid: 2, minimized: true)

    func makeRunner(rearranges: Bool = false,
                    onFinished: @escaping @MainActor (LayoutRunResult) -> Void = { _ in }) -> LayoutSetRunner {
        LayoutSetRunner(enumerator: enumerator, windowService: windows,
                        placer: WindowPlacer(windowService: windows, screens: FakeScreenProvider.single),
                        spaceMover: mover, dockPreferences: FakeDockPreferences(rearrangesSpacesAutomatically: rearranges),
                        permission: permission, onFinished: onFinished)
    }

    let set = LayoutSet(name: "連絡", rows: [
        LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird, desktop: 3),
        LayoutRow(bundleIdentifier: "discord", appName: "Discord", action: .centerThird, desktop: nil),
        LayoutRow(bundleIdentifier: "teams", appName: "Microsoft Teams", action: .rightThird, desktop: 3),
    ])

    @Test func 成功と飛ばしが結果に入りデスクトップ移動は該当行だけ() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        var results: [LayoutRunResult] = []
        let runner = makeRunner { results.append($0) }
        let started = await runner.apply(set)
        #expect(started)
        #expect(results.count == 1)
        let result = results[0]
        #expect(result.placed == [set.rows[0], set.rows[1]])
        #expect(result.skipped.map(\.reason) == [.appNotRunning])
        #expect(result.failed.isEmpty)
        #expect(!result.skippedDesktopMoves)
        #expect(mover.calls.map { $0.desktop } == [3])
        #expect(mover.calls.map { $0.window } == [Self.line.handle])
        #expect(windows.raiseCalls == [Self.line.handle, Self.discord.handle])
        #expect(windows.unminimizeCalls == [Self.discord.handle])
        #expect(windows.setFrameCalls.count == 2)
        #expect(result.summary == "連絡: 3 件中 2 件を配置 ・ Microsoft Teams は起動していません")
    }

    @Test func spaceMoverが投げたらfailedに入り次の行へ進む() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        mover.error = .shortcutDisabled(desktop: 3)
        var results: [LayoutRunResult] = []
        _ = await makeRunner { results.append($0) }.apply(set)
        let result = results[0]
        #expect(result.failed.map(\.row) == [set.rows[0]])
        #expect(result.placed == [set.rows[1]])
        #expect(result.summary == "連絡: 3 件中 1 件を配置 ・ デスクトップ 3 へ切り替えるショートカットがオフです ・ Microsoft Teams は起動していません")
    }

    @Test func 自動並べ替えがオンならデスクトップ移動を飛ばす() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        var results: [LayoutRunResult] = []
        _ = await makeRunner(rearranges: true) { results.append($0) }.apply(set)
        #expect(mover.calls.isEmpty)
        #expect(results[0].skippedDesktopMoves)
        #expect(results[0].placed.count == 2)
        #expect(results[0].summary.hasSuffix(" ・ 自動並べ替えがオンなのでデスクトップ移動を飛ばしました"))
    }

    @Test func 権限がなければ何もせずfalse() async {
        permission.isTrusted = false
        var results: [LayoutRunResult] = []
        let started = await makeRunner { results.append($0) }.apply(set)
        #expect(!started)
        #expect(results.isEmpty)
        #expect(permission.requestAccessCount == 1)
        #expect(windows.raiseCalls.isEmpty)
    }

    @Test func 何もしない行は件数に入らない() async {
        let set = LayoutSet(name: "s", rows: [
            LayoutRow(bundleIdentifier: "line", appName: "LINE"),
            LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .maximize),
        ])
        enumerator.windowsByBundle = ["line": [Self.line]]
        var results: [LayoutRunResult] = []
        _ = await makeRunner { results.append($0) }.apply(set)
        #expect(results[0].summary == "s: 1 件を配置")
    }

    @Test func 対象行がなければその旨() async {
        var results: [LayoutRunResult] = []
        _ = await makeRunner { results.append($0) }.apply(LayoutSet(name: "空"))
        #expect(results[0].summary == "空: 配置する行がありません")
    }

    @Test func 行の順に処理する() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        _ = await makeRunner().apply(set)
        #expect(windows.raiseCalls == [Self.line.handle, Self.discord.handle])
    }
}
```

`FakeSpaceMover.move` は `error` があれば投げ、なければ `calls` に積む。`FakeWindowService.raise` は `raiseCalls` に積む（Task 2 で追加済み）。

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutSetRunnerTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`Tatami/Engine/LayoutSetRunner.swift`: Interfaces のとおり。`apply`:

1. `isRunning` なら false。`permission.isTrusted` でなければ `requestAccess()` して false。
2. `isRunning = true`（`defer` で戻す）。`let skipMoves = dockPreferences.rearrangesSpacesAutomatically`。
3. `set.rows` の `bundleIdentifier` の重複を除いた集合ごとに `enumerator.windows(ofBundleIdentifier:)` を呼び、空でないものだけ `windowsByBundle` に入れる（空 = 起動していない）。
4. `LayoutSetPlanner.plan` の `steps` を順に: `isMinimized` なら `unminimize`、`raise`、`desktop` があり `!skipMoves` なら `windowService.frame(of:)` を読んで `spaceMover.move`、`action` があれば `placer.place`。`throw` されたらその行を `failed` に入れて次へ。
5. `LayoutRunResult` を作って `onFinished` に渡す。

`summary` は上の表のとおり。`placed.count + skipped.count + failed.count` が「N 件」。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutSetRunnerTests`）。Expected: 7 件 PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Engine/LayoutSetRunner.swift TatamiTests/Fakes TatamiTests/LayoutSetRunnerTests.swift
git commit -m "feat: add LayoutSetRunner that applies a layout set row by row"
```

---

### Task 8: RegionMatcher と LayoutCapture（いまの配置 → 行）

**Files:**
- Create: `Tatami/Engine/RegionMatcher.swift`
- Create: `Tatami/Engine/LayoutCapture.swift`
- Test: `TatamiTests/RegionMatcherTests.swift`, `TatamiTests/LayoutCaptureTests.swift`

**Interfaces:**
- Consumes: Task 2 の `WindowEnumerating` / `WindowInfo`、既存 `LayoutCalculator`、`ScreenLocator`、`CoordinateConverter`、`ScreenProviding`。
- Produces:
  ```swift
  enum RegionMatcher {
      /// サイズ系 3 つを除いた 24 区画。
      static let candidates: [SnapAction]
      static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat
      /// frameNS に最も近い区画。IoU が threshold 未満なら nil。
      static func closestAction(to frameNS: CGRect, in visible: CGRect, threshold: CGFloat = 0.9) -> SnapAction?
  }

  @MainActor
  struct LayoutCapture {
      init(enumerator: any WindowEnumerating, screens: any ScreenProviding)
      /// いまの配置を行にする。desktop は全行に同じ値。
      func capture(desktop: Int?) -> [LayoutRow]
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/RegionMatcherTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tatami

struct RegionMatcherTests {
    let visible = CGRect(x: 0, y: 45, width: 1920, height: 1010)

    @Test func 区画ちょうどの枠はその区画() {
        for action in RegionMatcher.candidates {
            let frame = LayoutCalculator.frame(for: action, in: visible, current: visible)
            #expect(RegionMatcher.closestAction(to: frame, in: visible) == action, "\(action)")
        }
    }

    @Test func 少しずれた枠も同じ区画() {
        let frame = LayoutCalculator.frame(for: .leftTwoThirds, in: visible, current: visible).insetBy(dx: 10, dy: 10)
        #expect(RegionMatcher.closestAction(to: frame, in: visible) == .leftTwoThirds)
    }

    @Test func 自由サイズはnil() {
        #expect(RegionMatcher.closestAction(to: CGRect(x: 300, y: 300, width: 700, height: 500), in: visible) == nil)
    }

    @Test func サイズ系は候補に出ない() {
        #expect(!RegionMatcher.candidates.contains(.maximizeHeight))
        #expect(!RegionMatcher.candidates.contains(.maximizeWidth))
        #expect(!RegionMatcher.candidates.contains(.center))
        #expect(RegionMatcher.candidates.count == 24)
    }

    @Test func IoUの計算() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(RegionMatcher.intersectionOverUnion(a, a) == 1)
        #expect(RegionMatcher.intersectionOverUnion(a, CGRect(x: 50, y: 0, width: 100, height: 100)) == CGFloat(50) / 150)
        #expect(RegionMatcher.intersectionOverUnion(a, CGRect(x: 200, y: 0, width: 10, height: 10)) == 0)
    }
}
```

`TatamiTests/LayoutCaptureTests.swift`:

```swift
import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct LayoutCaptureTests {
    let enumerator = FakeWindowEnumerator()
    let screens = FakeScreenProvider.single   // visible NS (0,45,1920,1010) → AX (0,25,1920,1010)

    static func window(_ bundle: String, _ app: String, _ title: String, pid: pid_t, frameAX: CGRect) -> WindowInfo {
        WindowInfo(handle: WindowHandle(element: AXUIElementCreateApplication(pid)), pid: pid,
                   bundleIdentifier: bundle, appName: app, title: title, frameAX: frameAX, isMinimized: false)
    }

    @Test func 窓ごとに区画へ丸めた行ができる() {
        enumerator.onScreen = [
            Self.window("wez", "WezTerm", "host: herdr", pid: 1, frameAX: CGRect(x: 0, y: 25, width: 1280, height: 1010)),
            Self.window("chrome", "Google Chrome", "GitHub", pid: 2, frameAX: CGRect(x: 1280, y: 25, width: 640, height: 1010)),
            Self.window("finder", "Finder", "Desktop", pid: 3, frameAX: CGRect(x: 300, y: 300, width: 700, height: 500)),
        ]
        let rows = LayoutCapture(enumerator: enumerator, screens: screens).capture(desktop: 2)
        #expect(rows.map(\.bundleIdentifier) == ["wez", "chrome", "finder"])
        #expect(rows.map(\.appName) == ["WezTerm", "Google Chrome", "Finder"])
        #expect(rows.map(\.action) == [.leftTwoThirds, .rightThird, nil])
        #expect(rows.map(\.desktop) == [2, 2, 2])
        #expect(rows.map(\.titleFilter) == ["", "", ""])
    }

    @Test func 同じアプリが2枚以上のときだけタイトルで絞り込む() {
        enumerator.onScreen = [
            Self.window("wez", "WezTerm", "host: herdr", pid: 1, frameAX: CGRect(x: 0, y: 25, width: 960, height: 1010)),
            Self.window("wez", "WezTerm", "host: tatami", pid: 1, frameAX: CGRect(x: 960, y: 25, width: 960, height: 1010)),
            Self.window("chrome", "Google Chrome", "GitHub", pid: 2, frameAX: CGRect(x: 0, y: 25, width: 1920, height: 1010)),
        ]
        let rows = LayoutCapture(enumerator: enumerator, screens: screens).capture(desktop: nil)
        #expect(rows.map(\.titleFilter) == ["host: herdr", "host: tatami", ""])
        #expect(rows.map(\.action) == [.leftHalf, .rightHalf, .maximize])
        #expect(rows.map(\.desktop) == [nil, nil, nil])
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`RegionMatcherTests`、`LayoutCaptureTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`Tatami/Engine/RegionMatcher.swift`: `candidates = SnapAction.allCases.filter { ![.maximizeHeight, .maximizeWidth, .center].contains($0) }`。`closestAction` は各候補の `LayoutCalculator.frame(for:in:current: frameNS)` との IoU を取り、最大が `threshold` 以上ならその候補。

`Tatami/Engine/LayoutCapture.swift`: `onScreenWindows()` の各窓を `CoordinateConverter.toScreen(_:primaryHeight:)` で NS にし、`ScreenLocator.region(containing:in:) ?? screens.mainScreen` の `visibleFrame` で `closestAction`。画面が取れない窓は `action = nil`。`titleFilter` は同じ `bundleIdentifier` の窓が 2 枚以上あるときだけ `title`。

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`RegionMatcherTests`、`LayoutCaptureTests`）。Expected: 7 件 PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Engine/RegionMatcher.swift Tatami/Engine/LayoutCapture.swift TatamiTests/RegionMatcherTests.swift TatamiTests/LayoutCaptureTests.swift
git commit -m "feat: capture the current window arrangement as layout rows"
```

---

### Task 9: 配線（ShortcutRegistrar、AppModel、メニュー、結果 HUD）

ここから先は Task 2 のスパイク結果を反映してから進める。

**Files:**
- Modify: `Tatami/App/ShortcutRegistrar.swift`
- Modify: `Tatami/App/AppModel.swift`
- Modify: `Tatami/App/MenuBarView.swift`
- Create: `Tatami/App/ResultHUD.swift`

**Interfaces:**
- Consumes: Task 4 `LayoutSetStore`、Task 7 `LayoutSetRunner` / `LayoutRunResult`、Task 6 `SnapEngine.clearMemory()`、Task 1 / 2 の System 型。
- Produces:
  ```swift
  extension LayoutSet {
      @MainActor var shortcutName: KeyboardShortcuts.Name   // Name("layoutSet.<uuid>")、既定キーなし
  }

  enum ShortcutRegistrar {
      static let pickerName = KeyboardShortcuts.Name("layoutSets.picker")
      /// 既存。isBusy が true、または NSApp.isActive のときは beep して何もしない。
      static func register(engine: SnapEngine, settings: CommandSettings, isBusy: @escaping @MainActor () -> Bool)
      /// ピッカーと各セットのハンドラを登録し、store.onChange で追加・削除に追従する。削除分は KeyboardShortcuts.reset と removeHandler。
      static func registerLayoutSets(store: LayoutSetStore,
                                     onPicker: @escaping @MainActor () -> Void,
                                     onApply: @escaping @MainActor (LayoutSet) -> Void)
  }

  @MainActor
  final class ResultHUD {
      /// 中央下（下端から 120pt）に text を出し、duration 後に閉じる。クリックで即閉じる。
      func show(_ text: String, duration: Duration = .seconds(2))
  }

  // AppModel に追加
  let layoutSets: LayoutSetStore
  let runner: LayoutSetRunner
  let hud: ResultHUD
  func apply(_ set: LayoutSet)          // Task { await runner.apply(set) }、false なら beep
  func openPicker()                     // Task 10 で中身を入れる。ここでは空でよい
  ```

- [ ] **Step 1: ShortcutRegistrar を拡張する**

`register(engine:settings:isBusy:)` のハンドラ先頭に `guard !isBusy(), !NSApp.isActive else { NSSound.beep(); return }` を足す。
`registerLayoutSets`: `pickerName` に `onKeyDown` で `onPicker`。`store.sets` の各セットに `onKeyDown` で `onApply(set)`（最新のセットを `store.set(id:)` で引き直す。名前の変更に追従するため）。登録済み id を `Set<UUID>` で持ち、`store.onChange` で新しい id を登録、消えた id は `KeyboardShortcuts.removeHandler(for:)` と `KeyboardShortcuts.reset(_:)`。

- [ ] **Step 2: ResultHUD を書く**

`Tatami/App/ResultHUD.swift`: `NSPanel(contentRect:styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)`、`level = .statusBar`、`collectionBehavior = [.canJoinAllSpaces, .transient]`、`isOpaque = false`、`backgroundColor = .clear`、`hasShadow = true`。中身は `NSHostingView` の SwiftUI（`Text` を `.regularMaterial` の角丸 12 の `padding(.horizontal, 16) .padding(.vertical, 10)` に）。`show` は前の表示を閉じてから出し、`Task.sleep(duration)` 後に `orderOut`。クリックは `NSHostingView` 上の `onTapGesture` で閉じる。位置はメイン画面の `visibleFrame.midX` と `visibleFrame.minY + 120`。

- [ ] **Step 3: AppModel とメニューを配線する**

`AppModel`: `layoutSets = LayoutSetStore()`、`hud = ResultHUD()`、`runner = LayoutSetRunner(enumerator: AccessibilityWindowEnumerator(), windowService: AccessibilityWindowService(), placer: WindowPlacer(...), spaceMover: CGEventSpaceMover(shortcuts: MissionControlShortcuts()), dockPreferences: DockPreferences(), permission: permission, onFinished: { [weak self] in self?.engine.clearMemory(); self?.hud.show($0.summary) })`。`start()` で `ShortcutRegistrar.register(engine:settings:isBusy: { [runner] in runner.isRunning })` と `registerLayoutSets(store:onPicker:onApply:)` を呼ぶ。

`MenuBarView`: 「設定…」の上に `Button("レイアウトセット…") { model.openPicker() }`。`model.layoutSets.sets` が空でなければその下に各セットの `Button(set.name) { model.apply(set) }` を並べ、`Divider()`。

- [ ] **Step 4: ビルドとテストが通ることを確認する**

テスト実行（全テスト）。Expected: すべて PASS。

- [ ] **Step 5: 実機で確認する**

設定画面はまだないので、`defaults` で 1 セットを仕込む（`LayoutSetStoreTests` と同じ JSON 形式。`LayoutSetStore.key` に Data として書く。例: `defaults write dev.hidekingerz.tatami layoutSets.v1 -data "$(printf '[{"id":"...","name":"作業","rows":[...]}]' | xxd -p | tr -d '\n')"`）。

1. メニューに「レイアウトセット…」と「作業」が出る。
2. 「作業」を選ぶと WezTerm と Chrome が並び、HUD に「作業: 2 件を配置」が出て 2 秒で消える。
3. Chrome を終了して再び選ぶと「作業: 2 件中 1 件を配置 ・ Google Chrome は起動していません」。
4. 設定画面を前面にして ⌃⌥b を押すと beep し、設定画面は動かない。閉じれば従来どおり。

- [ ] **Step 6: コミット**

```bash
git add Tatami/App
git commit -m "feat: wire layout sets into shortcuts, menu bar, and a result HUD"
```

---

### Task 10: ピッカー

**Files:**
- Modify: `Tatami/App/RegionGlyph.swift`
- Create: `Tatami/App/PickerPanel.swift`
- Create: `Tatami/App/PickerView.swift`
- Modify: `Tatami/App/AppModel.swift`（`openPicker` の中身）
- Test: `TatamiTests/RegionGlyphTests.swift`（既存に 1 件追加）

**Interfaces:**
- Consumes: Task 4 `LayoutSetStore`、Task 9 `AppModel.apply`。
- Produces:
  ```swift
  struct RegionGlyph: View {
      init(action: SnapAction, isEnabled: Bool = true)          // 既存。actions: [action] に委譲
      init(actions: [SnapAction], isEnabled: Bool = true)       // 複数の区画を 1 枚に重ねる
      static func normalizedRegion(for action: SnapAction) -> CGRect   // 既存
  }

  @MainActor
  final class PickerPanel: NSPanel {
      init(store: LayoutSetStore,
           onApply: @escaping @MainActor (LayoutSet) -> Void,
           onEdit: @escaping @MainActor (LayoutSet?) -> Void)   // nil = セットなしで設定を開く
      func toggle()      // 出ていれば閉じ、出ていなければメイン画面の中央上寄りに出して key にする
  }

  struct PickerView: View {
      init(store: LayoutSetStore, state: PickerState,
           onApply: @escaping (LayoutSet) -> Void, onEdit: @escaping (LayoutSet?) -> Void)
  }

  @MainActor @Observable
  final class PickerState {
      var query: String
      var selectedIndex: Int
      var expandedID: UUID?
      /// query で絞ったセット。名前とアプリ名への部分一致、大文字小文字を無視。
      static func filter(_ sets: [LayoutSet], query: String) -> [LayoutSet]
  }
  ```

- [ ] **Step 1: 絞り込みとグリフのテストを書く**

`TatamiTests/PickerStateTests.swift`（新規）:

```swift
import Testing
@testable import Tatami

@MainActor
struct PickerStateTests {
    let sets = [
        LayoutSet(name: "作業", rows: [LayoutRow(bundleIdentifier: "wez", appName: "WezTerm", action: .leftTwoThirds)]),
        LayoutSet(name: "連絡", rows: [LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird)]),
    ]

    @Test func 空の検索は全部() {
        #expect(PickerState.filter(sets, query: "").map(\.name) == ["作業", "連絡"])
    }

    @Test func 名前とアプリ名に部分一致() {
        #expect(PickerState.filter(sets, query: "連").map(\.name) == ["連絡"])
        #expect(PickerState.filter(sets, query: "wez").map(\.name) == ["作業"])
        #expect(PickerState.filter(sets, query: "LINE").map(\.name) == ["連絡"])
    }
}
```

`TatamiTests/RegionGlyphTests.swift` に追加:

```swift
    @Test func 複数区画のグリフは各区画の正規化矩形を重ねる() {
        let regions = [SnapAction.leftThird, .centerThird, .rightThird].map(RegionGlyph.normalizedRegion(for:))
        #expect(regions.map(\.minX) == [0, 1.0 / 3, 2.0 / 3])
        #expect(regions.allSatisfy { $0.height == 1 })
    }
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`PickerStateTests`）。Expected: コンパイルエラー。

- [ ] **Step 3: 実装する**

`RegionGlyph`: `actions` を持ち、`Canvas` で各区画を順に塗る（既存の 1 区画の描画をループに）。`init(action:)` は `init(actions: [action])`。

`PickerState`: Interfaces のとおり。`filter` は `set.name` と `set.rows.map(\.appName)` のいずれかが `localizedCaseInsensitiveContains(query)`。

`PickerView`: モックに従う。上に `TextField`（プレースホルダ「レイアウトセットを検索…」、右に「N セット」）、中に行（`RegionGlyph(actions: set.rows.compactMap(\.action))` 幅 48 高さ 32、名前、要約「`appName` `action.title`」を「 ・ 」でつないだもの、`desktop` があるものは「デスクトップ N」のバッジ、キーは `KeyboardShortcuts.getShortcut(for: set.shortcutName)?.description` か「未割当」）、下にヒント「⏎ 適用  ↑↓ 選択  →← 内訳  ⌘⏎ 編集  esc 閉じる」。選択行は `Color.accentColor` で塗り、文字は反転色。`expandedID` の行は下に各行の「appName / action.title / デスクトップ N」を縦に並べる。行のクリックで `onApply`。セットが 0 件なら「設定でセットを作ってください」と Enter で `onEdit(nil)`。

`PickerPanel`: `styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel]` は使わず `[.borderless]`、`level = .floating`、`collectionBehavior = [.canJoinAllSpaces, .transient]`、`isMovable = false`、幅 620。`canBecomeKey` を true に上書き。`keyDown` を上書きして ↑↓ / ⏎ / ⌘⏎ / esc / → / ← を処理し、それ以外は `super`（検索欄へ）。`resignKey` で閉じる。`toggle` は `NSApp.activate()` → `makeKeyAndOrderFront` → 検索欄へフォーカス。`onApply` の前に `close()`。

`AppModel.openPicker()`: `picker.toggle()`。`onApply` は `apply(set)`、`onEdit` は `NSApp.activate()` して設定を開く（`SettingsLink` は View なので、`NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` で開く。Task 11 でタブ選択を足す）。

- [ ] **Step 4: ビルドとテストが通ることを確認する**

テスト実行（全テスト）。Expected: すべて PASS。

- [ ] **Step 5: 実機で確認する**

設定画面で「ピッカーを開く」にキーを記録する手段はまだないので、`KeyboardShortcuts` の UserDefaults キー `KeyboardShortcuts_layoutSets.picker` を手で書くか、Task 11 のあとで確認してもよい。メニューの「レイアウトセット…」からは確認できる。

1. ピッカーが画面中央上寄りに出て、検索欄にフォーカスがある。
2. ↑↓ で選択が動き、端で止まる。文字を入れると絞られ、選択が先頭に戻る。
3. → で内訳が開き、← で閉じる。
4. Enter またはクリックでピッカーが閉じ、セットが適用され、HUD が出る。
5. esc で閉じる。別のアプリをクリックしても閉じる。
6. 別のデスクトップでもピッカーが出る。

- [ ] **Step 6: コミット**

```bash
git add Tatami/App TatamiTests/PickerStateTests.swift TatamiTests/RegionGlyphTests.swift
git commit -m "feat: add layout set picker panel"
```

---

### Task 11: 設定画面「セット」タブ

**Files:**
- Create: `Tatami/App/LayoutSetsTab.swift`
- Modify: `Tatami/App/SettingsView.swift`
- Modify: `Tatami/App/TatamiApp.swift`
- Modify: `Tatami/App/AppModel.swift`（`capture`、`dockPreferences` / `missionControl` の公開、設定タブの選択）

**Interfaces:**
- Consumes: Task 4 `LayoutSetStore`、Task 8 `LayoutCapture`、Task 1 `DockPreferencesReading` / `MissionControlShortcutReading`、Task 9 `ShortcutRegistrar.pickerName`、Task 10 の `onEdit`。
- Produces:
  ```swift
  struct LayoutSetsTab: View {
      init(model: AppModel)
  }
  // AppModel に追加
  let capture: LayoutCapture
  let dockPreferences: any DockPreferencesReading
  let missionControl: any MissionControlShortcutReading
  var settingsTab: SettingsTab          // .commands(SnapCommand.Category) | .layoutSets(selectedID: UUID?)
  ```

- [ ] **Step 1: SettingsView にタブを足す**

`SettingsView` を `TabView(selection:)` にし、`SettingsTab` を `Hashable` な enum にする。既存 6 タブは `.commands(category)`。末尾に `LayoutSetsTab(model:)` を `.layoutSets` で足し、`tabItem` は `Label("セット", systemImage: "rectangle.3.group")`。`.frame(width: 640)`。`TatamiApp` は `SettingsView(model:)` に変える（`settings` は `model.settings` から取る）。

- [ ] **Step 2: LayoutSetsTab を書く**

`Form(.grouped)`:

- Section「ピッカー」: `KeyboardShortcuts.Recorder("ピッカーを開く", name: ShortcutRegistrar.pickerName)`。
- 警告（該当時のみ、Section の上）:
  - `dockPreferences.rearrangesSpacesAutomatically` が true で、いずれかのセットに `desktop != nil` の行があるとき: 「Mission Control の『最新の使用状況に基づいて操作スペースを自動的に並べ替える』がオンです。オンの間はデスクトップ番号への移動を飛ばします。」と `Button("オフにする…")`。押すと `confirmationDialog`「Dock を再起動します。デスクトップの並びが変わることがあります。」→ 了承で `try dockPreferences.disableAutomaticRearrangement()`。失敗は `Alert` で表示。
  - 各セットの `desktop` の集合のうち `missionControl.switchToDesktopShortcut(n) == nil` のものがあるとき: 「デスクトップ N へ切り替えるショートカットがオフです。システム設定 → キーボード → キーボードショートカット → Mission Control で有効にしてください。」と `Button("システム設定を開く")`（`x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts`）。
  - 両方とも表示のたびに読み直す（`onAppear` と `scenePhase` の変化で）。
- Section「セット」: `List` に `ForEach(model.layoutSets.sets)` で `LayoutSetEditor`（`DisclosureGroup`。ヘッダ: 名前の `TextField`（`onSubmit` と `onChange` で `store.update`）、`KeyboardShortcuts.Recorder(for: set.shortcutName)`、削除ボタン）。開くと `ForEach(set.rows)` で `LayoutRowEditor`、`onMove` で行の並び替え、「行を追加」。`settingsTab == .layoutSets(selectedID:)` の id は最初から開く。
- `LayoutRowEditor` 1 行: アプリの `Picker`（`NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }` を `localizedName` 順、現在の `bundleIdentifier` が一覧になければその値を先頭に表示。末尾に「bundle identifier を入力…」→ `TextField` に切り替え）、`TextField`（プレースホルダ「タイトルに含む文字（任意）」）、区画の `Menu`（ラベルは `RegionGlyph(action:)` + `action.title` か「変えない」。中身は `SnapCommand.Category.allCases` ごとの `Menu(category.title)` に `RegionMatcher.candidates` と サイズ系 3 つ を含む全 27 区画を `category` 順で、先頭に「変えない」）、デスクトップの `Picker`（「変えない」, 1...10）、削除ボタン。`isNoOp` の行は文字を `.secondary` にし「何もしない」を添える。変更は即 `store.update`。
- 下部: `Button("セットを追加")` → `LayoutSet(name: "名称未設定")` を `add` し開く。`Button("いまの配置を保存")` → `sheet` で「このセットはデスクトップ何番ですか」（`Picker`: 指定しない, 1...10）と「保存」。保存で `model.capture.capture(desktop:)` の行を持つ `LayoutSet(name: "名称未設定")` を `add` し、そのセットを開く。

`AppModel`: `capture = LayoutCapture(enumerator: AccessibilityWindowEnumerator(), screens: NSScreenProvider())`、`dockPreferences` と `missionControl` は Task 9 で runner に渡したインスタンスを保持して公開。Task 10 の `onEdit` は `settingsTab = .layoutSets(selectedID: set?.id)` にしてから設定を開く。

- [ ] **Step 3: ビルドとテストが通ることを確認する**

テスト実行（全テスト）。Expected: すべて PASS。

- [ ] **Step 4: 実機で確認する**

`defaults delete dev.hidekingerz.tatami` で設定を消した状態から。確認できない項目はそのまま報告する。

1. 設定に「セット」タブがあり、ウィンドウ幅 640 で既存タブも崩れない。
2. 「ピッカーを開く」にキーを記録し、どのアプリの前面でもピッカーが出る。
3. 「セットを追加」→ 名前「作業」、行を 2 つ（WezTerm `herdr` 左 2/3、Chrome 右 1/3）作り、キーを記録 → そのキーで即適用される。
4. 自動並べ替えがオンの状態で、行にデスクトップ 3 を入れると警告が出る。「オフにする…」→ 確認 → Dock が再起動し、警告が消える。
5. デスクトップ 3 のショートカットがオフだと警告が出る。「システム設定を開く」でキーボードショートカットの画面が開く。オンにして設定画面に戻ると警告が消える。
6. 「連絡」セット（LINE / Discord / Teams、1/3 ずつ、デスクトップ 3）で、LINE をデスクトップ 1 に出した状態から適用 → LINE がデスクトップ 3 へ移り、3 枚が並ぶ。HUD に「連絡: 3 件を配置」。
7. Teams を終了して適用 → 「連絡: 3 件中 2 件を配置 ・ Microsoft Teams は起動していません」。
8. 「いまの配置を保存」→ デスクトップ「指定しない」→ 見えている窓の数だけ行ができ、左 2/3・右 1/3 に置いた窓がその区画、自由サイズの窓は「何もしない」。同じアプリが 2 枚なら絞り込みにタイトルが入る。
9. 行をドラッグで並び替え、削除、「変えない」の選択が保存され、再起動後も残る。
10. セットを削除すると、そのキーが効かなくなり、再起動後も復活しない。
11. ピッカーで ⌘⏎ → 設定の「セット」タブがそのセットを開いた状態で出る。
12. 既存 8 ショートカットが変更前と同じ動作をする。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App
git commit -m "feat: layout sets settings tab with editor, capture, and desktop warnings"
```

---

### Task 12: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「レイアウトセット」の節を足す**

「ショートカット」の節の後に `## レイアウトセット`:

- 何ができるか（複数の窓を一括配置、ピッカー、セットごとのキー、いまの配置を保存）。
- デスクトップ移動の仕組み: タイトルバーを掴んだまま Mission Control の「デスクトップ N へ切り替え」を送る。非公開 API は使わない。
- 必要な設定: システム設定 → キーボード → キーボードショートカット → Mission Control で「デスクトップ N へ切り替え」をオン。「最新の使用状況に基づいて操作スペースを自動的に並べ替える」はオフ（設定画面の「オフにする」ボタンでも可）。オンの間はデスクトップ移動を飛ばす。
- 制約: 存在しない番号は無視される、複数ディスプレイのデスクトップ指定は対象外、フルスクリーンの窓は対象外、Task 2 で × だったアプリがあればその名前。
- トラブルシュート: `defaults write dev.hidekingerz.tatami debugMenu -bool YES` でデバッグメニュー、`log stream` の述語。

- [ ] **Step 2: コミット**

```bash
git add README.md
git commit -m "docs: describe layout sets, picker, and desktop move requirements in README"
```

---

## 完了条件

- 全テストが `xcodebuild ... test` で PASS。
- Task 2 の確認表が埋まり、×のアプリがあれば README に書かれている。
- Task 9 / 10 / 11 の実機確認がすべて通る（通らない項目は報告する）。
- `git log` に Task 1〜12 のコミットが並んでいる。
