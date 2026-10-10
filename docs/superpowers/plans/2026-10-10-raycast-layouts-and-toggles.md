# Raycast 互換の配置パターンとコマンドの有効/無効 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tatami のコマンドを 8 個から 27 個（Raycast の区画系・サイズ系）へ増やし、設定画面でコマンドごとに有効/無効を切り替えられるようにする。既存 8 個だけが初期状態で有効。

**Architecture:** `SnapAction` と `LayoutCalculator` に新しい区画とサイズ系の計算を足し、`SnapCommand` を `String` rawValue 付きの 27 case に拡張してカテゴリを持たせる。有効/無効は App 層の新クラス `CommandSettings` が UserDefaults に保存し、`ShortcutRegistrar` が KeyboardShortcuts の `enable`/`disable` でホットキー登録に反映する。設定画面はカテゴリごとのタブに、行はトグル + 区画グリフ + 名前 + Recorder にする。

**Tech Stack:** Swift 6 言語モード、SwiftUI（TabView / Canvas / ImageRenderer）、sindresorhus/KeyboardShortcuts 2.4.0、Swift Testing、Xcode 26 / xcodebuild。

**Spec:** `docs/superpowers/specs/2026-10-10-raycast-layouts-and-toggles-design.md`

## Global Constraints

- 最低 macOS 26、Swift 6 言語モード（strict concurrency）。既存のビルド設定は変えない。
- 既存 8 コマンドの rawValue は現在の `KeyboardShortcuts.Name` の文字列と同一にする: `cycleLeft`, `cycleRight`, `topHalf`, `bottomHalf`, `maximize`, `leftThird`, `centerThird`, `rightThird`。
- 既存 8 コマンドの既定キーは変えない: ⌃⌥b / ⌃⌥f / ⌃⌥p / ⌃⌥n / ⌃⌥m / ⌃⌥z / ⌃⌥x / ⌃⌥c。新規 19 コマンドは既定キーなし。
- 既定で有効なのは既存 8 コマンドだけ。有効/無効の保存キーは `command.<rawValue>.enabled`。
- 無効なコマンドはホットキーを登録しない。無効中は Recorder を操作不可にする。
- 分割の端数は右端・上端の区画に寄せ、同じ分割に属する区画は隙間も重なりもなく visibleFrame を埋める。
- 座標は `WindowService` の境界で AX 座標（左上原点）、`LayoutCalculator` は NS 座標（左下原点）。
- `SnapCommand.allCases` の順はカテゴリ順（半分 → 1/3 → 1/4 → 四隅 → 1/6 → サイズ）。設定画面はこの順。
- ビルドとテストは `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS'` で通ること。
- ソースと設計書のコメントは日本語。識別子は英語。テスト名も日本語（既存に合わせる）。
- 各 Task の最後にコミットする。コミットメッセージ末尾に `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` を付ける。
- 作業ブランチは `feature/raycast-layouts`（作成済み）。

## Review Focus

1. **visibleFrame より大きいウィンドウに「中央に配置」「高さを最大化」「幅を最大化」**: 枠を visibleFrame の大きさまで縮め、はみ出さないこと（Task 2 `LayoutCalculatorTests` の「現在枠が画面より大きければ縮める」で検証）。
2. **幅や高さが 4 や 6 で割り切れない画面、原点が負の画面**: 1/4・四隅・1/6 が隙間も重なりもなく埋め、画面外へ出ないこと（Task 1 `LayoutCalculatorTests` の奇数サイズ・オフセット付きの敷き詰めテストで検証）。
3. **アップデート前からの利用者**: 変更済みのキー割当がそのまま効き、8 コマンドが有効なままであること（Task 3 `SnapCommandTests` の rawValue 一致と `isEnabledByDefault`、Task 4 `CommandSettingsTests` の「設定なしで既定値」で検証）。
4. **無効なコマンドにキーを記録しようとする**: Recorder が操作不可で記録できないこと（KeyboardShortcuts は記録時に即登録するため）。Task 7 の実機確認項目。
5. **有効にしたがキー未設定のコマンド**: 何も登録せず、エラーにもならず、Recorder だけが操作可能になること（Task 4 `CommandSettingsTests` の「キーの有無に関係なく保存される」、Task 7 の実機確認項目で検証）。

---

## ファイル構成

```
Tatami/
  Model/SnapAction.swift            Task 1（区画 14 種追加）, Task 2（サイズ系 3 種追加）
  Model/SnapCommand.swift           Task 3（27 case、Category、title、isEnabledByDefault）
  Engine/LayoutCalculator.swift     Task 1（current 引数、列/行ヘルパー、新区画）, Task 2（サイズ系）
  Engine/SnapEngine.swift           Task 1（current を渡す）
  App/CommandSettings.swift         Task 4（新規）
  App/ShortcutRegistrar.swift       Task 3（title を Model へ移動）, Task 5（27 個の Name、enable/disable）
  App/AppModel.swift                Task 5（CommandSettings を保持）
  App/RegionGlyph.swift             Task 6（新規）
  App/SettingsView.swift            Task 7（TabView、CommandListTab、CommandRow）
  App/TatamiApp.swift               Task 7（settings を渡す）
TatamiTests/
  LayoutCalculatorTests.swift       Task 1, Task 2
  SnapEngineTests.swift             Task 3
  SnapCommandTests.swift            Task 3
  CommandSettingsTests.swift        Task 4（新規）
  RegionGlyphTests.swift            Task 6（新規）
README.md                           Task 8
docs/superpowers/specs/2026-10-10-raycast-layouts-and-toggles-design.md  Task 6（グリフの基準矩形を修正）
```

Xcode プロジェクトは `PBXFileSystemSynchronizedRootGroup` なので、新規ファイルはフォルダに置くだけで対象に入る。`project.pbxproj` は触らない。

テストの実行コマンド（以下「テスト実行」と書いたらこれ）:

```bash
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test -only-testing:TatamiTests/<SuiteName> 2>&1 | grep -E "Test Suite|Test Case|passed|failed|error:" | tail -40
```

全テストは `-only-testing:` を外す。初回はパッケージ解決とビルドで数分かかる。

---

### Task 1: LayoutCalculator に現在枠の引数と 1/4・四隅・1/6 の区画を追加する

**Files:**
- Modify: `Tatami/Model/SnapAction.swift`
- Modify: `Tatami/Engine/LayoutCalculator.swift`
- Modify: `Tatami/Engine/SnapEngine.swift:63`
- Test: `TatamiTests/LayoutCalculatorTests.swift`

**Interfaces:**
- Consumes: 既存の `SnapAction`、`LayoutCalculator.frame(for:in:)`。
- Produces: `LayoutCalculator.frame(for action: SnapAction, in visible: CGRect, current: CGRect) -> CGRect`。`SnapAction` に 14 case 追加: `firstFourth, secondFourth, thirdFourth, lastFourth, topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter, topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth`。

- [ ] **Step 1: 既存テストの呼び出しに `current:` を足し、新しい区画のテストを書く**

まず既存の呼び出しを機械的に書き換える:

```bash
cd /Users/hidekingerz/ghq/github.com/hidekingerz/tatami
sed -i '' -E 's/(LayoutCalculator\.frame\(for: [^,]+, in: [A-Za-z]+)\)/\1, current: window)/g' TatamiTests/LayoutCalculatorTests.swift
grep -c "current: window" TatamiTests/LayoutCalculatorTests.swift   # 15 前後になる
```

