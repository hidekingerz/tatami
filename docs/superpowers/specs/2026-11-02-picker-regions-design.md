# ピッカーからの区画適用（27 区画の検索実行、別名検索、入力ソース切替、★） 設計書

作成日: 2026-11-02
対象: hidekingerz/tatami
前提: [レイアウトセット設計書](2026-10-30-layout-sets-design.md) のピッカー（PickerPanel / PickerView / PickerState）、
SnapEngine / WindowPlacer、CommandSettings、設定画面のタブ構成を引き継ぐ。
ブランチ: `feature/picker-regions`（`feature/layout-sets` から分岐。PR #8 がマージされたら main に rebase する）。

## 1. 目的と成功条件

レイアウトセットのピッカー（検索して ⏎ / クリックで実行する画面）は使い勝手がよいので、
ここから「最前面のウィンドウを 1 区画へ」も実行できるようにする。
いまは 27 区画のうちキーを割り当てたものしか使えず、たまにしか使わない区画のためにキーを覚えたり割り当てたりする必要がある。
ピッカーに 27 区画を全部並べ、設定でオフのものもキー未割り当てのものも、名前で探して実行できるようにする。

利用者が挙げた使い勝手上の要件は 2 つ。

- 「左」「右」のように日本語に変換して打つのは面倒。英語・ローマ字・記号で探せること。
- そもそも IME が日本語のままだと `left` が「ぇft」になる。ピッカーが開いている間だけ入力ソースを ABC にすること。

成功条件:

- ピッカーを開くと、空の状態から「セット」「区画」の 2 見出しで全部が出る。区画は 27 個、カテゴリ順。
- `> 1/3`、`r3`、`migi 1/3`、`右 1/3` のどれでも「右 1/3」に絞れる（§2.3 の別名表どおり）。
- ⏎ かクリックで、ピッカーを開く直前に最前面だったウィンドウにその区画が適用される。
- ピッカーを開くと入力ソースが ABC（なければ ASCII 入力できるレイアウト）に切り替わり、閉じると元に戻る。元から ASCII なら触らない。
- ★ を付けた区画は「区画」見出しの先頭に浮かぶ。★ はピッカー（⌘D、クリック）と設定画面のコマンド一覧から付け外しでき、再起動後も残る。
- セットの検索・適用・⌘⏎ 編集・内訳の開閉は従来どおり動く。既存 27 コマンドのホットキーと設定には影響しない。
- 一覧の組み立て（並び、★、絞り込み）、別名の照合、入力ソースの選び方、記憶したウィンドウへの適用が単体テストで検証されている。

## 2. 要件

### 2.1 用語

- 区画（region）: `SnapAction` の 27 ケース。ピッカーに並ぶ単位。ループ系コマンド（左半分 → 左 1/3 → 左 2/3）は並べない。
- 項目（item）: ピッカーの 1 行。セットか区画のどちらか。
- 対象ウィンドウ: ピッカーを開く直前に最前面だったアプリのフォーカスウィンドウ。
- ★（お気に入り）: 利用者が印を付けた区画。「区画」見出しの先頭に出る。

### 2.2 一覧

- 見出しは「セット」「区画」の順。セットが 0 件なら「セット」見出しごと出さない。「区画」は常に 27 個出す。
- 区画の並びは、★ 付きを先頭に、残りをその後ろに。どちらの中も**カテゴリ順**
  （半分、1/3、1/4、四隅、1/6、サイズ。各カテゴリの中は `SnapCommand.allCases` の順で、コマンドの先頭区画を取る。
  既存の `SnapCommand.Category.actions`（LayoutSetsTab 内の private 拡張）をモデル層へ移して共有する）。
  具体的には: 左半分、右半分、上半分、下半分、左 1/3、中央 1/3、右 1/3、左 2/3、右 2/3、左 1/4、左から 2 番目の 1/4、
  左から 3 番目の 1/4、右 1/4、左上、右上、左下、右下、左上 1/6、中央上 1/6、右上 1/6、左下 1/6、中央下 1/6、右下 1/6、
  最大化、高さを最大化、幅を最大化、中央に配置。
