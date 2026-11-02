# ピッカーからの区画適用 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** レイアウトセットのピッカーに 27 区画を並べ、英語・ローマ字・記号の別名で探して、開く直前に最前面だったウィンドウへ ⏎ で適用できるようにする。開いている間は入力ソースを ABC にし、★ を付けた区画を先頭に出す。

**Architecture:** 純粋なモデル（`PickerItem` / `PickerSection` / `PickerQuery` / `SnapAction.searchTerms`）で一覧と絞り込みを決め、`PickerState.sections` がそれを組み立てる。実行は `SnapEngine` に「開く直前の窓を記憶して、あとで区画を適用する」口を足して `WindowPlacer` を再利用する。入力ソースは `InputSourceSwitching`（Carbon TIS 実装 + フェイク）で、選び方だけ純粋関数 `InputSourcePolicy` に切り出す。★ は `FavoriteRegions`（UserDefaults）。UI は `PickerView` / `PickerPanel` / `CommandRow` / `MenuBarView` の拡張。

**Tech Stack:** Swift 6 / SwiftUI / AppKit / Carbon.HIToolbox（TIS）/ KeyboardShortcuts 2.4.0 / Swift Testing。macOS 26。

**Spec:** `docs/superpowers/specs/2026-11-02-picker-regions-design.md`

## Global Constraints

- `SnapAction` と `SnapCommand` の rawValue（ケース名）は変更しない（保存互換）。
- 既存 27 コマンドのホットキー登録、`CommandSettings` の保存キー、`layoutSets.v1` の形式には触れない。
- UserDefaults の新規キーは `picker.favoriteRegions`（`[String]`、`SnapAction.rawValue`）だけ。
- テストは Swift Testing（`@Test`、`#expect`）。テスト名は日本語でよいが Swift の識別子として有効なものにする（数字で始めない、`/` `-` を使わない）。
- UserDefaults を使うテストは `LayoutSetStoreTests` と同じく suite ごとの `UserDefaults(suiteName:)` を使い、`deinit` で消す。
- 文言（コピー）は仕様のとおり: プレースホルダ「セットや区画を検索…」、件数「N 件」、空「一致する項目はありません」、
  ヒント「⏎ 適用  ↑↓ 選択  →← 内訳  ⌘D ★  ⌘⏎ 編集  esc 閉じる」、HUD「対象のウィンドウがありません」「ウィンドウを動かせませんでした」、
  メニュー「ピッカー…」、★ の help「★ を付ける／外す」（ピッカー）「ピッカーの先頭に出す」（設定）。