次に `TatamiTests/LayoutCalculatorTests.swift` の `let offsetScreen = ...` の直後にプロパティを足し、末尾の `}` の前に新しいテストを追加する:

```swift
    /// 区画系の計算では使われない現在枠。サイズ系（Task 2）で意味を持つ。
    let window = CGRect(x: 100, y: 100, width: 400, height: 300)
    /// 幅 1003・高さ 701 は 2・3・4 のどれでも割り切れない。
    let oddScreen = CGRect(x: 0, y: 0, width: 1003, height: 701)

    static let fourths: [SnapAction] = [.firstFourth, .secondFourth, .thirdFourth, .lastFourth]
    static let quarters: [SnapAction] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
    static let sixths: [SnapAction] = [
        .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
    ]
```

```swift
    @Test func 四分割は隙間なく幅を埋める_右に端数を寄せる() {
        let frames = Self.fourths.map { LayoutCalculator.frame(for: $0, in: oddScreen, current: window) }
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 250, height: 701))
        #expect(frames[1] == CGRect(x: 250, y: 0, width: 250, height: 701))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 250, height: 701))
        #expect(frames[3] == CGRect(x: 750, y: 0, width: 253, height: 701))
    }

    @Test func 四隅は半分の幅と高さの組み合わせ_右上に端数を寄せる() {
        #expect(LayoutCalculator.frame(for: .bottomLeftQuarter, in: oddScreen, current: window)
                == CGRect(x: 0, y: 0, width: 501, height: 350))
        #expect(LayoutCalculator.frame(for: .bottomRightQuarter, in: oddScreen, current: window)
                == CGRect(x: 501, y: 0, width: 502, height: 350))
        #expect(LayoutCalculator.frame(for: .topLeftQuarter, in: oddScreen, current: window)
                == CGRect(x: 0, y: 350, width: 501, height: 351))
        #expect(LayoutCalculator.frame(for: .topRightQuarter, in: oddScreen, current: window)
                == CGRect(x: 501, y: 350, width: 502, height: 351))
    }

    @Test func 六分割は三分の一の幅と半分の高さの組み合わせ() {
        #expect(LayoutCalculator.frame(for: .bottomLeftSixth, in: oddScreen, current: window)
                == CGRect(x: 0, y: 0, width: 334, height: 350))
        #expect(LayoutCalculator.frame(for: .topCenterSixth, in: oddScreen, current: window)
                == CGRect(x: 334, y: 350, width: 334, height: 351))
        #expect(LayoutCalculator.frame(for: .topRightSixth, in: oddScreen, current: window)
                == CGRect(x: 668, y: 350, width: 335, height: 351))
        #expect(LayoutCalculator.frame(for: .bottomRightSixth, in: oddScreen, current: window)
                == CGRect(x: 668, y: 0, width: 335, height: 350))
    }

    /// 同じ分割に属する区画が、隙間も重なりもなく visibleFrame を埋めることを総当たりで確かめる。
    @Test(arguments: [Self.fourths, Self.quarters, Self.sixths],
          [CGRect(x: 0, y: 0, width: 1000, height: 700),
           CGRect(x: 0, y: 0, width: 1003, height: 701),
           CGRect(x: -1440, y: 25, width: 1440, height: 875)])
    func 分割は隙間も重なりもなく画面を埋める(group: [SnapAction], visible: CGRect) {
        let frames = group.map { LayoutCalculator.frame(for: $0, in: visible, current: window) }
        for frame in frames {
            #expect(visible.contains(frame), "\(frame) が \(visible) からはみ出している")
        }
        let area = frames.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == visible.width * visible.height)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                #expect(a.intersection(b).isEmpty, "\(a) と \(b) が重なっている")
            }
        }
    }
```

既存の「全区画が原点オフセット付きvisibleFrameの内側に収まる」は `SnapAction.allCases` を引数にしているので、新しい区画も自動で対象になる。

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutCalculatorTests`）。
Expected: コンパイルエラー（`current` 引数がない、`firstFourth` などが未定義）。

- [ ] **Step 3: SnapAction に区画を追加し、LayoutCalculator を列/行ヘルパーで書き直す**

`Tatami/Model/SnapAction.swift`:

```swift
import Foundation

/// ウィンドウを配置する区画。
enum SnapAction: CaseIterable, Sendable {
    // 半分と最大化
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    // 横 1/3 と 2/3
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    // 横 1/4
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    // 四隅（横半分 × 縦半分）
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // 1/6（横 1/3 × 縦半分）
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
}
```

`Tatami/Engine/LayoutCalculator.swift` を全体として次にする:

```swift
import CoreGraphics

/// 区画の目標枠を計算する純粋関数。入出力とも NS 座標（左下原点）。
///
/// 分割の端数は右端・上端の区画に寄せ、区画同士に隙間と重なりを作らない。
/// `current` はウィンドウの現在枠で、サイズ系の区画だけが使う。
enum LayoutCalculator {
    static func frame(for action: SnapAction, in visible: CGRect, current: CGRect) -> CGRect {
        switch action {
        case .maximize:
            return visible

        case .leftHalf: return cell(column: 0, of: 2, row: 0, of: 1, in: visible)
        case .rightHalf: return cell(column: 1, of: 2, row: 0, of: 1, in: visible)
        // NS 座標は下が原点なので、行 0 が下半分。
        case .bottomHalf: return cell(column: 0, of: 1, row: 0, of: 2, in: visible)
        case .topHalf: return cell(column: 0, of: 1, row: 1, of: 2, in: visible)

        case .leftThird: return cell(column: 0, of: 3, row: 0, of: 1, in: visible)
        case .centerThird: return cell(column: 1, of: 3, row: 0, of: 1, in: visible)
        case .rightThird: return cell(column: 2, of: 3, row: 0, of: 1, in: visible)
        case .leftTwoThirds:
            let third = column(0, of: 3, in: visible)
            return CGRect(x: visible.minX, y: visible.minY, width: third.width * 2, height: visible.height)
        case .rightTwoThirds:
            let third = column(0, of: 3, in: visible)
            return CGRect(x: visible.minX + third.width, y: visible.minY,
                          width: visible.width - third.width, height: visible.height)

        case .firstFourth: return cell(column: 0, of: 4, row: 0, of: 1, in: visible)
        case .secondFourth: return cell(column: 1, of: 4, row: 0, of: 1, in: visible)
        case .thirdFourth: return cell(column: 2, of: 4, row: 0, of: 1, in: visible)
        case .lastFourth: return cell(column: 3, of: 4, row: 0, of: 1, in: visible)

        case .topLeftQuarter: return cell(column: 0, of: 2, row: 1, of: 2, in: visible)
        case .topRightQuarter: return cell(column: 1, of: 2, row: 1, of: 2, in: visible)
        case .bottomLeftQuarter: return cell(column: 0, of: 2, row: 0, of: 2, in: visible)
        case .bottomRightQuarter: return cell(column: 1, of: 2, row: 0, of: 2, in: visible)

        case .topLeftSixth: return cell(column: 0, of: 3, row: 1, of: 2, in: visible)
        case .topCenterSixth: return cell(column: 1, of: 3, row: 1, of: 2, in: visible)
        case .topRightSixth: return cell(column: 2, of: 3, row: 1, of: 2, in: visible)
        case .bottomLeftSixth: return cell(column: 0, of: 3, row: 0, of: 2, in: visible)
        case .bottomCenterSixth: return cell(column: 1, of: 3, row: 0, of: 2, in: visible)
        case .bottomRightSixth: return cell(column: 2, of: 3, row: 0, of: 2, in: visible)
        }
    }