- 設定画面でオフにしているコマンドの区画も、キー未割り当ての区画も出す。ピッカーはホットキーの有効/無効と独立。
- 区画の行: 区画の図（`RegionGlyph`、36×22）、区画名、キー、★。
  キーは「その区画だけを持つ単発コマンド」が設定でオンかつキー割り当てありのときだけ出す
  （左半分・右半分は単発コマンドがないので出さない。上の図の ⌃⌥f は例示で、実際には出ない）。
  それ以外はキー欄を空にする（セットの「未割当」とは違い、何も出さない）。
- セットの行は従来どおり（図、名前、要約、デスクトップのバッジ、キーまたは「未割当」、→ で内訳）。
- 検索欄の右の件数は「N 件」（セットと区画の合計）。検索欄のプレースホルダは「セットや区画を検索…」。
- 一致がないときは「一致する項目はありません」。セットが 0 件でも区画があるので、従来の「設定でセットを作ってください」は出さない。

### 2.3 検索（絞り込み）

- 問い合わせは空白で語に分ける（半角・全角の空白）。各語を小文字にする。
- 項目は、**すべての語**について「その項目の語彙のどれかに前方一致する」とき残る。語彙は小文字で比較する。
- 区画の語彙 = 以下の表の全列（日本語名は空白で分けた各語と全体の両方）。
- セットの語彙 = セット名、各行のアプリ名（それぞれ空白で分けた各語と全体）。
  従来の「部分一致」から「前方一致」に変わるが、名前の途中から打つ使い方は想定しないので許容する。
- 記号 `<` `>` `^` `v` は左・右・上・下。四隅は 2 文字の組み合わせで、どちらの順でも効く（`<^` と `^<`）。
  `<` だけ打つと `<^` `<v` にも前方一致するので左系がまとめて残る（意図どおり）。
- 分数 `1/3` `2/3` `1/4` `1/6` はそのまま語彙に入れる。`< 1/3` で左 1/3 だけになる（左 2/3 は `2/3`、左上 1/6 は `1/6` なので落ちる）。

別名表（この表を `SnapAction.searchTerms` の正とする。英語は空白で分けた各語も語彙に入れる）:

| 区画 | 英語 | 略号 | ローマ字 | 記号・分数 |
|---|---|---|---|---|
| 左半分 | left half | lh, l | hidari, hanbun | < |
| 右半分 | right half | rh, r | migi, hanbun | > |
| 上半分 | top half | th, t, up | ue, hanbun | ^ |
| 下半分 | bottom half | bh, b, down | shita, hanbun | v |
| 最大化 | maximize | max, m, full | saidai | |
| 左 1/3 | left third | l3, l13 | hidari | <, 1/3 |
| 中央 1/3 | center third | c3, c13 | chuo, mannaka | 1/3 |
| 右 1/3 | right third | r3, r13 | migi | >, 1/3 |
| 左 2/3 | left two thirds | l23 | hidari | <, 2/3 |
| 右 2/3 | right two thirds | r23 | migi | >, 2/3 |
| 左 1/4 | left quarter | l4, q1 | hidari | <, 1/4 |
| 左から 2 番目の 1/4 | second quarter | q2 | | 1/4, 2 |
| 左から 3 番目の 1/4 | third quarter | q3 | | 1/4, 3 |
| 右 1/4 | right quarter | r4, q4 | migi | >, 1/4 |
| 左上 | top left | tl | hidariue | <^, ^< |
| 右上 | top right | tr | migiue | >^, ^> |
| 左下 | bottom left | bl | hidarishita | <v, v< |
| 右下 | bottom right | br | migishita | >v, v> |
| 左上 1/6 | top left sixth | tl6 | hidariue | <^, ^<, 1/6 |
| 中央上 1/6 | top center sixth | tc6 | chuo, ue | ^, 1/6 |
| 右上 1/6 | top right sixth | tr6 | migiue | >^, ^>, 1/6 |
| 左下 1/6 | bottom left sixth | bl6 | hidarishita | <v, v<, 1/6 |
| 中央下 1/6 | bottom center sixth | bc6 | chuo, shita | v, 1/6 |
| 右下 1/6 | bottom right sixth | br6 | migishita | >v, v>, 1/6 |
| 高さを最大化 | max height | h | takasa | |
| 幅を最大化 | max width | w | haba | |
| 中央に配置 | center | c | chuo, mannaka | |