- `import Carbon.HIToolbox` は System 層の `InputSourceSwitcher.swift` だけ。テストターゲットから Carbon 実装は呼ばない。
- 全テスト: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test`。
  1 ファイルだけなら `-only-testing:TatamiTests/<SuiteName>` を付ける。

## Review Focus

1. 入力ソースを切り替えたまま戻し忘れる経路（esc、⌘⏎、フォーカス喪失、適用）。→ Task 6 の `FakeInputSourceSwitcher` と Task 8 の「閉じる経路を `dismiss` 1 か所に集める」実装、§8-2 の実機確認。
2. 古い対象ウィンドウへの適用（前回の窓が残る）。→ Task 7 のテスト「取れなければ nil に戻す」「閉じたら forget」。
3. ★ の保存に未知の rawValue が混ざってクラッシュ／全滅する。→ Task 5 のテスト「未知の値を捨てる」。
4. 別名の前方一致が広すぎて、`l` で右 1/4（last）が残る、`c` で中央系以外が残る。→ Task 3 のテスト「`l` に右 1/4 は含まれない」。
5. 選択位置がセクションをまたいでずれる（セットが 0 件のとき区画の先頭が index 0 になる）。→ Task 4 のテスト「セット 0 件で区画だけ」「flatten の順」。

---

### Task 1: 区画の並びと単発コマンドの対応（モデル）

**Files:**
- Modify: `Tatami/Model/SnapCommand.swift`（`Category.actions`、`SnapAction.allInCategoryOrder`、`SnapAction.singleCommand`）
- Modify: `Tatami/App/LayoutSetsTab.swift`（末尾の `private extension SnapCommand.Category { var actions }` を削除）
- Test: `TatamiTests/SnapCommandTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension SnapCommand.Category { var actions: [SnapAction] }          // commands.map { $0.sequence[0] }
  extension SnapAction {
      static var allInCategoryOrder: [SnapAction]                       // Category.allCases.flatMap(\.actions)
      var singleCommand: SnapCommand?                                   // SnapCommand.allCases.first { $0.sequence == [self] }
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**（`SnapCommandTests.swift` に追加）

```swift
@Test func カテゴリ順の区画は27個が1回ずつ() {
    let all = SnapAction.allInCategoryOrder
    #expect(all.count == 27)
    #expect(Set(all).count == 27)
    #expect(all.prefix(5) == [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .leftThird])
    #expect(all.suffix(4) == [.maximize, .maximizeHeight, .maximizeWidth, .center])
}

@Test func 単発コマンドは自分だけを持つコマンド() {
    #expect(SnapAction.leftHalf.singleCommand == nil)
    #expect(SnapAction.rightHalf.singleCommand == nil)
    #expect(SnapAction.leftThird.singleCommand == .leftThird)
    #expect(SnapAction.center.singleCommand == .center)
    for action in SnapAction.allCases where action != .leftHalf && action != .rightHalf {
        #expect(action.singleCommand?.sequence == [action])
    }
}
```

- [ ] **Step 2: 失敗を確認** — `xcodebuild … test -only-testing:TatamiTests/SnapCommandTests`。コンパイルエラー（`allInCategoryOrder` 未定義）で失敗。
- [ ] **Step 3: 実装** — `SnapCommand.swift` の末尾に上の 3 つを足す。`LayoutSetsTab.swift` の private 拡張を削除し、参照（`category.actions`）はそのまま使えることを確認。
- [ ] **Step 4: テストが通ることを確認**（同じコマンド）。全体ビルドも通す。
- [ ] **Step 5: Commit** — `git commit -m "feat: expose regions in category order and the single command of a region"`

---

### Task 2: PickerQuery（語の分割と前方一致、純粋）

**Files:**
- Create: `Tatami/Model/PickerQuery.swift`
- Test: `TatamiTests/PickerQueryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum PickerQuery {
      static func tokens(_ query: String) -> [String]                     // 半角・全角空白で分割、小文字、空を除く
      static func matches(tokens: [String], terms: [String]) -> Bool      // 全語が terms のどれかに hasPrefix。tokens 空なら true
      static func terms(of set: LayoutSet) -> [String]                    // 名前と各行の appName（全体と各語）、小文字
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import Tatami

struct PickerQueryTests {
    @Test func 空白で分けて小文字にする() {
        #expect(PickerQuery.tokens("Left  1/3") == ["left", "1/3"])
        #expect(PickerQuery.tokens("右　1/3") == ["右", "1/3"])   // 全角空白
        #expect(PickerQuery.tokens("   ") == [])
        #expect(PickerQuery.tokens("") == [])
    }

    @Test func 全部の語がどれかの語彙に前方一致すれば残る() {
        let terms = ["右 1/3", "右", "1/3", "right third", "right", "third", "r3", ">"]
        #expect(PickerQuery.matches(tokens: [], terms: terms))
        #expect(PickerQuery.matches(tokens: ["r"], terms: terms))
        #expect(PickerQuery.matches(tokens: [">", "1/3"], terms: terms))
        #expect(PickerQuery.matches(tokens: ["right", "thi"], terms: terms))
        #expect(!PickerQuery.matches(tokens: ["2/3"], terms: terms))
        #expect(!PickerQuery.matches(tokens: [">", "2/3"], terms: terms))
        #expect(!PickerQuery.matches(tokens: ["ight"], terms: terms))   // 途中からは一致しない
    }

    @Test func セットの語彙は名前とアプリ名() {
        let set = LayoutSet(name: "Agent Coding", rows: [
            LayoutRow(bundleIdentifier: "wez", appName: "WezTerm", action: .leftTwoThirds),
            LayoutRow(bundleIdentifier: "chrome", appName: "Google Chrome", action: .rightThird),
        ])
        let terms = PickerQuery.terms(of: set)
        #expect(terms.contains("agent coding"))
        #expect(terms.contains("coding"))
        #expect(terms.contains("wezterm"))
        #expect(terms.contains("google chrome"))
        #expect(terms.contains("chrome"))
        #expect(terms.allSatisfy { $0 == $0.lowercased() })
    }
}
```

- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/PickerQueryTests`。
- [ ] **Step 3: 実装** — `tokens` は `query.lowercased().split(whereSeparator: { $0.isWhitespace })`（`Character.isWhitespace` は全角空白 U+3000 も true）。`matches` は `tokens.allSatisfy { t in terms.contains { $0.hasPrefix(t) } }`。`terms(of:)` は名前と appName それぞれを `lowercased()` し、全体と `split(whereSeparator: \.isWhitespace)` の各語を入れて重複を除く（順序は問わない）。
- [ ] **Step 4: テストが通ることを確認。**
- [ ] **Step 5: Commit** — `git commit -m "feat: PickerQuery tokenizes a query and prefix-matches terms"`

---

### Task 3: SnapAction.searchTerms（別名表）

**Files:**
- Create: `Tatami/Model/SnapAction+Search.swift`
- Test: `TatamiTests/SnapActionSearchTests.swift`

**Interfaces:**
- Consumes: `PickerQuery.tokens` / `matches`（Task 2）、`SnapAction.allInCategoryOrder`（Task 1）
- Produces: `extension SnapAction { var searchTerms: [String] }` — すべて小文字。仕様 §2.3 の表の全列 + 日本語名（全体と各語）。英語は全体と各語。

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import Tatami

struct SnapActionSearchTests {
    /// query で絞った区画（カテゴリ順）。
    func filter(_ query: String) -> [SnapAction] {
        let tokens = PickerQuery.tokens(query)
        return SnapAction.allInCategoryOrder.filter { PickerQuery.matches(tokens: tokens, terms: $0.searchTerms) }
    }

    @Test func 全区画に小文字の語彙がある() {
        for action in SnapAction.allCases {
            #expect(!action.searchTerms.isEmpty, "\(action)")
            #expect(action.searchTerms.allSatisfy { $0 == $0.lowercased() }, "\(action)")
            #expect(action.searchTerms.contains(action.title.lowercased()), "\(action)")
        }
    }

    @Test func 記号と分数で右三分の一だけになる() {
        #expect(filter("> 1/3") == [.rightThird])
        #expect(filter("r3") == [.rightThird])
        #expect(filter("migi 1/3") == [.rightThird])
        #expect(filter("右 1/3") == [.rightThird])
    }

    @Test func 左の記号で左系がまとめて残る() {
        let expected: [SnapAction] = [.leftHalf, .leftThird, .leftTwoThirds, .firstFourth,
                                      .topLeftQuarter, .bottomLeftQuarter, .topLeftSixth, .bottomLeftSixth]
        #expect(filter("<") == expected)
        #expect(filter("left") == expected)
    }

    @Test func 四隅はどちらの順でも効く() {
        #expect(filter("<^") == [.topLeftQuarter, .topLeftSixth])
        #expect(filter("^<") == [.topLeftQuarter, .topLeftSixth])
        #expect(filter(">v 1/6") == [.bottomRightSixth])
    }

    @Test func ローマ字と略号() {
        #expect(filter("hanbun") == [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
        #expect(filter("l23") == [.leftTwoThirds])
        #expect(filter("q2") == [.secondFourth])
        #expect(filter("max") == [.maximize, .maximizeHeight, .maximizeWidth])
        #expect(filter("takasa") == [.maximizeHeight])
    }

    @Test func lで右四分の一は残らない() {
        #expect(!filter("l").contains(.lastFourth))
        #expect(filter("l").contains(.leftHalf))
    }

    @Test func 数字の2は左三分の二と左から2番目の両方() {
        #expect(filter("2") == [.leftTwoThirds, .rightTwoThirds, .secondFourth])
    }
}
```

- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/SnapActionSearchTests`。
- [ ] **Step 3: 実装** — 仕様 §2.3 の表を `switch self` で `(english: String, abbreviations: [String], romaji: [String], symbols: [String])` として返す private 関数にし、`searchTerms` で `title`（全体 + 各語）、english（全体 + 各語）、abbreviations、romaji、symbols を連結して `lowercased()`、重複除去（順序は問わない）。表の値は仕様の表を**そのまま**写す（`last` は入れない）。
  注意: 「数字の2」のテストが `[.leftTwoThirds, .rightTwoThirds, .secondFourth]` になるのは、`2/3` と「2」「2 番目」の語に前方一致するため。右 2/3 も含まれる。
- [ ] **Step 4: テストが通ることを確認。** 通らない項目が表の矛盾なら、表（仕様）ではなくテストの期待を疑う前に、語彙の写し間違いを確認する。
- [ ] **Step 5: Commit** — `git commit -m "feat: search terms (English, abbreviations, romaji, symbols) for every region"`

---

### Task 4: PickerItem / PickerSection と PickerState.sections

**Files:**
- Create: `Tatami/Model/PickerItem.swift`
- Modify: `Tatami/App/PickerView.swift`（`PickerState` だけ。`filter` を削除し `sections` / `flatten` を足す。View 本体は Task 8）
- Test: `TatamiTests/PickerStateTests.swift`（全面置き換え）

**Interfaces:**
- Consumes: Task 1〜3
- Produces:
  ```swift
  enum PickerItem: Hashable, Identifiable, Sendable {
      case set(LayoutSet)
      case region(SnapAction)
      var id: String            // "set:<uuid>" / "region:<rawValue>"
      var setValue: LayoutSet?  // .set なら中身
      var region: SnapAction?   // .region なら中身
  }
  struct PickerSection: Hashable, Sendable { let title: String; let items: [PickerItem] }
  extension PickerState {
      static func sections(sets: [LayoutSet], favorites: Set<SnapAction>, query: String) -> [PickerSection]
      static func flatten(_ sections: [PickerSection]) -> [PickerItem]
  }
  ```
  見出し文字列は `"セット"` と `"区画"`。

- [ ] **Step 1: 失敗するテストを書く**（ファイルを置き換える）

```swift
import Testing
@testable import Tatami

@MainActor
struct PickerStateTests {
    let sets = [
        LayoutSet(name: "作業", rows: [LayoutRow(bundleIdentifier: "wez", appName: "WezTerm", action: .leftTwoThirds)]),
        LayoutSet(name: "連絡", rows: [LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird)]),
    ]

    func sections(_ query: String, sets: [LayoutSet]? = nil, favorites: Set<SnapAction> = []) -> [PickerSection] {
        PickerState.sections(sets: sets ?? self.sets, favorites: favorites, query: query)
    }

    @Test func 空の検索は2見出しで全部() {
        let s = sections("")
        #expect(s.map(\.title) == ["セット", "区画"])
        #expect(s[0].items.compactMap(\.setValue).map(\.name) == ["作業", "連絡"])
        #expect(s[1].items.compactMap(\.region) == SnapAction.allInCategoryOrder)
    }

    @Test func セットが0件なら区画だけ() {
        let s = sections("", sets: [])
        #expect(s.map(\.title) == ["区画"])
        #expect(PickerState.flatten(s).first == .region(.leftHalf))
    }

    @Test func お気に入りは区画の先頭にカテゴリ順で浮く() {
        let regions = sections("", favorites: [.center, .rightThird])[1].items.compactMap(\.region)
        #expect(regions.prefix(2) == [.rightThird, .center])
        #expect(regions.count == 27)
        #expect(Set(regions).count == 27)
    }

    @Test func セット名はアプリ名でも前方一致() {
        #expect(sections("連")[0].items.compactMap(\.setValue).map(\.name) == ["連絡"])
        #expect(sections("wez")[0].items.compactMap(\.setValue).map(\.name) == ["作業"])
        #expect(sections("line")[0].items.compactMap(\.setValue).map(\.name) == ["連絡"])
    }

    @Test func 区画だけに当たるとセット見出しは消える() {
        let s = sections("> 1/3")
        #expect(s.map(\.title) == ["区画"])
        #expect(s[0].items == [.region(.rightThird)])
    }

    @Test func 一致なしは空配列() {
        #expect(sections("zzz").isEmpty)
    }

    @Test func flattenはセットのあとに区画() {
        let flat = PickerState.flatten(sections(""))
        #expect(flat.count == 2 + 27)
        #expect(flat[0] == .set(sets[0]))
        #expect(flat[2] == .region(.leftHalf))
    }
}
```

- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/PickerStateTests`。
- [ ] **Step 3: 実装** — `PickerItem.swift` を作る。`PickerState.sections`: `tokens = PickerQuery.tokens(query)`; セットは `PickerQuery.matches(tokens:, terms: PickerQuery.terms(of:))` で絞る; 区画は `allInCategoryOrder` を `favorites` に含まれるものと含まれないものに分けて連結してから `searchTerms` で絞る; 空のセクションは入れない。`filter(_:query:)` と旧テストを削除。`PickerView` 内の `filter` 参照は Task 8 まで残るとビルドが壊れるので、このタスクでは `private var filtered` を一時的に `PickerState.flatten(PickerState.sections(sets: store.sets, favorites: [], query: state.query)).compactMap(\.setValue)` に置き換えてビルドを通す（Task 8 で本実装）。
- [ ] **Step 4: テストが通り、全体ビルドが通ることを確認。**
- [ ] **Step 5: Commit** — `git commit -m "feat: picker sections (sets, regions with favorites first) built from a query"`