    /// visible を columns 列 × rows 行に等分したときのセル。
    private static func cell(column c: Int, of columns: Int, row r: Int, of rows: Int, in visible: CGRect) -> CGRect {
        let x = column(c, of: columns, in: visible)
        let y = row(r, of: rows, in: visible)
        return CGRect(x: x.x, y: y.y, width: x.width, height: y.height)
    }

    /// visible を count 列に等分したときの index 番目（左から 0 始まり）の x と幅。端数は最後の列に寄せる。
    private static func column(_ index: Int, of count: Int, in visible: CGRect) -> (x: CGFloat, width: CGFloat) {
        let base = (visible.width / CGFloat(count)).rounded(.down)
        let x = visible.minX + base * CGFloat(index)
        let width = index == count - 1 ? visible.maxX - x : base
        return (x, width)
    }

    /// visible を count 行に等分したときの index 番目（下から 0 始まり）の y と高さ。端数は最上段に寄せる。
    private static func row(_ index: Int, of count: Int, in visible: CGRect) -> (y: CGFloat, height: CGFloat) {
        let base = (visible.height / CGFloat(count)).rounded(.down)
        let y = visible.minY + base * CGFloat(index)
        let height = index == count - 1 ? visible.maxY - y : base
        return (y, height)
    }
}
```

`Tatami/Engine/SnapEngine.swift` の呼び出し（63 行目付近）を書き換える:

```swift
            let targetNS = LayoutCalculator.frame(for: action, in: region.visibleFrame, current: currentNS)
```

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutCalculatorTests`）。続けて `SnapEngineTests` と `CycleResolverTests` も実行し、既存の期待値（半分 960、1/3 640、2/3 1280 など）が変わっていないことを確認する。
Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Model/SnapAction.swift Tatami/Engine/LayoutCalculator.swift Tatami/Engine/SnapEngine.swift TatamiTests/LayoutCalculatorTests.swift
git commit -m "feat: add fourths, quarters and sixths to LayoutCalculator

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: サイズ系 3 区画（高さを最大化・幅を最大化・中央に配置）

**Files:**
- Modify: `Tatami/Model/SnapAction.swift`
- Modify: `Tatami/Engine/LayoutCalculator.swift`
- Test: `TatamiTests/LayoutCalculatorTests.swift`, `TatamiTests/SnapEngineTests.swift`

**Interfaces:**
- Consumes: Task 1 の `LayoutCalculator.frame(for:in:current:)`。
- Produces: `SnapAction` に `maximizeHeight, maximizeWidth, center` を追加（計 27 case）。

- [ ] **Step 1: テストを書く**

`TatamiTests/LayoutCalculatorTests.swift` に追加:

```swift
    @Test func 高さを最大化は幅とxを保って縦いっぱいにする() {
        let frame = LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: window)
        #expect(frame == CGRect(x: 100, y: 0, width: 400, height: 700))
    }

    @Test func 幅を最大化は高さとyを保って横いっぱいにする() {
        let frame = LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: window)
        #expect(frame == CGRect(x: 0, y: 100, width: 1000, height: 300))
    }

    @Test func 中央に配置は大きさを保って画面中央に置く() {
        let frame = LayoutCalculator.frame(for: .center, in: screen, current: window)
        #expect(frame == CGRect(x: 300, y: 200, width: 400, height: 300))
    }

    @Test func 中央に配置の端数は切り捨てる_原点オフセット付き() {
        // offsetScreen の中心は (-720, 462.5)。幅 400・高さ 300 なら x = -920, y = 312.5 → 312。
        let frame = LayoutCalculator.frame(for: .center, in: offsetScreen, current: window)
        #expect(frame == CGRect(x: -920, y: 312, width: 400, height: 300))
    }

    @Test func 現在枠が画面より大きければ縮める() {
        let huge = CGRect(x: -50, y: -50, width: 1200, height: 900)
        #expect(LayoutCalculator.frame(for: .center, in: screen, current: huge) == screen)
        #expect(LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: huge) == screen)
        #expect(LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: huge) == screen)
    }

    @Test func 高さを最大化で右にはみ出すなら内側へ寄せる() {
        let nearRightEdge = CGRect(x: 800, y: 100, width: 400, height: 300)
        let frame = LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: nearRightEdge)
        #expect(frame == CGRect(x: 600, y: 0, width: 400, height: 700))
    }

    @Test func 幅を最大化で上にはみ出すなら内側へ寄せる() {
        let nearTop = CGRect(x: 100, y: 600, width: 400, height: 300)
        let frame = LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: nearTop)
        #expect(frame == CGRect(x: 0, y: 400, width: 1000, height: 300))
    }

    @Test(arguments: SnapAction.allCases)
    func 現在枠が画面外にあっても全区画が画面内に収まる(action: SnapAction) {
        let outside = CGRect(x: 5000, y: -3000, width: 1600, height: 1200)
        let frame = LayoutCalculator.frame(for: action, in: offsetScreen, current: outside)
        #expect(offsetScreen.contains(frame), "\(action) が画面外にはみ出している: \(frame)")
    }
```

SnapEngine を通したテストは `SnapCommand` に `.center` などが増える Task 3 で書く。

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`LayoutCalculatorTests`）。
Expected: コンパイルエラー（`maximizeHeight` などが未定義）。

- [ ] **Step 3: 実装する**

`Tatami/Model/SnapAction.swift` の末尾の case のあとに追加:

```swift
    // サイズ系（現在枠に依存する）
    case maximizeHeight
    case maximizeWidth
    case center
```

`Tatami/Engine/LayoutCalculator.swift` の `switch` に追加（`.bottomRightSixth` の次）:

```swift
        case .maximizeHeight:
            let width = min(current.width, visible.width)
            return keptInside(CGRect(x: current.minX, y: visible.minY, width: width, height: visible.height), in: visible)
        case .maximizeWidth:
            let height = min(current.height, visible.height)
            return keptInside(CGRect(x: visible.minX, y: current.minY, width: visible.width, height: height), in: visible)
        case .center:
            let size = CGSize(width: min(current.width, visible.width), height: min(current.height, visible.height))
            let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(.down),
                                 y: (visible.midY - size.height / 2).rounded(.down))
            return keptInside(CGRect(origin: origin, size: size), in: visible)
```

同じファイルの private ヘルパーに追加:

```swift
    /// frame が visible からはみ出していれば、大きさはそのままに原点を内側へ寄せる。
    /// frame の大きさは visible 以下である前提。
    private static func keptInside(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        return CGRect(origin: origin, size: frame.size)
    }
```

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`LayoutCalculatorTests`）。
Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Model/SnapAction.swift Tatami/Engine/LayoutCalculator.swift TatamiTests/LayoutCalculatorTests.swift
git commit -m "feat: add maximize height/width and center actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: SnapCommand を 27 個にし、カテゴリ・表示名・既定の有効状態を持たせる

**Files:**
- Modify: `Tatami/Model/SnapCommand.swift`
- Modify: `Tatami/App/ShortcutRegistrar.swift`（`title` を削除。残りは Task 5 で書き換える）
- Test: `TatamiTests/SnapCommandTests.swift`, `TatamiTests/SnapEngineTests.swift`