「left」は `left half` / `left third` / `left two thirds` / `left quarter` / `top left` … に前方一致し、左系が残る。
日本語名を空白で分けると「左から」「2」「番目の」「1/4」のような語も語彙に入る。`2` で左 2/3（`2/3`）と左から 2 番目の 1/4 の両方が残るのは意図どおり。
「l」は `lh` `l3` `l23` `l4` `left` に加えて `last` のような語にも当たりうるので、`last` は語彙に入れない（上の表に従う）。

### 2.4 ★（お気に入り）

- 保存: UserDefaults のキー `picker.favoriteRegions`、値は `SnapAction.rawValue` の配列（順序は意味を持たない。読み込み時に未知の値は捨てる）。
- 付け外し:
  - ピッカーで区画の行を選んで ⌘D。セットの行で押しても何もしない。
  - ピッカーの区画の行の右端の ★ をクリック（行の適用は起こさない）。
  - 設定画面のコマンド一覧（半分〜サイズのタブ）の各行に ★ のトグルを足す。ループ系の行（左半分→…、右半分→…）には出さない。
    左半分・右半分はループ系にしか含まれないので、設定画面からは ★ を付けられない（ピッカーからのみ）。
- 表示: ★ 付きは塗りつぶしの `star.fill`、それ以外は `star`（secondary 色）。選択行（アクセント塗り）の上では白。
- 並び: §2.2 のとおり「区画」見出しの先頭に、カテゴリ順で。

### 2.5 実行

- ピッカーを開くとき（開くたび）、`NSApp.activate()` の**前に**最前面アプリのフォーカスウィンドウを取り、記憶する（§3.4）。
  開くたびに記憶を上書きし、取れなかったときは nil にする（前回の窓が残らない）。
  最前面が tatami 自身（設定画面を開いたまま、など）のときは取りに行かず nil にする。設定画面の窓を動かしてしまわないため。
  取れなくても（最前面が tatami 自身、窓がない、権限なし）ピッカーは開く。
- 記憶は、区画を適用したとき、またはピッカーが閉じたとき（esc、⌘⏎、フォーカス喪失のどれでも）に消す。
  閉じたあとに古い窓へ適用される経路を残さない。
- 区画の行を ⏎ かクリックすると、ピッカーを閉じて前のアプリへ戻し、記憶したウィンドウに区画を適用する。
  適用は `WindowPlacer.place` で、ホットキーのスナップと同じ計算・同じはみ出し補正。
  適用後は `SnapEngine.memory` をその窓・区画・枠で更新し、続けてループ系のキーを押したときに自然につながるようにする。
  失敗したとき（記憶なし、権限なし、適用エラー）は `memory` に触れない。その後の判定は従来どおり `CycleResolver` に任せる。
- 失敗の扱い:
  - 記憶したウィンドウがない: beep し、HUD に「対象のウィンドウがありません」。
  - 権限なし: 権限要求を出して beep（既存の `SnapFailure.notTrusted` と同じ）。
  - 適用エラー（窓が閉じられた、画面が取れない）: beep し、HUD に「ウィンドウを動かせませんでした」。
  - レイアウトセットの実行中（`runner.isRunning`）: beep（ホットキーと同じ）。
  - 成功時は HUD を出さない（ホットキーのスナップと同じ）。
- セットの行の ⏎ / クリック / ⌘⏎ は従来どおり。
- 区画の行の ⌘⏎ は、設定画面をその区画のカテゴリのタブ（`SettingsTab.commands(category)`）で開く。左半分は「半分」タブ。
- ⏎ で一覧が空のときは何もしない。

### 2.6 入力ソースの切替