---

### Task 5: FavoriteRegions

**Files:**
- Create: `Tatami/App/FavoriteRegions.swift`
- Test: `TatamiTests/FavoriteRegionsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor @Observable
  final class FavoriteRegions {
      static let key = "picker.favoriteRegions"
      init(defaults: UserDefaults = .standard)
      private(set) var regions: Set<SnapAction>
      func contains(_ action: SnapAction) -> Bool
      func toggle(_ action: SnapAction)
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Foundation
import Testing
@testable import Tatami

@MainActor
final class FavoriteRegionsTests {
    let suiteName = "dev.hidekingerz.tatamiTests.FavoriteRegions.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    @Test func 何もなければ空() {
        #expect(FavoriteRegions(defaults: defaults).regions.isEmpty)
    }

    @Test func toggleで追加と削除が保存され別インスタンスで読める() {
        let favorites = FavoriteRegions(defaults: defaults)
        favorites.toggle(.rightThird)
        favorites.toggle(.center)
        favorites.toggle(.rightThird)
        #expect(favorites.regions == [.center])
        #expect(favorites.contains(.center))
        #expect(!favorites.contains(.rightThird))
        #expect(FavoriteRegions(defaults: defaults).regions == [.center])
        #expect(defaults.stringArray(forKey: FavoriteRegions.key) == ["center"])
    }

    @Test func 未知の値は捨てる() {
        defaults.set(["center", "noSuchRegion", "leftHalf"], forKey: FavoriteRegions.key)
        #expect(FavoriteRegions(defaults: defaults).regions == [.center, .leftHalf])
    }
}
```

- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/FavoriteRegionsTests`。
- [ ] **Step 3: 実装** — `LayoutSetStore` / `CommandSettings` と同じ構え（`@ObservationIgnored private let defaults`）。保存は `regions.map(\.rawValue).sorted()`。
- [ ] **Step 4: テストが通ることを確認。**
- [ ] **Step 5: Commit** — `git commit -m "feat: FavoriteRegions persists starred regions"`

---

### Task 6: InputSourcePolicy と InputSourceSwitcher

**Files:**
- Create: `Tatami/System/InputSourceSwitcher.swift`（`InputSourceInfo`、`InputSourcePolicy`、`InputSourceSwitching`、`CarbonInputSourceSwitcher`）
- Create: `TatamiTests/Fakes/FakeInputSourceSwitcher.swift`
- Test: `TatamiTests/InputSourcePolicyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct InputSourceInfo: Equatable, Sendable {
      let id: String; let isASCIICapable: Bool; let isSelectable: Bool; let isKeyboardLayout: Bool
  }
  enum InputSourcePolicy {
      static let preferredID = "com.apple.keylayout.ABC"
      static func target(current: InputSourceInfo, candidates: [InputSourceInfo]) -> InputSourceInfo?
  }
  @MainActor protocol InputSourceSwitching: AnyObject { func enterASCII(); func restore() }
  @MainActor final class CarbonInputSourceSwitcher: InputSourceSwitching
  // テスト用
  @MainActor final class FakeInputSourceSwitcher: InputSourceSwitching {
      private(set) var enterCount = 0; private(set) var restoreCount = 0
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import Tatami

struct InputSourcePolicyTests {
    let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", isASCIICapable: true, isSelectable: true, isKeyboardLayout: true)
    let us = InputSourceInfo(id: "com.apple.keylayout.US", isASCIICapable: true, isSelectable: true, isKeyboardLayout: true)
    let japanese = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", isASCIICapable: false, isSelectable: true, isKeyboardLayout: false)
    let romaji = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", isASCIICapable: true, isSelectable: true, isKeyboardLayout: false)
    let emoji = InputSourceInfo(id: "com.apple.CharacterPaletteIM", isASCIICapable: true, isSelectable: false, isKeyboardLayout: false)

    @Test func いまがASCII可能なら切り替えない() {
        #expect(InputSourcePolicy.target(current: abc, candidates: [abc, japanese]) == nil)
        #expect(InputSourcePolicy.target(current: us, candidates: [abc, us]) == nil)
    }

    @Test func ABCがあればABC() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, us, abc]) == abc)
    }

    @Test func ABCがなければ最初のASCII可能なキーボードレイアウト() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, romaji, us]) == us)
    }

    @Test func 選択不可や入力メソッドは選ばない() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, emoji, romaji]) == nil)
    }
}
```

- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/InputSourcePolicyTests`。
- [ ] **Step 3: 実装**
  - `InputSourcePolicy.target`: `current.isASCIICapable` なら nil。`candidates.first { $0.id == preferredID && $0.isSelectable }` → なければ `candidates.first { $0.isASCIICapable && $0.isSelectable && $0.isKeyboardLayout }`。
  - `CarbonInputSourceSwitcher`: `private var previous: TISInputSource?`。`enterASCII()`: `TISCopyCurrentKeyboardInputSource()` を `InputSourceInfo` に変換（`TISGetInputSourceProperty` で `kTISPropertyInputSourceID`、`kTISPropertyInputSourceIsASCIICapable`、`kTISPropertyInputSourceIsSelectCapable`、`kTISPropertyInputSourceType == kTISTypeKeyboardLayout`）。候補は `TISCreateInputSourceList(nil, false)` のうち `kTISPropertyInputSourceIsEnabled` が true かつ `kTISPropertyInputSourceCategory == kTISCategoryKeyboardInputSource` のもの。`target` が返れば `previous = current` にして `TISSelectInputSource(targetSource)`。noErr 以外なら `previous = nil` にしてログ（`Logger(subsystem: "dev.hidekingerz.tatami", category: "InputSource")`）。`restore()`: `previous` があれば `TISSelectInputSource(previous)` して nil に。
  - `TISInputSource` と `InputSourceInfo` の対応を保つため、候補は `[(source: TISInputSource, info: InputSourceInfo)]` で持ち、`target` の結果を id で引き直す。
  - `FakeInputSourceSwitcher` はカウントするだけ。