**Interfaces:**
- Consumes: Task 1・2 の `SnapAction`。
- Produces:
  - `enum SnapCommand: String, CaseIterable, Sendable`（27 case、カテゴリ順）
  - `SnapCommand.Category: CaseIterable, Sendable` — `halves, thirds, fourths, quarters, sixths, size`
  - `SnapCommand.sequence: [SnapAction]`, `.isCycle: Bool`, `.category: Category`, `.title: String`, `.isEnabledByDefault: Bool`
  - `SnapCommand.Category.title: String`, `.commands: [SnapCommand]`

- [ ] **Step 1: テストを書き換える**

`TatamiTests/SnapCommandTests.swift` を全体として次にする:

```swift
import Testing
@testable import Tatami

struct SnapCommandTests {
    @Test func 区画は27種類ある() {
        #expect(SnapAction.allCases.count == 27)
    }

    @Test func コマンドは27種類ある() {
        #expect(SnapCommand.allCases.count == 27)
    }

    @Test func コマンドはカテゴリ順に並ぶ() {
        let categories = SnapCommand.allCases.map(\.category)
        let expected = SnapCommand.Category.allCases.flatMap { category in
            Array(repeating: category, count: category.commands.count)
        }
        #expect(categories == expected)
        #expect(SnapCommand.Category.allCases == [.halves, .thirds, .fourths, .quarters, .sixths, .size])
    }

    @Test func カテゴリごとのコマンド数() {
        #expect(SnapCommand.Category.halves.commands == [.cycleLeft, .cycleRight, .topHalf, .bottomHalf])
        #expect(SnapCommand.Category.thirds.commands
                == [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
        #expect(SnapCommand.Category.fourths.commands == [.firstFourth, .secondFourth, .thirdFourth, .lastFourth])
        #expect(SnapCommand.Category.quarters.commands
                == [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter])
        #expect(SnapCommand.Category.sixths.commands == [
            .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
        ])
        #expect(SnapCommand.Category.size.commands == [.maximize, .maximizeHeight, .maximizeWidth, .center])
    }

    @Test func 既定で有効なのはMVPの8コマンドだけ() {
        let enabled = SnapCommand.allCases.filter(\.isEnabledByDefault)
        #expect(Set(enabled) == [
            .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .maximize, .leftThird, .centerThird, .rightThird,
        ])
    }

    /// KeyboardShortcuts は名前の文字列をキーに UserDefaults へ保存する。
    /// 既存ユーザーのキー割当を引き継ぐため、MVP の名前と一致していなければならない。
    @Test func 既存8コマンドのrawValueはMVPのKeyboardShortcuts名と一致する() {
        #expect(SnapCommand.cycleLeft.rawValue == "cycleLeft")
        #expect(SnapCommand.cycleRight.rawValue == "cycleRight")
        #expect(SnapCommand.topHalf.rawValue == "topHalf")
        #expect(SnapCommand.bottomHalf.rawValue == "bottomHalf")
        #expect(SnapCommand.maximize.rawValue == "maximize")
        #expect(SnapCommand.leftThird.rawValue == "leftThird")
        #expect(SnapCommand.centerThird.rawValue == "centerThird")
        #expect(SnapCommand.rightThird.rawValue == "rightThird")
    }

    @Test func rawValueは重複しない() {
        #expect(Set(SnapCommand.allCases.map(\.rawValue)).count == SnapCommand.allCases.count)
    }

    @Test func 左ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleLeft.sequence == [.leftHalf, .leftThird, .leftTwoThirds])
        #expect(SnapCommand.cycleLeft.isCycle)
    }

    @Test func 右ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleRight.sequence == [.rightHalf, .rightThird, .rightTwoThirds])
        #expect(SnapCommand.cycleRight.isCycle)
    }

    @Test func ループ系は左右の2つだけ() {
        #expect(SnapCommand.allCases.filter(\.isCycle) == [.cycleLeft, .cycleRight])
    }

    @Test(arguments: SnapCommand.allCases.filter { !$0.isCycle })
    func 単発コマンドの系列は1要素(command: SnapCommand) {
        #expect(command.sequence.count == 1)
    }

    @Test(arguments: [
        (SnapCommand.topHalf, SnapAction.topHalf),
        (SnapCommand.maximize, SnapAction.maximize),
        (SnapCommand.secondFourth, SnapAction.secondFourth),
        (SnapCommand.bottomRightQuarter, SnapAction.bottomRightQuarter),
        (SnapCommand.topCenterSixth, SnapAction.topCenterSixth),
        (SnapCommand.center, SnapAction.center),
    ])
    func 単発コマンドは同名の区画に対応する(command: SnapCommand, action: SnapAction) {
        #expect(command.sequence == [action])
    }

    @Test func 表示名は空でなく重複しない() {
        let titles = SnapCommand.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }
}
```

`TatamiTests/SnapEngineTests.swift` に追加（FakeWindowService の初期枠は AX (0, 0, 800, 600)。NS に直すと y = 1080 - 600 = 480）:

```swift
    @Test func 中央に配置は大きさを保ってvisibleFrameの中央に置く() {
        let engine = makeEngine()
        engine.perform(.center)
        // NS: x = 960 - 400 = 560, y = 45 + 505 - 300 = 250 → AX: y = 1080 - (250 + 600) = 230
        #expect(windows.setFrameCalls == [CGRect(x: 560, y: 230, width: 800, height: 600)])
    }

    @Test func 高さを最大化は幅を保って縦いっぱいにする() {
        let engine = makeEngine()
        engine.perform(.maximizeHeight)
        // NS: (0, 45, 800, 1010) → AX: y = 1080 - (45 + 1010) = 25
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 25, width: 800, height: 1010)])
    }
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`SnapCommandTests`）。
Expected: コンパイルエラー（`category`、`Category`、`SnapCommand.center` などの新しい case が未定義）。

- [ ] **Step 3: SnapCommand を書き換え、ShortcutRegistrar から title を外す**

`Tatami/Model/SnapCommand.swift` を全体として次にする:

```swift
import Foundation

/// ショートカット 1 つに対応するコマンド。
/// ループ系は複数の区画を順に巡り、単発系は 1 つの区画に固定される。
///
/// rawValue は KeyboardShortcuts の名前と有効/無効の保存キーに使う。
/// 既存 8 コマンドの rawValue は MVP の `KeyboardShortcuts.Name` と同じ文字列にしてあり、
/// ユーザーが変更済みのキー割当を引き継ぐ。変更してはならない。
enum SnapCommand: String, CaseIterable, Sendable {
    // 半分
    case cycleLeft
    case cycleRight
    case topHalf
    case bottomHalf
    // 1/3
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    // 1/4
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    // 四隅
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // 1/6
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    // サイズ
    case maximize
    case maximizeHeight
    case maximizeWidth
    case center

    /// 設定画面のタブに対応する分類。allCases の順がタブの順。
    enum Category: CaseIterable, Sendable {
        case halves
        case thirds
        case fourths
        case quarters
        case sixths
        case size
    }