- ピッカーを開くとき、現在の入力ソースが ASCII 入力可能（`kTISPropertyInputSourceIsASCIICapable`）なら何もしない。
  そうでなければ現在のソースを記憶し、次の優先順で選んで `TISSelectInputSource` する。
  1. 有効なソースの中で ID が `com.apple.keylayout.ABC` のもの
  2. 有効で選択可能（`kTISPropertyInputSourceIsSelectCapable`）、カテゴリが keyboard（`kTISCategoryKeyboardInputSource`）、
     種類がキーボードレイアウト（`kTISTypeKeyboardLayout`）、ASCII 入力可能なものの先頭
  3. 該当なしなら切り替えない（記憶も残さない）
- ピッカーが閉じる（適用、esc、フォーカス喪失、⌘⏎ のどれでも）たびに、記憶があれば元のソースへ戻し、記憶を消す。
  戻すのは `orderOut` の後、前のアプリを `activate()` する**前**。
  macOS の「書類ごとに入力ソースを切り替える」をオンにしている環境では、戻したあとに前のアプリ側の記憶が上書きすることがあるが、
  それは OS の挙動なので任せる（実機で確かめる。§8）。
- 切替直後の最初のキー入力が IME に取られる問題が実機で出たら、`enterASCII()` の後に短い待ち（最大 50 ms）を入れることを許容する。
  出なければ入れない。
- 切替は OS 全体に効く（macOS の既定は入力ソースがアプリ横断）。閉じる経路を 1 か所（`PickerPanel.dismiss`）に集めて戻し漏れを防ぐ。
  tatami が終了するときに開いたままなら、`applicationWillTerminate` 相当で戻す必要はない（パネルは終了時に閉じられ `dismiss` が走る。
  走らない経路があるかは実機で確かめる。§8）。
- 入力ソースの切替は失敗しうる（`TISSelectInputSource` が noErr 以外）。失敗しても何もしない（ピッカーは開く）。ログに残す。

### 2.7 スコープ外

- 日本語の読み（ひらがな）での照合。IME の未確定文字は `TextField` の値にならないため意味がない。ABC への切替で代替する。
- 最近使った順や使用回数による並び替え。★ で代替する。
- ループ系コマンドをピッカーから実行すること。
- ピッカーから区画の対象ウィンドウを選ぶ UI（対象は常に「開く直前の最前面」）。
- 入力ソース切替の設定でのオン/オフ。常にオン。要望が出たら設定を足す。

## 3. アーキテクチャ

### 3.1 変更の全体像

```
PickerPanel.show() ─ AppModel.openPicker()
   │   ├ engine.rememberFocusedWindow()     … 対象ウィンドウを記憶（activate の前）
   │   └ inputSource.enterASCII()           … 入力ソースを ABC へ
   ├ PickerView ── PickerState.sections(sets:favorites:query:) → [PickerSection]
   │                 └ PickerItem.set / .region、SnapAction.searchTerms、PickerQuery.matches
   └ dismiss() ── inputSource.restore()
          ├ onApply(set)    → AppModel.apply(set)（従来）
          ├ onApply(region) → AppModel.apply(region) → engine.applyToRememberedWindow(region)
          ├ onEdit(set / category) → openSettings
          └ onToggleFavorite(region) → FavoriteRegions.toggle
```

### 3.2 Model

- `Tatami/Model/PickerItem.swift`（新設）
  ```swift
  enum PickerItem: Hashable, Identifiable, Sendable {
      case set(LayoutSet)
      case region(SnapAction)
      var id: PickerItemID   // .set(UUID) / .region(SnapAction)
  }
  struct PickerSection: Hashable, Sendable {
      let title: String      // "セット" / "区画"
      let items: [PickerItem]
  }
  ```
- `Tatami/Model/SnapAction+Search.swift`（新設）: `extension SnapAction { var searchTerms: [String] }`。§2.3 の表を返す。
  日本語名は `title` から作る（空白で分けた各語と全体）。表の英語は全体と各語の両方を入れる。すべて小文字。