- [ ] **Step 4: テストが通り、アプリ全体がビルドできることを確認**（Carbon の呼び出しがコンパイルできるか）。
- [ ] **Step 5: Commit** — `git commit -m "feat: input source switcher (ABC while the picker is open) with a pure selection policy"`

---

### Task 7: SnapEngine に対象ウィンドウの記憶と区画適用を足す

**Files:**
- Modify: `Tatami/Engine/SnapEngine.swift`
- Modify: `Tatami/System/WindowService.swift`（`WindowServiceError: Equatable`）
- Test: `TatamiTests/SnapEngineTests.swift`（追加）

**Interfaces:**
- Produces:
  ```swift
  enum SnapFailure { …既存…; case noTargetWindow }
  extension SnapEngine {
      private(set) var rememberedWindow: WindowHandle?
      func rememberFocusedWindow()                                   // 取れなければ nil
      func forgetRememberedWindow()
      @discardableResult func applyToRememberedWindow(_ action: SnapAction) -> SnapFailure?   // nil = 成功
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**（`SnapEngineTests` に追加）

```swift
@Test func 記憶した窓に区画を適用して記憶を消しmemoryを更新する() {
    let engine = makeEngine()
    engine.rememberFocusedWindow()
    #expect(engine.rememberedWindow == windows.window)
    #expect(engine.applyToRememberedWindow(.rightThird) == nil)
    #expect(windows.setFrameCalls == [CGRect(x: 1280, y: 25, width: 640, height: 1010)])
    #expect(engine.memory?.action == .rightThird)
    #expect(engine.memory?.window == windows.window)
    #expect(engine.rememberedWindow == nil)
}