    /// このコマンドが巡る区画の系列。単発系は 1 要素。
    var sequence: [SnapAction] {
        switch self {
        case .cycleLeft: [.leftHalf, .leftThird, .leftTwoThirds]
        case .cycleRight: [.rightHalf, .rightThird, .rightTwoThirds]
        case .topHalf: [.topHalf]
        case .bottomHalf: [.bottomHalf]
        case .leftThird: [.leftThird]
        case .centerThird: [.centerThird]
        case .rightThird: [.rightThird]
        case .leftTwoThirds: [.leftTwoThirds]
        case .rightTwoThirds: [.rightTwoThirds]
        case .firstFourth: [.firstFourth]
        case .secondFourth: [.secondFourth]
        case .thirdFourth: [.thirdFourth]
        case .lastFourth: [.lastFourth]
        case .topLeftQuarter: [.topLeftQuarter]
        case .topRightQuarter: [.topRightQuarter]
        case .bottomLeftQuarter: [.bottomLeftQuarter]
        case .bottomRightQuarter: [.bottomRightQuarter]
        case .topLeftSixth: [.topLeftSixth]
        case .topCenterSixth: [.topCenterSixth]
        case .topRightSixth: [.topRightSixth]
        case .bottomLeftSixth: [.bottomLeftSixth]
        case .bottomCenterSixth: [.bottomCenterSixth]
        case .bottomRightSixth: [.bottomRightSixth]
        case .maximize: [.maximize]
        case .maximizeHeight: [.maximizeHeight]
        case .maximizeWidth: [.maximizeWidth]
        case .center: [.center]
        }
    }

    /// 押すたびに区画が切り替わるループ系か。
    var isCycle: Bool { sequence.count > 1 }

    var category: Category {
        switch self {
        case .cycleLeft, .cycleRight, .topHalf, .bottomHalf: .halves
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth: .fourths
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter: .quarters
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: .sixths
        case .maximize, .maximizeHeight, .maximizeWidth, .center: .size
        }
    }

    /// 設定画面に表示するラベル。
    var title: String {
        switch self {
        case .cycleLeft: "左半分 → 左 1/3 → 左 2/3"
        case .cycleRight: "右半分 → 右 1/3 → 右 2/3"
        case .topHalf: "上半分"
        case .bottomHalf: "下半分"
        case .leftThird: "左 1/3"
        case .centerThird: "中央 1/3"
        case .rightThird: "右 1/3"
        case .leftTwoThirds: "左 2/3"
        case .rightTwoThirds: "右 2/3"
        case .firstFourth: "左 1/4"
        case .secondFourth: "左から 2 番目の 1/4"
        case .thirdFourth: "左から 3 番目の 1/4"
        case .lastFourth: "右 1/4"
        case .topLeftQuarter: "左上"
        case .topRightQuarter: "右上"
        case .bottomLeftQuarter: "左下"
        case .bottomRightQuarter: "右下"
        case .topLeftSixth: "左上 1/6"
        case .topCenterSixth: "中央上 1/6"
        case .topRightSixth: "右上 1/6"
        case .bottomLeftSixth: "左下 1/6"
        case .bottomCenterSixth: "中央下 1/6"
        case .bottomRightSixth: "右下 1/6"
        case .maximize: "最大化"
        case .maximizeHeight: "高さを最大化"
        case .maximizeWidth: "幅を最大化"
        case .center: "中央に配置"
        }
    }

    /// 初回起動（設定なし）で有効か。MVP にあった 8 コマンドだけ true。
    var isEnabledByDefault: Bool {
        switch self {
        case .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .maximize, .leftThird, .centerThird, .rightThird:
            true
        default:
            false
        }
    }
}

extension SnapCommand.Category {
    /// タブに表示する名前。
    var title: String {
        switch self {
        case .halves: "半分"
        case .thirds: "1/3"
        case .fourths: "1/4"
        case .quarters: "四隅"
        case .sixths: "1/6"
        case .size: "サイズ"
        }
    }

    /// このカテゴリのコマンド。`SnapCommand.allCases` の順。
    var commands: [SnapCommand] {
        SnapCommand.allCases.filter { $0.category == self }
    }
}
```

`Tatami/App/ShortcutRegistrar.swift` から `var title: String { ... }` のブロック（「設定画面に表示するラベル。」のコメントを含む）を削除する。`shortcutName` の switch は 8 case のままだと exhaustive でなくなるので、末尾に次を足しておく（新しいコマンドは既定キーなしの名前になり、起動してもクラッシュしない。Task 5 でファイルごと書き直す）:

```swift
        default: KeyboardShortcuts.Name(rawValue)
        }
```

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`SnapCommandTests`）。続けて `SnapEngineTests`（Task 2 で足した 2 本を含む）と `CycleResolverTests` も実行する。
Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/Model/SnapCommand.swift Tatami/App/ShortcutRegistrar.swift TatamiTests/SnapCommandTests.swift TatamiTests/SnapEngineTests.swift
git commit -m "feat: expand SnapCommand to 27 commands with categories and default-enabled flags

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: CommandSettings（有効/無効の保存）

**Files:**
- Create: `Tatami/App/CommandSettings.swift`
- Test: `TatamiTests/CommandSettingsTests.swift`（新規）

**Interfaces:**
- Consumes: Task 3 の `SnapCommand`（`rawValue`, `isEnabledByDefault`, `allCases`）。
- Produces:
  ```swift
  @MainActor @Observable final class CommandSettings {
      init(defaults: UserDefaults = .standard)
      var onChange: ((SnapCommand, Bool) -> Void)?
      func isEnabled(_ command: SnapCommand) -> Bool
      func setEnabled(_ enabled: Bool, for command: SnapCommand)
      var enabledCommands: [SnapCommand]
      static func key(for command: SnapCommand) -> String   // "command.<rawValue>.enabled"
  }
  ```

- [ ] **Step 1: テストを書く**

`TatamiTests/CommandSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Tatami