- `Tatami/Model/SnapCommand.swift`: `SnapCommand.Category.actions: [SnapAction]` をここへ移す（LayoutSetsTab の private 拡張を削除）。
  `SnapAction.allInCategoryOrder: [SnapAction]` を足す（全カテゴリの `actions` を連結。27 個が 1 回ずつ）。
  `SnapAction.singleCommand: SnapCommand?` を足す（`sequence == [self]` のコマンド。左半分・右半分は nil）。
- `Tatami/Model/PickerQuery.swift`（新設、純粋）
  ```swift
  enum PickerQuery {
      /// 空白で分けて小文字にした語。空文字は除く。
      static func tokens(_ query: String) -> [String]
      /// すべての語が terms のどれかに前方一致するか。tokens が空なら true。
      static func matches(tokens: [String], terms: [String]) -> Bool
      /// セットの語彙（名前と各行のアプリ名。全体と各語）。
      static func terms(of set: LayoutSet) -> [String]
  }
  ```

### 3.3 PickerState（App 層、既存を拡張）

- `static func sections(sets: [LayoutSet], favorites: Set<SnapAction>, query: String) -> [PickerSection]`
  - セットは `sets` の順で絞る。0 件なら「セット」セクションを入れない。
  - 区画は `favorites` に含まれるものを `allInCategoryOrder` 順で先に、残りを同じ順で後に並べ、絞る。
    0 件なら「区画」セクションを入れない（全体が空なら「一致する項目はありません」）。
- `static func flatten(_ sections: [PickerSection]) -> [PickerItem]`。選択位置はこの平坦な配列の添字。
- `expandedID: UUID?` はセットだけに意味を持つ。→ はセットの行でだけ効く。
- 既存の `filter(_:query:)` は `sections` に置き換えて削除する（テストも移す）。

### 3.4 SnapEngine の拡張（Engine 層）

```swift
/// ピッカーを開く直前に記憶した対象ウィンドウ。
private(set) var rememberedWindow: WindowHandle?

/// 最前面アプリのフォーカスウィンドウを記憶する。取れなければ nil にする（エラーはログに残す）。
func rememberFocusedWindow()

/// 記憶を消す。
func forgetRememberedWindow()

/// 記憶したウィンドウに区画を適用し、記憶を消す。成功なら memory を更新して true。
/// 失敗は onFailure に流しつつ、理由を返す（HUD の文言に使う）。
@discardableResult
func applyToRememberedWindow(_ action: SnapAction) -> SnapFailure?
```

- `applyToRememberedWindow` は、権限なし → `.notTrusted`（requestAccess も呼ぶ）、記憶なし → 新設の `.noTargetWindow`、
  `PlacementError.noScreen` → `.noScreen`、`WindowServiceError` → `.window(error)`、その他 → `.unknown`。
  成功時は `memory = CycleMemory(window:action:appliedFrame:)`。どの経路でも `rememberedWindow = nil`。
- `SnapFailure` に `case noTargetWindow` を足す。

### 3.5 FavoriteRegions（App 層、新設）

```swift
@MainActor @Observable
final class FavoriteRegions {
    init(defaults: UserDefaults = .standard)
    private(set) var regions: Set<SnapAction>
    func contains(_ action: SnapAction) -> Bool
    func toggle(_ action: SnapAction)
    static let key = "picker.favoriteRegions"
}
```

保存は `[String]`（rawValue）。読み込みで未知の文字列は捨てる。`toggle` のたびに書く。

### 3.6 InputSourceSwitcher（System 層、新設）

```swift
protocol InputSourceSwitching: AnyObject {
    /// 現在が ASCII 入力可能でなければ記憶して ASCII レイアウトへ切り替える。
    func enterASCII()
    /// 記憶があれば戻して記憶を消す。
    func restore()
}

final class CarbonInputSourceSwitcher: InputSourceSwitching   // TIS* を使う実装
```

- 選び方は純粋関数に分けてテストする:
  ```swift
  struct InputSourceInfo: Equatable { let id: String; let isASCIICapable: Bool; let isSelectable: Bool; let isKeyboardLayout: Bool }
  enum InputSourcePolicy {
      static let preferredID = "com.apple.keylayout.ABC"
      /// 切り替え先。current が ASCII 可能なら nil。
      static func target(current: InputSourceInfo, candidates: [InputSourceInfo]) -> InputSourceInfo?
  }
  ```
  `candidates` は有効なソースだけ（`kTISPropertyInputSourceIsEnabled` が true のものを呼び出し側で絞って渡す）。