@Test func 取れなければ記憶はnilに戻る() {
    let engine = makeEngine()
    engine.rememberFocusedWindow()
    windows.focusedWindowError = .noFocusedWindow
    engine.rememberFocusedWindow()
    #expect(engine.rememberedWindow == nil)
}

@Test func forgetで消える() {
    let engine = makeEngine()
    engine.rememberFocusedWindow()
    engine.forgetRememberedWindow()
    #expect(engine.rememberedWindow == nil)
}

@Test func 記憶なしはnoTargetWindowでmemoryは不変() {
    var failures: [SnapFailure] = []
    let engine = makeEngine { failures.append($0) }
    engine.perform(.maximize)
    let before = engine.memory
    #expect(engine.applyToRememberedWindow(.leftThird) == .noTargetWindow)
    #expect(engine.memory == before)
    #expect(failures.count == 1)
}

@Test func 権限なしはnotTrustedで権限要求する() {
    permission.isTrusted = false
    let engine = makeEngine()
    engine.rememberFocusedWindow()
    #expect(engine.applyToRememberedWindow(.leftThird) == .notTrusted)
    #expect(permission.requestAccessCount == 1)
    #expect(windows.setFrameCalls.isEmpty)
}

@Test func 適用エラーはwindowでmemoryは不変() {
    let engine = makeEngine()
    engine.perform(.maximize)
    let before = engine.memory
    engine.rememberFocusedWindow()
    windows.setFrameError = .axError(.invalidUIElement)
    let failure = engine.applyToRememberedWindow(.leftThird)
    guard case .window = failure else { Issue.record("expected .window, got \(String(describing: failure))"); return }
    #expect(engine.memory == before)
    #expect(engine.rememberedWindow == nil)
}
```

  `SnapFailure` を `==` で比べるため `Equatable` が要る。`case unknown(any Error)` があるので自動合成できない。
  テスト側で `guard case` を使うか、`SnapFailure` に手書きの `==`（`unknown` 同士は常に false 扱いでよい）を足す。**手書きの `==` を足す**（テスト 1・4・5 が `==` を使う）。
  そのために `WindowServiceError` に `Equatable` を足す（`AXError` は Equatable なので自動合成できる）。
  `rememberFocusedWindow` が `permission.isTrusted` を見るかは決めない。`focusedWindow()` が投げたら nil、で十分（権限なしなら AX が失敗する）。
- [ ] **Step 2: 失敗を確認** — `-only-testing:TatamiTests/SnapEngineTests`。
- [ ] **Step 3: 実装** — `applyToRememberedWindow`: `guard permission.isTrusted else { permission.requestAccess(); fail(.notTrusted); rememberedWindow = nil; return .notTrusted }`、`guard let window = rememberedWindow else { fail(.noTargetWindow); return .noTargetWindow }`、`defer { rememberedWindow = nil }`、`do { let applied = try placer.place(window, action: action); memory = CycleMemory(window: window, action: action, appliedFrame: applied); return nil } catch PlacementError.noScreen { fail(.noScreen); return .noScreen } catch let e as WindowServiceError { fail(.window(e)); return .window(e) } catch { fail(.unknown(error)); return .unknown(error) }`。
  `fail` は既存どおりログ + `onFailure`（beep）。
- [ ] **Step 4: テストが通ることを確認。**
- [ ] **Step 5: Commit** — `git commit -m "feat: SnapEngine remembers the window to target and applies a region to it"`

---

### Task 8: PickerView / PickerPanel（セクション、区画の行、⌘D、入力ソース）

**Files:**
- Modify: `Tatami/App/PickerView.swift`
- Modify: `Tatami/App/PickerPanel.swift`

**Interfaces:**
- Consumes: Task 4（`PickerState.sections` / `flatten`、`PickerItem`）、Task 5（`FavoriteRegions`）、Task 6（`InputSourceSwitching`）、`SnapAction.singleCommand`（Task 1）、`KeyboardShortcuts.getShortcut(for:)`、`CommandSettings.isEnabled`
- Produces:
  ```swift
  struct PickerView: View {
      init(store: LayoutSetStore, favorites: FavoriteRegions, settings: CommandSettings, state: PickerState,
           onApply: @escaping (LayoutSet) -> Void,
           onApplyRegion: @escaping (SnapAction) -> Void,
           onEdit: @escaping (LayoutSet?) -> Void,
           onEditRegion: @escaping (SnapCommand.Category) -> Void,
           onClose: @escaping () -> Void = {})
  }
  final class PickerPanel: NSPanel {
      init(store: LayoutSetStore, favorites: FavoriteRegions, settings: CommandSettings, inputSource: any InputSourceSwitching,
           onApply: …, onApplyRegion: …, onEdit: …, onEditRegion: …, onDismiss: @escaping @MainActor () -> Void)
  }
  ```

- [ ] **Step 1: PickerView を実装する**（UI なのでテストなし。ビルドと Task 10 の実機確認で見る）
  - `private var sections: [PickerSection]` = `PickerState.sections(sets: store.sets, favorites: favorites.regions, query: state.query)`、`private var items = PickerState.flatten(sections)`、`selected: PickerItem?` は `items` と `state.selectedIndex` から。
  - 一覧: `ForEach(sections, id: \.title)` → 見出し `Text(section.title).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6).padding(.horizontal, 10)` → `ForEach(section.items)`: `.set` は既存 `PickerRow`、`.region` は新設 `RegionRow(action:isSelected:isFavorite:keyLabel:onToggleFavorite:)`。
    `RegionRow`: `HStack(spacing: 12) { RegionGlyph(action:).size(width: 36, height: 22).highlighted(isSelected); Text(action.title).font(.system(size: 14)); Spacer(); if let keyLabel { 札（PickerRow と同じ） }; Button { onToggleFavorite() } label: { Image(systemName: isFavorite ? "star.fill" : "star") }.buttonStyle(.borderless).help("★ を付ける／外す") }`。縦 padding 6、選択は `PickerRow` と同じアクセント塗り。★ ボタンのタップが行の `onTapGesture` に伝わらないよう、行側は `.contentShape(Rectangle()).onTapGesture` のままでよい（SwiftUI は Button が先に受ける）。
    `keyLabel`: `action.singleCommand` があり `settings.isEnabled(command)` かつ `KeyboardShortcuts.getShortcut(for: command.shortcutName) != nil` のときだけ `description`。それ以外 nil。
  - `scrollTo` は `PickerItem.id`。
  - 検索欄: プレースホルダ「セットや区画を検索…」、件数 `"\(items.count) 件"`。
  - `content`: `items.isEmpty` なら `message("一致する項目はありません")`、それ以外は一覧。`store.sets.isEmpty` の分岐は削除。
  - キー: `.upArrow` / `.downArrow` は `items.count` で端止め。`.rightArrow` は `selected?.setValue` があるときだけ `expandedID` を設定、なければ `.ignored`。`.leftArrow` は既存。`.return`（phases: .down）: `submit(edit:)` → selected が `.set` なら従来、`.region` なら `onEditRegion(action.singleCommand?.category ?? .halves)` / `onApplyRegion(action)`。`items` が空なら何もしない。
    ⌘D: `.onKeyPress(characters: CharacterSet(charactersIn: "dD"), phases: .down) { press in guard press.modifiers.contains(.command), let region = selected?.region else { return .ignored }; favorites.toggle(region); return .handled }`。
  - ヒント文字列を仕様どおりに。
- [ ] **Step 2: PickerPanel を実装する**
  - 新しい引数を保持し `PickerView` に渡す。`show()` の先頭（`previousApp` を決めた直後、`NSApp.activate()` の前）で `inputSource.enterASCII()`。
  - `dismiss(restoringPreviousApp:)`: `guard isVisible`、`orderOut(nil)`、**`inputSource.restore()`**、`onDismiss()`、それから `previous?.activate()`。
  - `apply(_ set:)` は従来（close → onApply）。区画は `applyRegion(_ action:)`: `onApplyRegion(action)` を呼ぶだけ（閉じるのは AppModel が `applyToRememberedWindow` のあとに `closePicker()` で行う。仕様 §3.7）。
  - `edit(_ set:)` は従来。`editRegion(_ category:)`: `dismiss(restoringPreviousApp: false)` → `onEditRegion(category)`。
- [ ] **Step 3: ビルドが通ることを確認**（AppModel 側はまだ古い init を呼んでいるので、このタスクで `AppModel.openPicker` の呼び出しを新 init に合わせ、`favorites` / `inputSource` プロパティと `apply(_ action:)` / `openSettings(for category:)` の**空実装ではなく仕様どおりの実装**を Task 9 で入れる。ビルドを通すために Task 8 では AppModel を最小限（新 init に渡す引数の追加だけ）変更してよい）。
- [ ] **Step 4: Commit** — `git commit -m "feat: picker lists regions with favorites, aliases, ⌘D, and switches the input source while open"`

---

### Task 9: AppModel の配線、メニュー名、設定画面の ★

**Files:**
- Modify: `Tatami/App/AppModel.swift`
- Modify: `Tatami/App/MenuBarView.swift`
- Modify: `Tatami/App/SettingsView.swift`（`CommandListTab` / `CommandRow` に `favorites`）

**Interfaces:**
- Consumes: Task 5〜8
- Produces: `AppModel.favorites: FavoriteRegions`、`AppModel.apply(_ action: SnapAction)`、`AppModel.openSettings(for category: SnapCommand.Category)`（private でよい）

- [ ] **Step 1: AppModel**
  - `@ObservationIgnored let favorites = FavoriteRegions()`、`@ObservationIgnored private let inputSource: any InputSourceSwitching = CarbonInputSourceSwitcher()`。
  - `openPicker()`: パネルを（なければ）作り、`if !picker.isVisible { if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current { engine.forgetRememberedWindow() } else { engine.rememberFocusedWindow() } }` のあと `picker.toggle()`。
  - `PickerPanel` の `onApplyRegion: { [weak self] in self?.apply($0) }`、`onEditRegion: { [weak self] in self?.openSettings(for: $0) }`、`onDismiss: { [weak self] in self?.engine.forgetRememberedWindow() }`。
  - `apply(_ action: SnapAction)` を仕様 §3.7 のコードどおりに（`runner.isRunning` → closePicker + beep; `let failure = engine.applyToRememberedWindow(action)`; `closePicker()`; `switch failure { case nil: break; case .noTargetWindow: hud.show("対象のウィンドウがありません"); case .notTrusted: break; default: hud.show("ウィンドウを動かせませんでした") }`）。
  - `openSettings(for category:)`: `settingsTab = .commands(category)` にして、既存 `openSettings(for set:)` と同じ開く処理を共通の private 関数 `presentSettings()` に切り出して呼ぶ。
- [ ] **Step 2: MenuBarView** — `Button("レイアウトセット…")` を `Button("ピッカー…")` に。
- [ ] **Step 3: SettingsView** — `CommandListTab(category:settings:favorites:)`、`CommandRow(command:settings:favorites:)`。行の Toggle の右に、`command.isCycle` なら `Color.clear.frame(width: 16)`、そうでなければ `Button { favorites.toggle(command.sequence[0]) } label: { Image(systemName: favorites.contains(command.sequence[0]) ? "star.fill" : "star") }.buttonStyle(.borderless).help("ピッカーの先頭に出す")`。`SettingsView` から `model.favorites` を渡す。
- [ ] **Step 4: 全テストとビルド** — `xcodebuild … test`。153 + 新規がすべて PASS。
- [ ] **Step 5: Commit** — `git commit -m "feat: wire region application, favorites, and the renamed picker menu item"`

---

### Task 10: README、仕様の書き戻し、実機確認の手引き

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-11-02-picker-regions-design.md`（実装で決めた細部があれば）
- Modify: `docs/superpowers/plans/2026-10-30-layout-sets-on-device-checks.md`（末尾に「E ピッカーからの区画適用」として仕様 §8 の 9 項目を写す）