/// テストごとに別の suite 名の UserDefaults を使い、終了時に消す。
@MainActor
final class CommandSettingsTests {
    let suiteName = "dev.hidekingerz.tatamiTests.CommandSettings.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func 設定がなければ既定値を返す() {
        let settings = CommandSettings(defaults: defaults)
        #expect(settings.isEnabled(.cycleLeft))
        #expect(settings.isEnabled(.maximize))
        #expect(!settings.isEnabled(.topLeftQuarter))
        #expect(!settings.isEnabled(.center))
        #expect(settings.enabledCommands == [
            .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .leftThird, .centerThird, .rightThird, .maximize,
        ])
    }

    @Test func 保存キーはcommand_rawValue_enabled() {
        #expect(CommandSettings.key(for: .topLeftQuarter) == "command.topLeftQuarter.enabled")
    }

    @Test func 変更は読み戻せる() {
        let settings = CommandSettings(defaults: defaults)
        settings.setEnabled(true, for: .topLeftQuarter)
        settings.setEnabled(false, for: .maximize)
        #expect(settings.isEnabled(.topLeftQuarter))
        #expect(!settings.isEnabled(.maximize))
        #expect(defaults.bool(forKey: "command.topLeftQuarter.enabled"))
        #expect(defaults.object(forKey: "command.maximize.enabled") as? Bool == false)
    }

    @Test func 別インスタンスでも同じUserDefaultsなら同じ値() {
        CommandSettings(defaults: defaults).setEnabled(true, for: .center)
        let reloaded = CommandSettings(defaults: defaults)
        #expect(reloaded.isEnabled(.center))
        #expect(reloaded.enabledCommands.contains(.center))
    }

    /// キーが未設定でも有効/無効は独立して保存される（キーは KeyboardShortcuts が別に持つ）。
    @Test func キーの有無に関係なく保存される() {
        let settings = CommandSettings(defaults: defaults)
        settings.setEnabled(true, for: .bottomCenterSixth)
        #expect(settings.isEnabled(.bottomCenterSixth))
    }

    @Test func 変更するとonChangeが呼ばれる() {
        let settings = CommandSettings(defaults: defaults)
        var received: [(SnapCommand, Bool)] = []
        settings.onChange = { received.append(($0, $1)) }
        settings.setEnabled(true, for: .firstFourth)
        settings.setEnabled(false, for: .firstFourth)
        #expect(received.map(\.0) == [.firstFourth, .firstFourth])
        #expect(received.map(\.1) == [true, false])
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`CommandSettingsTests`）。
Expected: コンパイルエラー（`CommandSettings` が未定義）。

- [ ] **Step 3: 実装する**

`Tatami/App/CommandSettings.swift`:

```swift
// Tatami/App/CommandSettings.swift
import Foundation
import Observation

/// コマンドごとの有効/無効。UserDefaults に `command.<rawValue>.enabled` で保存する。
///
/// キー割当そのものは KeyboardShortcuts が別に保存しているので、ここでは触らない。
/// 無効にしてもキー割当は残り、再び有効にすれば同じキーで動く。
@MainActor
@Observable
final class CommandSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// 有効/無効が変わったときに呼ばれる。ShortcutRegistrar がホットキーの登録・解除に使う。
    @ObservationIgnored var onChange: ((SnapCommand, Bool) -> Void)?

    /// 観測用の写し。setEnabled のたびに更新し、設定画面の再描画を起こす。
    private var enabled: [SnapCommand: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Dictionary(uniqueKeysWithValues: SnapCommand.allCases.map { command in
            (command, Self.read(command, from: defaults))
        })
    }

    func isEnabled(_ command: SnapCommand) -> Bool {
        enabled[command] ?? command.isEnabledByDefault
    }

    func setEnabled(_ value: Bool, for command: SnapCommand) {
        defaults.set(value, forKey: Self.key(for: command))
        enabled[command] = value
        onChange?(command, value)
    }

    /// 有効なコマンド。`SnapCommand.allCases` の順。
    var enabledCommands: [SnapCommand] {
        SnapCommand.allCases.filter(isEnabled)
    }

    static func key(for command: SnapCommand) -> String {
        "command.\(command.rawValue).enabled"
    }

    /// 保存がなければ `isEnabledByDefault`。これで初回起動は MVP の 8 コマンドだけが有効になる。
    private static func read(_ command: SnapCommand, from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(for: command)) as? Bool ?? command.isEnabledByDefault
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`CommandSettingsTests`）。
Expected: 6 本すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App/CommandSettings.swift TatamiTests/CommandSettingsTests.swift
git commit -m "feat: persist per-command enabled state in CommandSettings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: ShortcutRegistrar を 27 コマンドと有効/無効に対応させ、AppModel に配線する

**Files:**
- Modify: `Tatami/App/ShortcutRegistrar.swift`（全面書き換え）
- Modify: `Tatami/App/AppModel.swift`

**Interfaces:**
- Consumes: Task 3 の `SnapCommand`、Task 4 の `CommandSettings`、`SnapEngine.perform(_:)`。
- Produces:
  ```swift
  extension SnapCommand {
      var defaultShortcut: KeyboardShortcuts.Shortcut?        // 既存 8 個だけ非 nil
      @MainActor var shortcutName: KeyboardShortcuts.Name     // Name(rawValue, default: defaultShortcut)、キャッシュ付き
  }
  @MainActor enum ShortcutRegistrar {
      static func register(engine: SnapEngine, settings: CommandSettings)
      static func setEnabled(_ enabled: Bool, for command: SnapCommand)
  }
  final class AppModel { let settings: CommandSettings /* 追加 */ }
  ```

KeyboardShortcuts は Carbon のホットキー登録に依存するので単体テストは書かない。この Task の検証はビルドが通ることと、Task 7 の実機確認で行う。

- [ ] **Step 1: ShortcutRegistrar を書き換える**

`Tatami/App/ShortcutRegistrar.swift` を全体として次にする:

```swift
// Tatami/App/ShortcutRegistrar.swift
import AppKit
import KeyboardShortcuts

extension SnapCommand {
    /// 既定キー。MVP の 8 コマンドだけが持ち、新しいコマンドはユーザーが記録するまでキーなし。
    var defaultShortcut: KeyboardShortcuts.Shortcut? {
        switch self {
        case .cycleLeft: .init(.b, modifiers: [.control, .option])
        case .cycleRight: .init(.f, modifiers: [.control, .option])
        case .topHalf: .init(.p, modifiers: [.control, .option])
        case .bottomHalf: .init(.n, modifiers: [.control, .option])
        case .maximize: .init(.m, modifiers: [.control, .option])
        case .leftThird: .init(.z, modifiers: [.control, .option])
        case .centerThird: .init(.x, modifiers: [.control, .option])
        case .rightThird: .init(.c, modifiers: [.control, .option])
        default: nil
        }
    }

    /// KeyboardShortcuts に登録する名前。rawValue をそのまま使うので、MVP からのキー割当を引き継ぐ。
    @MainActor
    var shortcutName: KeyboardShortcuts.Name {
        ShortcutNames.name(for: self)
    }
}

/// `KeyboardShortcuts.Name` をコマンドごとに 1 度だけ作るためのキャッシュ。
@MainActor
private enum ShortcutNames {
    private static var cache: [SnapCommand: KeyboardShortcuts.Name] = [:]

    static func name(for command: SnapCommand) -> KeyboardShortcuts.Name {
        if let cached = cache[command] {
            return cached
        }
        let name = KeyboardShortcuts.Name(command.rawValue, default: command.defaultShortcut)
        cache[command] = name
        return name
    }
}

/// すべてのショートカットを SnapEngine に接続し、有効/無効をホットキーの登録に反映する。
@MainActor
enum ShortcutRegistrar {
    /// 全コマンドのハンドラを登録し、無効なものはホットキーを解除する。
    /// `onKeyDown` はキーが割り当て済みならその場で登録するので、解除はその直後に行う。
    static func register(engine: SnapEngine, settings: CommandSettings) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                engine.perform(command)
            }
        }
        let disabled = SnapCommand.allCases.filter { !settings.isEnabled($0) }
        KeyboardShortcuts.disable(disabled.map(\.shortcutName))
        settings.onChange = { command, enabled in
            setEnabled(enabled, for: command)
        }
    }

    /// 有効ならホットキーを登録し、無効なら解除する。キーが未割当なら KeyboardShortcuts 側で何もしない。
    static func setEnabled(_ enabled: Bool, for command: SnapCommand) {
        if enabled {
            KeyboardShortcuts.enable(command.shortcutName)
        } else {
            KeyboardShortcuts.disable(command.shortcutName)
        }
    }
}
```

- [ ] **Step 2: AppModel に CommandSettings を持たせる**

`Tatami/App/AppModel.swift` の `@ObservationIgnored let engine: SnapEngine` の直後に追加:

```swift
    @ObservationIgnored let settings = CommandSettings()
```

`start()` の `ShortcutRegistrar.register(engine: engine)` を次に置き換える:

```swift
        ShortcutRegistrar.register(engine: engine, settings: settings)