- Carbon の `TISCopyCurrentKeyboardInputSource`、`TISCreateInputSourceList(nil, false)`、`TISGetInputSourceProperty`、
  `TISSelectInputSource` を使う。`import Carbon.HIToolbox`。メインスレッドから呼ぶ。
- テスト用に `FakeInputSourceSwitcher`（enter / restore の呼び出し回数を数える）。

### 3.7 PickerPanel / AppModel

- `PickerPanel` の init に `favorites: FavoriteRegions`、`inputSource: any InputSourceSwitching`、
  `onApplyRegion: (SnapAction) -> Void`、`onEditRegion: (SnapCommand.Category) -> Void` を足す。
  `show()` の先頭で `inputSource.enterASCII()`、`dismiss(restoringPreviousApp:)` の中で `inputSource.restore()`（`isVisible` ガードの後）。
- `AppModel.openPicker()` は、パネルが出ていない（これから開く）ときだけ対象を記憶してから `toggle()`。
  `NSWorkspace.shared.frontmostApplication` が `NSRunningApplication.current` なら `engine.forgetRememberedWindow()`、
  それ以外なら `engine.rememberFocusedWindow()`（取れなければ engine 側で nil になる）。
  `PickerPanel.show()` の `NSApp.activate()` より前に走ること（AppModel 側で先に呼ぶので満たす）。
  「これから開く」の判定は `picker.isVisible` が false のとき。ホットキー再押下で閉じる場合は記憶に触れない（dismiss が消す）。
- `PickerPanel` に `onDismiss: () -> Void` を足し、`dismiss(restoringPreviousApp:)` の中で呼ぶ。AppModel はこれで
  `engine.forgetRememberedWindow()` を呼ぶ。適用の経路では `applyToRememberedWindow` が先に記憶を取り出すので、順序は
  「`closePicker()`（dismiss → onDismiss で forget）」より**前に**記憶を取り出す必要がある。したがって `AppModel.apply(_ action:)` は
  `let failure = engine.applyToRememberedWindow(action)` を先に行い、その後 `closePicker()` する
  （§2.5 の「閉じてから適用」はセットの場合。区画の適用は合成マウス操作を伴わないので順序を入れ替えてよい。
  ただし tatami が前面のまま `setFrame` しても AX は動く）。
- `AppModel.apply(_ action: SnapAction)`:
  ```swift
  func apply(_ action: SnapAction) {
      guard !runner.isRunning else { closePicker(); NSSound.beep(); return }
      let failure = engine.applyToRememberedWindow(action)
      closePicker()
      switch failure {
      case nil: break
      case .noTargetWindow: hud.show("対象のウィンドウがありません")
      case .notTrusted: break                      // engine が requestAccess 済み。beep は onFailure
      default: hud.show("ウィンドウを動かせませんでした")
      }
  }
  ```
  beep は既存の `onFailure: { _ in NSSound.beep() }` が鳴らすので二重に鳴らさない。
- `PickerPanel.dismiss` には再入ガード（`isDismissing`）がある。`orderOut` が `resignKey` を誘発して `dismiss` が再入しても、
  `restore()` と `onDismiss()` は 1 回しか走らない。そのため `onDismiss` は状態を消すだけにする（ほかの処理を載せない）。
- `AppModel.openSettings(for category: SnapCommand.Category)`: `settingsTab = .commands(category)` にして既存の開く経路を使う。
- `AppModel` に `@ObservationIgnored let favorites = FavoriteRegions()` と `inputSource = CarbonInputSourceSwitcher()`。

## 4. UI

### 4.1 ピッカー（PickerView）