- [ ] **Step 1: README** — 「レイアウトセット」節の 3 つ目の箇条書き（ショートカット）を「メニューバーにも『ピッカー…』と各セットが並びます」に直し、ピッカーの段落の後に次を足す:

> ピッカーには 27 種類の区画も並び、⏎ で「ピッカーを開く直前に最前面だったウィンドウ」に適用します。設定でオフにしているコマンドやキー未割り当ての区画も使えます。検索は日本語名のほか、英語（`left third`）、略号（`l3`、`tl`、`max`）、ローマ字（`migi`）、記号（`<` `>` `^` `v`、四隅は `<^` など）、分数（`1/3`）で前方一致します。ピッカーが開いている間は入力ソースが ABC に切り替わり、閉じると戻ります。⌘D か行の ★ でお気に入りにすると、区画の先頭に出ます。

- [ ] **Step 2: 実機確認リスト** — 仕様 §8 の 9 項目を on-device-checks に追記。
- [ ] **Step 3: スクリーンショット** — `docs/images/layout-sets-picker.png` の撮り直しは実機の手が要る（ピッカーを key にするにはホットキーが必要）。利用者に依頼する項目として README には触れず、最終報告に書く。
- [ ] **Step 4: Commit** — `git commit -m "docs: describe applying regions from the picker, aliases, input source switch, and favorites"`