```

- [ ] **Step 3: ビルドが通ることを確認する**

`SettingsView` はまだ `KeyboardShortcuts.Recorder(command.title, name: command.shortcutName)` を使っており、`shortcutName` が `@MainActor` になっても View の body は MainActor なので通る。

```bash
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning: .*ShortcutRegistrar|BUILD" | tail -20
```

Expected: `** BUILD SUCCEEDED **`。エラーなし。

- [ ] **Step 4: 全テストが通ることを確認する**

テスト実行（`-only-testing:` なし）。
Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App/ShortcutRegistrar.swift Tatami/App/AppModel.swift
git commit -m "feat: register all 27 shortcuts and honor per-command enabled state

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: RegionGlyph（区画グリフ）

**Files:**
- Create: `Tatami/App/RegionGlyph.swift`
- Modify: `docs/superpowers/specs/2026-10-10-raycast-layouts-and-toggles-design.md`（§4.3 の基準矩形）
- Test: `TatamiTests/RegionGlyphTests.swift`（新規）

**Interfaces:**
- Consumes: Task 2 の `LayoutCalculator.frame(for:in:current:)`、Task 3 の `SnapCommand.Category.commands`。
- Produces:
  ```swift
  struct RegionGlyph: View {
      init(action: SnapAction, isEnabled: Bool = true)
      static let referenceScreen: CGRect     // (0, 0, 1200, 600)
      static let sampleWindow: CGRect        // (300, 120, 600, 360)
      /// 0...1 に正規化した区画。NS 座標（左下原点）。
      static func normalizedRegion(for action: SnapAction) -> CGRect
      /// タブのアイコン用に描画した画像。カテゴリの先頭コマンドの区画。
      @MainActor static func tabImage(for category: SnapCommand.Category) -> NSImage
  }
  ```

設計書 §4.3 は「単位矩形を渡す」と書いているが、`LayoutCalculator` は幅を `floor` するので単位矩形では 0 になる。
2・3・4 で割り切れる 1200 × 600 を基準にして結果を正規化する。設計書もそのように直す。

- [ ] **Step 1: テストを書く**

`TatamiTests/RegionGlyphTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tatami

struct RegionGlyphTests {
    @Test func 左半分は左側の半分() {
        #expect(RegionGlyph.normalizedRegion(for: .leftHalf) == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func 右上の四隅は右上() {
        #expect(RegionGlyph.normalizedRegion(for: .topRightQuarter) == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test func 中央に配置は代表枠を中央に置いた形() {
        #expect(RegionGlyph.normalizedRegion(for: .center) == CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6))
    }

    @Test func 高さを最大化は縦長_幅を最大化は横長() {
        let tall = RegionGlyph.normalizedRegion(for: .maximizeHeight)
        let wide = RegionGlyph.normalizedRegion(for: .maximizeWidth)
        #expect(tall == CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        #expect(wide == CGRect(x: 0, y: 0.2, width: 1, height: 0.6))
    }

    @Test(arguments: SnapAction.allCases)
    func 全区画が0から1の範囲に収まり空でない(action: SnapAction) {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let region = RegionGlyph.normalizedRegion(for: action)
        #expect(unit.contains(region), "\(action): \(region)")
        #expect(region.width > 0 && region.height > 0)
    }
}
```

- [ ] **Step 2: テストが落ちることを確認する**

テスト実行（`RegionGlyphTests`）。
Expected: コンパイルエラー（`RegionGlyph` が未定義）。

- [ ] **Step 3: 実装する**

`Tatami/App/RegionGlyph.swift`:

```swift
// Tatami/App/RegionGlyph.swift
import AppKit
import SwiftUI

/// 画面の中のどこに置かれるかを示す小さな図。
/// 形は LayoutCalculator から得るので、計算と表示が必ず一致する。
struct RegionGlyph: View {
    let action: SnapAction
    var isEnabled = true

    /// 形を求めるときの基準画面。LayoutCalculator は幅を floor するので、2・3・4 で割り切れる大きさにする。
    static let referenceScreen = CGRect(x: 0, y: 0, width: 1200, height: 600)
    /// サイズ系コマンド用の代表的な現在枠（中央に置いた 0.5 × 0.6）。
    static let sampleWindow = CGRect(x: 300, y: 120, width: 600, height: 360)

    /// 0...1 に正規化した区画。NS 座標（左下原点）。
    static func normalizedRegion(for action: SnapAction) -> CGRect {
        let frame = LayoutCalculator.frame(for: action, in: referenceScreen, current: sampleWindow)
        return CGRect(
            x: frame.minX / referenceScreen.width,
            y: frame.minY / referenceScreen.height,
            width: frame.width / referenceScreen.width,
            height: frame.height / referenceScreen.height
        )
    }

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(Path(roundedRect: screen, cornerRadius: 2), with: .color(strokeColor), lineWidth: 1)

            let region = Self.normalizedRegion(for: action)
            // NS 座標は下が原点なので、描画時に上下を反転する。
            let rect = CGRect(
                x: screen.minX + region.minX * screen.width,
                y: screen.minY + (1 - region.maxY) * screen.height,
                width: region.width * screen.width,
                height: region.height * screen.height
            ).insetBy(dx: 1, dy: 1)
            context.fill(Path(rect), with: .color(fillColor))
        }
        .frame(width: 24, height: 15)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        isEnabled ? .accentColor : Color(nsColor: .tertiaryLabelColor)
    }

    private var strokeColor: Color {
        isEnabled ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .tertiaryLabelColor)
    }
}

extension RegionGlyph {
    @MainActor private static var tabImages: [SnapCommand.Category: NSImage] = [:]

    /// タブのアイコン。カテゴリの先頭コマンドの区画をテンプレート画像にして、システムが色を付ける。
    @MainActor
    static func tabImage(for category: SnapCommand.Category) -> NSImage {
        if let cached = tabImages[category] {
            return cached
        }
        let action = category.commands[0].sequence[0]
        let renderer = ImageRenderer(content: RegionGlyph(action: action))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 24, height: 15))
        image.isTemplate = true
        tabImages[category] = image
        return image
    }
}
```

設計書 `docs/superpowers/specs/2026-10-10-raycast-layouts-and-toggles-design.md` §4.3 の 2 つ目の箇条書きを次に置き換える:

```markdown
- 区画の形は `LayoutCalculator.frame(for: action, in: reference, current: sample)` を基準画面の大きさで割って 0...1 に正規化して得る。
  `reference` は `CGRect(x: 0, y: 0, width: 1200, height: 600)`（LayoutCalculator は幅を floor するので、2・3・4 で割り切れる大きさにする）。
  サイズ系には代表的な現在枠 `sample = CGRect(x: 300, y: 120, width: 600, height: 360)` を渡し、
  「高さを最大化」なら縦長、「幅を最大化」なら横長、「中央に配置」なら中央の矩形として描かれる。
```

- [ ] **Step 4: テストが通ることを確認する**

テスト実行（`RegionGlyphTests`）。
Expected: すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App/RegionGlyph.swift TatamiTests/RegionGlyphTests.swift docs/superpowers/specs/2026-10-10-raycast-layouts-and-toggles-design.md
git commit -m "feat: add RegionGlyph that draws a command's region from LayoutCalculator

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: 設定画面をカテゴリタブ + トグル付きの行にする

**Files:**
- Modify: `Tatami/App/SettingsView.swift`（全面書き換え）
- Modify: `Tatami/App/TatamiApp.swift`

**Interfaces:**
- Consumes: Task 3 の `SnapCommand.Category`、`SnapCommand.title / isCycle / sequence`、Task 4 の `CommandSettings`、Task 5 の `shortcutName`、Task 6 の `RegionGlyph` と `RegionGlyph.tabImage(for:)`。
- Produces: `SettingsView(settings: CommandSettings)`、`CommandListTab`、`CommandRow`。

SwiftUI と KeyboardShortcuts の Recorder に依存するので単体テストは書かない。検証はビルドと実機確認。

- [ ] **Step 1: SettingsView を書き換える**

`Tatami/App/SettingsView.swift` を全体として次にする:

```swift
// Tatami/App/SettingsView.swift
import KeyboardShortcuts
import SwiftUI