- 構成は従来どおり（検索欄 / 一覧 / ヒント）。一覧はセクション見出し付き。見出しは 11pt、secondary、左寄せ、上に 6pt の余白。
- 区画の行（1 段、高さはセットの行より低い）: `RegionGlyph(action:)` 36×22 → 区画名 14pt → `Spacer` → キー（あれば、セットの行と同じ角丸の札）→ ★ ボタン（`star.fill` / `star`、borderless、`.help("★ を付ける／外す")`）。
  ★ のクリックは `onToggleFavorite(action)` を呼び、行のタップには伝えない。
  ⌘D のあとも選択はトグルした区画に付いたまま動かない（並びが変わっても追従する）。塗りつぶしの ★ は、選択されていない行ではアクセント色にする。
- セットの行は従来の `PickerRow`。
- 選択はセクションをまたいで ↑↓ で移動する（平坦な配列の添字）。端で止まる。
- `→` は選択がセットのときだけ内訳を開く。区画では `.ignored`。
- ⌘D は選択が区画のときだけ `onToggleFavorite`。セットでは `.ignored`。
  受け方は ⌘⏎ と同じく、ルートの `.onKeyPress` で `KeyEquivalent("d")` と `modifiers.contains(.command)` を見る
  （検索欄がフォーカスを持っていても届く。⌘D はフィールドエディタの既定バインディングにない）。
- ⏎: 区画なら `onApplyRegion`、セットなら `onApply`。⌘⏎: 区画なら `onEditRegion(category)`、セットなら `onEdit(set)`。
  一覧が空なら何もしない（従来の「セットが 0 件なら設定を開く」は、区画が常にあるので不要になる）。
- ヒント: 「⏎ 適用  ↑↓ 選択  →← 内訳  ⌘D ★  ⌘⏎ 編集  esc 閉じる」。
- 検索欄の件数: 「N 件」。