/// コマンドの有効/無効とショートカットを変更する設定画面。カテゴリごとにタブを分ける。
/// キーの保存は KeyboardShortcuts が、有効/無効の保存は CommandSettings が UserDefaults に行う。
struct SettingsView: View {
    let settings: CommandSettings

    var body: some View {
        TabView {
            ForEach(SnapCommand.Category.allCases, id: \.self) { category in
                CommandListTab(category: category, settings: settings)
                    .tabItem {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(nsImage: RegionGlyph.tabImage(for: category))
                        }
                    }
            }
        }
        .frame(width: 480)
    }
}

/// 1 カテゴリ分のコマンド一覧。
struct CommandListTab: View {
    let category: SnapCommand.Category
    let settings: CommandSettings

    var body: some View {
        Form {
            Section {
                ForEach(category.commands, id: \.self) { command in
                    CommandRow(command: command, settings: settings)
                }
            } header: {
                HStack {
                    Text(category.title)
                    Spacer()
                    Text("\(enabledCount) / \(category.commands.count) を使用中")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var enabledCount: Int {
        category.commands.filter(settings.isEnabled).count
    }
}

/// 1 コマンド分の行: トグル / 区画グリフ / 名前 / キーのレコーダー。
///
/// 無効のときは Recorder を操作不可にする。KeyboardShortcuts はキーを記録した時点でホットキーを登録するので、
/// 無効中に記録できると「無効なのに効く」状態になる。
struct CommandRow: View {
    let command: SnapCommand
    let settings: CommandSettings

    var body: some View {
        let isOn = settings.isEnabled(command)
        HStack(spacing: 10) {
            Toggle(command.title, isOn: Binding(
                get: { settings.isEnabled(command) },
                set: { settings.setEnabled($0, for: command) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            RegionGlyph(action: command.sequence[0], isEnabled: isOn)

            Text(command.isCycle ? "\(command.title) ⟳" : command.title)
                .foregroundStyle(isOn ? .primary : .secondary)

            Spacer()

            KeyboardShortcuts.Recorder(for: command.shortcutName)
                .disabled(!isOn)
        }
    }
}
```

- [ ] **Step 2: TatamiApp から settings を渡す**

`Tatami/App/TatamiApp.swift` の `Settings { SettingsView() }` を次に置き換える:

```swift
        Settings {
            SettingsView(settings: model.settings)
        }
```

- [ ] **Step 3: ビルドと全テストが通ることを確認する**

```bash
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`。続けてテスト実行（`-only-testing:` なし）で全 PASS。

- [ ] **Step 4: 実機で確認する**

ビルドしたアプリ（`~/Library/Developer/Xcode/DerivedData/Tatami-*/Build/Products/Debug/Tatami.app`）を起動し、メニューバー → 設定… を開いて次を確認する。確認できない項目があればそのまま報告する（勝手に省略しない）。

1. タブが「半分 / 1/3 / 1/4 / 四隅 / 1/6 / サイズ」の順に並び、アイコンが各カテゴリの区画の形になっている。
2. 初回起動（`defaults delete dev.hidekingerz.tatami` で設定を消した状態）で、有効なのが既存 8 コマンドだけ。半分タブの見出しが「4 / 4 を使用中」、四隅タブが「0 / 4 を使用中」。
3. 四隅タブで「左上」をオンにし、Recorder で ⌃⌥u を記録 → 任意のアプリで ⌃⌥u を押すと左上 1/4 になる。
4. 「左上」をオフにする → ⌃⌥u が tatami に奪われない（例: テキストエディタで何も起きない、または他アプリの割当が効く）。Recorder はグレーで操作できない。
5. 再びオンにする → キーの再記録なしで ⌃⌥u が効く。
6. tatami を終了して起動し直す → 「左上」がオンのまま、キーも残っている。
7. 「サイズ」タブで「中央に配置」をオンにしてキーを記録 → ウィンドウの大きさが変わらず中央に移動する。
8. 既存の ⌃⌥b / ⌃⌥f / ⌃⌥p / ⌃⌥n / ⌃⌥m / ⌃⌥z / ⌃⌥x / ⌃⌥c が変更前と同じ動作をする。

- [ ] **Step 5: コミット**

```bash
git add Tatami/App/SettingsView.swift Tatami/App/TatamiApp.swift
git commit -m "feat: tabbed settings with per-command toggles and region glyphs

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: README の更新

**Files:**
- Modify: `README.md`（「## ショートカット」セクション）

**Interfaces:** なし（ドキュメントのみ）。

- [ ] **Step 1: ショートカットのセクションを書き換える**

`README.md` の `## ショートカット` から `## ビルド` の直前までを次に置き換える:

```markdown
## ショートカット

Raycast の Window Management と同じ区画が使えます。コマンドは設定画面（メニューバー → 設定…）でカテゴリごとに一覧になっていて、使うものだけをオンにします。オフのコマンドはキーを登録しないので、他のアプリの同じキーを奪いません。

初期状態では次の 8 つだけがオンです。修飾キーはすべて ⌃⌥（Control + Option）で、キーは設定画面から変更できます。

| キー | 動作 |
|---|---|
| ⌃⌥b | 左半分 → 左 1/3 → 左 2/3 →（ループ） |
| ⌃⌥f | 右半分 → 右 1/3 → 右 2/3 →（ループ） |
| ⌃⌥p | 上半分 |
| ⌃⌥n | 下半分 |
| ⌃⌥m | 最大化 |
| ⌃⌥z | 左 1/3 |
| ⌃⌥x | 中央 1/3 |
| ⌃⌥c | 右 1/3 |

次のコマンドは初期状態ではオフで、キーも割り当てられていません。設定画面でオンにしてキーを記録すると使えます。

| カテゴリ | コマンド |
|---|---|
| 1/3 | 左 2/3、右 2/3 |
| 1/4 | 左 1/4、左から 2 番目の 1/4、左から 3 番目の 1/4、右 1/4 |
| 四隅 | 左上、右上、左下、右下 |
| 1/6 | 左上 1/6、中央上 1/6、右上 1/6、左下 1/6、中央下 1/6、右下 1/6 |
| サイズ | 高さを最大化（幅はそのまま）、幅を最大化（高さはそのまま）、中央に配置（大きさはそのまま） |

いったんオフにしてもキーの割り当ては残るので、再びオンにすれば同じキーで動きます。

```

- [ ] **Step 2: 表示を確認する**

```bash
sed -n '/^## ショートカット/,/^## ビルド/p' README.md
```

Expected: 2 つの表が崩れていない。`## ビルド` 見出しが残っている。

- [ ] **Step 3: コミット**

```bash
git add README.md
git commit -m "docs: describe the 27 commands and per-command toggles in README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 完了条件

- 全テストが `xcodebuild ... test` で PASS。
- Task 7 Step 4 の実機確認 8 項目がすべて通る（通らない項目は報告する）。
- `git log` に Task 1〜8 のコミットが並んでいる。