```
┌ 🔍 >                                                       8 件 ┐
├──────────────────────────────────────────────────────────────────┤
│ 区画                                                             │
│ ▭▮▮  右半分                                      ⌃⌥f    ★       │  ← 選択（アクセント塗り）
│ ▭▭▮  右 1/3                                      ⌃⌥c    ☆       │
│ ▭▮▮  右 2/3                                             ☆       │
│ ▭▭▮  右 1/4                                             ☆       │
│ …（右上、右下、右上 1/6、右下 1/6）                                │
├──────────────────────────────────────────────────────────────────┤
│ ⏎ 適用  ↑↓ 選択  →← 内訳  ⌘D ★  ⌘⏎ 編集  esc 閉じる             │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 設定画面（CommandRow）

- 各コマンド行のトグルの右（グリフの左）に ★ のトグルを足す（`Button` + `star.fill` / `star`、borderless、`.help("ピッカーの先頭に出す")`）。
  対象は `command.sequence[0]`（単発コマンドなので唯一の区画）。`CommandRow` が ★ を出すのもこの区画。
- ループ系の行には出さない（同じ幅の空白を置いて列をそろえる）。
- `FavoriteRegions` は `AppModel.favorites` の 1 つをピッカーと設定画面で共有する。`SettingsView` は `model` を持っているので、
  `CommandListTab` / `CommandRow` に `favorites` を引数で渡す（環境値は使わない。既存の `settings` と同じ渡し方）。
- 「セット」タブの `KeyboardShortcuts.Recorder("ピッカーを開く")` の文言はそのまま。

### 4.3 メニューバー

- 「レイアウトセット…」を「ピッカー…」に改名する（セット専用ではなくなるため）。README の記述も合わせる。

## 5. エラー処理と互換性

- 既存のセットの保存形式、コマンドの有効/無効、キー割当には触れない。
- `picker.favoriteRegions` は新規キー。無ければ空。
- 入力ソース切替は非サンドボックスの前提（いまの tatami と同じ）。`TISSelectInputSource` は「選択可能（IsSelectCapable）」でないソースに対して失敗する。候補から除く。
- 入力ソースを切り替えた直後の最初のキー入力が IME に取られる機種・設定があるかは実機で確かめる（§8）。

## 6. テスト

- `PickerStateTests`（既存を置き換え）: 空の問い合わせで 2 セクション、セット 0 件で「区画」だけ、★ が先頭に浮く、
  `> 1/3` で右 1/3 だけ、`<` で左系（左半分、左 1/3、左 2/3、左 1/4、左上、左下、左上 1/6、左下 1/6）、
  `left` で同じ集合、`migi 2/3` で右 2/3、`r3` で右 1/3、セット名の前方一致、全角空白の分割、一致なしで空配列。
- `SnapActionSearchTests`: 27 区画すべてに語彙があり小文字である、§2.3 の表の代表的な別名が引ける、
  `allInCategoryOrder` が 27 個で重複なし、`singleCommand` が左半分・右半分で nil、他は自分だけを持つコマンド。
- `PickerQueryTests`: tokens の分割（半角・全角空白、連続空白）、matches（空語、前方一致、全語一致の要件）。
- `FavoriteRegionsTests`: 空から toggle で追加・削除、UserDefaults に rawValue 配列で保存、未知の値を捨てる（テストごとに別 suite の defaults）。
- `InputSourcePolicyTests`: current が ASCII 可能なら nil、ABC があれば ABC、無ければ最初の ASCII 可能なキーボードレイアウト、候補なしなら nil、
  選択不可のものは選ばない。
- `SnapEngineTests`（既存に追加、FakeWindowService）: `rememberFocusedWindow` が focusedWindow を保持する、取れなければ nil に戻す、
  `forgetRememberedWindow` で消える、`applyToRememberedWindow` が place と memory 更新を行い記憶を消す、
  記憶なしで `.noTargetWindow`（memory は不変）、権限なしで `.notTrusted`（memory は不変）、適用エラーで memory は不変。
- UI（PickerView / PickerPanel / Carbon 呼び出し）は単体テストしない。実機確認は §8。

## 7. 付随作業

- README「レイアウトセット」節に、ピッカーから区画も実行できること、別名（英語・ローマ字・記号・分数）、
  入力ソースの自動切替、★ を書く。メニュー項目名の変更も反映する。
- `docs/images/layout-sets-picker.png` を、区画の行が見える状態で撮り直す。

## 8. 実機で確かめること

1. 別アプリを前面にしてホットキーでピッカーを開き、`r3` ⏎ でそのアプリの窓が右 1/3 になる。
2. 日本語入力のまま開いて `left` と打てる（ABC に切り替わる。最初の 1 文字が IME に取られないか）。
   閉じると日本語入力に戻る（esc、適用、別アプリをクリック、⌘⏎ の 4 経路）。
   「書類ごとに入力ソースを切り替える」がオンの環境でも、前のアプリに戻ったあとの入力ソースが開く前と同じか。
3. 元から ABC のとき、閉じても入力ソースが変わらない。
4. ピッカーを開いたまま tatami を終了したとき、入力ソースが元に戻るか。戻らなければ `applicationWillTerminate` で `restore()` を呼ぶ。
5. ⌘D と ★ クリックで付け外しでき、再起動後も先頭に出る。設定画面の ★ と同期している。
6. 窓のないアプリ（Finder でデスクトップだけ）を前面にして開き、区画を ⏎ すると HUD「対象のウィンドウがありません」が出る。
7. ピッカーを開いた後に対象の窓を閉じてから ⏎ すると HUD「ウィンドウを動かせませんでした」が出る。
8. ピッカーから区画を適用した直後に ⌃⌥b を押すと、左半分→左 1/3 のループが「次」から続く。
9. 設定画面を開いたままピッカーを出して区画を ⏎ すると、設定画面は動かず HUD「対象のウィンドウがありません」が出る。

## 9. ビルダーに委ねること

- 区画の行の正確な余白・フォントサイズ（セットの行と調和していればよい）。
- セクション見出しの見た目（11pt secondary を基本に、Spotlight の見出しに近い控えめなもの）。
- `PickerItem` の `Identifiable` の実装方法（`ScrollViewReader.scrollTo` に使えれば何でもよい）。
- `searchTerms` の表の持ち方（switch でも辞書でも。テストが表を検証する）。
- Carbon API の Swift からの呼び出しの細部（`Unmanaged` の扱い、CFBoolean の比較）。
