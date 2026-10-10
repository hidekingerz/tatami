# Raycast 互換の配置パターンとコマンドの有効/無効 設計書

作成日: 2026-10-10
対象: hidekingerz/tatami
前提: [tatami MVP 設計書](2026-10-10-tatami-mvp-design.md) の構成（SnapCommand → SnapAction の系列 → LayoutCalculator）を引き継ぐ。

## 1. 目的と成功条件

Raycast の Window Management にある区画系・サイズ系の配置を tatami でも使えるようにする。
すべてを使う人はいないので、コマンドごとに有効/無効を切り替えられるようにし、
既存の 8 コマンドだけを初期状態で有効にする。

成功条件:

- 27 コマンド（§2.1）がそれぞれショートカットから動作する。
- 設定画面でコマンドごとに有効/無効を切り替えられ、無効のコマンドはホットキーを登録しない
  （他アプリから同じキーを奪わない）。
- 有効/無効とキー割当は再起動後も保持される。既存 8 コマンドのキー割当は本変更の前後で引き継がれる。
- 初回起動（設定なし）では既存 8 コマンドだけが有効で、動作とキーは MVP と同じ。
- 新しい区画の枠計算、コマンド定義、設定の保存が単体テストで検証されている。

## 2. 要件

### 2.1 コマンド一覧

カテゴリは設定画面のタブに対応する。⟳ は押すたびに区画が切り替わるループ系。

| カテゴリ | コマンド (rawValue) | 系列 | 既定キー | 既定で有効 |
|---|---|---|---|---|
| 半分 | 左半分 ⟳ (`cycleLeft`) | leftHalf → leftThird → leftTwoThirds | ⌃⌥b | ○ |
| 半分 | 右半分 ⟳ (`cycleRight`) | rightHalf → rightThird → rightTwoThirds | ⌃⌥f | ○ |
| 半分 | 上半分 (`topHalf`) | topHalf | ⌃⌥p | ○ |
| 半分 | 下半分 (`bottomHalf`) | bottomHalf | ⌃⌥n | ○ |
| 1/3 | 左 1/3 (`leftThird`) | leftThird | ⌃⌥z | ○ |
| 1/3 | 中央 1/3 (`centerThird`) | centerThird | ⌃⌥x | ○ |
| 1/3 | 右 1/3 (`rightThird`) | rightThird | ⌃⌥c | ○ |
| 1/3 | 左 2/3 (`leftTwoThirds`) | leftTwoThirds | なし | |
| 1/3 | 右 2/3 (`rightTwoThirds`) | rightTwoThirds | なし | |
| 1/4 | 左 1/4 (`firstFourth`) | firstFourth | なし | |
| 1/4 | 左から 2 番目の 1/4 (`secondFourth`) | secondFourth | なし | |
| 1/4 | 左から 3 番目の 1/4 (`thirdFourth`) | thirdFourth | なし | |
| 1/4 | 右 1/4 (`lastFourth`) | lastFourth | なし | |
| 四隅 | 左上 (`topLeftQuarter`) | topLeftQuarter | なし | |
| 四隅 | 右上 (`topRightQuarter`) | topRightQuarter | なし | |
| 四隅 | 左下 (`bottomLeftQuarter`) | bottomLeftQuarter | なし | |
| 四隅 | 右下 (`bottomRightQuarter`) | bottomRightQuarter | なし | |
| 1/6 | 左上 1/6 (`topLeftSixth`) | topLeftSixth | なし | |
| 1/6 | 中央上 1/6 (`topCenterSixth`) | topCenterSixth | なし | |
| 1/6 | 右上 1/6 (`topRightSixth`) | topRightSixth | なし | |
| 1/6 | 左下 1/6 (`bottomLeftSixth`) | bottomLeftSixth | なし | |
| 1/6 | 中央下 1/6 (`bottomCenterSixth`) | bottomCenterSixth | なし | |
| 1/6 | 右下 1/6 (`bottomRightSixth`) | bottomRightSixth | なし | |
| サイズ | 最大化 (`maximize`) | maximize | ⌃⌥m | ○ |
| サイズ | 高さを最大化 (`maximizeHeight`) | maximizeHeight | なし | |
| サイズ | 幅を最大化 (`maximizeWidth`) | maximizeWidth | なし | |
| サイズ | 中央に配置 (`center`) | center | なし | |

- 既存 8 コマンドの rawValue は現在の `KeyboardShortcuts.Name` の文字列と同一にする。
  KeyboardShortcuts は名前をキーに UserDefaults へ保存するので、これでユーザーが変更済みのキーが引き継がれる。
- 新規 19 コマンドには既定キーを与えない（Raycast も既定キーなし）。有効にしてもキーを記録するまで何も登録されない。

### 2.2 サイズ系 3 コマンドの動作

区画系は visibleFrame だけで枠が決まるが、サイズ系 3 つは現在の枠に依存する。
入出力は NS 座標。`visible` は対象画面の visibleFrame、`current` はウィンドウの現在枠。

- 高さを最大化: `x = current.minX`、`width = min(current.width, visible.width)`、`y = visible.minY`、`height = visible.height`。
- 幅を最大化: `y = current.minY`、`height = min(current.height, visible.height)`、`x = visible.minX`、`width = visible.width`。
- 中央に配置: `width = min(current.width, visible.width)`、`height = min(current.height, visible.height)`、
  原点は `visible` の中心から大きさの半分を引いた位置を `floor` した値。
- 上の計算で枠が `visible` の外にはみ出すなら、大きさはそのままに原点を内側へ寄せる
  （高さを最大化で x が右に寄りすぎている場合など）。

### 2.3 有効/無効の意味

- 無効: ホットキーを登録しない。設定画面では行は表示したままトグルがオフになり、Recorder は操作不可（グレー）になる。
  キー割当は消さないので、再び有効にすれば同じキーで復活する。
- 有効: キーが割り当てられていればホットキーを登録する。
- 切り替えは即時反映（再起動不要）。

### 2.4 スコープ外

- 左右以外のコマンドのループ化（上半分 → 上 1/3 … など）。
- Raycast の Reasonable Size、Restore、Move Up/Down/Left/Right、ディスプレイ・Space 間移動、Toggle Fullscreen、Focus 系。
- カテゴリ単位の一括オン/オフ。
- 設定のエクスポート/インポート。

## 3. アーキテクチャ

### 3.1 変更の全体像

```
TatamiApp
 ├─ Settings シーン ─ SettingsView (TabView: カテゴリごとに CommandListTab)
 │     └─ CommandRow ─ Toggle / RegionGlyph / 名前 / KeyboardShortcuts.Recorder
 │           └─ CommandSettings (有効/無効の保存)  ─┐
 └─ ShortcutRegistrar ─ onKeyDown 登録 + enable/disable ◄┘
       │
       ▼
 SnapEngine ─ CycleResolver / LayoutCalculator(frame(for:in:current:)) / … (流れは MVP と同じ)
```

依存方向は MVP と同じく上から下。`CommandSettings` は App 層に置き、Engine 層は有効/無効を知らない。

### 3.2 Model

```swift
enum SnapAction: CaseIterable, Sendable {
    // 既存 10 種
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    // 追加 17 種
    case firstFourth, secondFourth, thirdFourth, lastFourth
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximizeHeight, maximizeWidth, center
}

enum SnapCommand: String, CaseIterable, Sendable {
    case cycleLeft, cycleRight, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case firstFourth, secondFourth, thirdFourth, lastFourth
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximize, maximizeHeight, maximizeWidth, center

    enum Category: CaseIterable { case halves, thirds, fourths, quarters, sixths, size }

    var sequence: [SnapAction]      // ループ系は 3 要素、他は 1 要素
    var category: Category
    var title: String               // 設定画面の表示名（§2.1）
    var isEnabledByDefault: Bool    // 既存 8 個だけ true
    var isCycle: Bool               // sequence.count > 1
}

extension SnapCommand.Category {
    var title: String               // タブ名: 半分 / 1/3 / 1/4 / 四隅 / 1/6 / サイズ
    var commands: [SnapCommand]     // SnapCommand.allCases のうちこのカテゴリのもの。allCases の順
}
```

`SnapCommand.allCases` の順はカテゴリ順（§2.1 の表の順）にし、設定画面はこの順で並べる。
MVP のテスト「設定画面の並びは …」はこの順に合わせて更新する。

### 3.3 LayoutCalculator

```swift
enum LayoutCalculator {
    /// visible: 対象画面の visibleFrame、current: ウィンドウの現在枠。いずれも NS 座標。
    /// 区画系は current を使わない。サイズ系 3 つ（§2.2）だけが current に依存する。
    static func frame(for action: SnapAction, in visible: CGRect, current: CGRect) -> CGRect
}
```

- 1/4 は `floor(width / 4)` を基本幅とし、端数は右端（lastFourth）に寄せる。
- 四隅は半分の幅と高さの組み合わせ。端数は右・上に寄せる（既存の半分と同じ規則）。
- 1/6 は 1/3 の幅と半分の高さの組み合わせ。端数は右・上に寄せる。
- 同じ分割に属する区画は隙間も重なりもなく visibleFrame を埋める。
- サイズ系 3 つは §2.2 のとおり。

### 3.4 CommandSettings（新設、App 層）

```swift
@MainActor @Observable
final class CommandSettings {
    init(defaults: UserDefaults = .standard)
    func isEnabled(_ command: SnapCommand) -> Bool
    func setEnabled(_ enabled: Bool, for command: SnapCommand)
    var enabledCommands: [SnapCommand]
}
```

- 保存キーは `command.<rawValue>.enabled`（例: `command.topLeftQuarter.enabled`）、値は Bool。
- キーが存在しなければ `command.isEnabledByDefault` を返す。初回起動ではこれで既存 8 個だけ有効になる。
- `setEnabled` は UserDefaults に書き、`onChange: (SnapCommand, Bool) -> Void` で ShortcutRegistrar に通知する
  （View は CommandSettings だけを触り、KeyboardShortcuts を直接呼ばない）。
- `UserDefaults` を注入できるので、テストでは suite 名付きの UserDefaults を使い、終了時に `removePersistentDomain` する。

### 3.5 ShortcutRegistrar

```swift
extension SnapCommand {
    var shortcutName: KeyboardShortcuts.Name   // Name(rawValue, default: defaultShortcut)
    var defaultShortcut: KeyboardShortcuts.Shortcut?   // 既存 8 個だけ非 nil
}

@MainActor
enum ShortcutRegistrar {
    static func register(engine: SnapEngine, settings: CommandSettings)
    static func setEnabled(_ enabled: Bool, for command: SnapCommand)
}
```

- `register` は全コマンドに `KeyboardShortcuts.onKeyDown` を登録したあと、
  `settings.isEnabled` が false のものを `KeyboardShortcuts.disable` で解除する。
  `onKeyDown` はキーが割り当て済みならその場で登録するので、解除は登録の直後に行う。
- `shortcutName` は毎回生成せず、`SnapCommand` ごとに静的辞書へキャッシュする。
- `setEnabled` は `KeyboardShortcuts.enable` / `disable` を呼ぶ。`CommandSettings.onChange` から接続する。
- `AppModel` が `CommandSettings` を保持し、`start()` で `ShortcutRegistrar.register(engine:settings:)` を呼ぶ。
  テストホスト下では MVP と同じく何もしない。

### 3.6 SnapEngine

- `LayoutCalculator.frame(for:in:current:)` に `currentNS`（手順 4 で求めた NS 座標の現在枠）を渡す。それ以外は変更なし。
- 最小サイズ制約ではみ出す場合の補正（`originKeptInside`）はそのまま。サイズ系でも同じ補正が効く。

## 4. UI

### 4.1 設定画面の構造

- `Settings` シーン内を `TabView` にし、`SnapCommand.Category.allCases` の順にタブを並べる。
  macOS の設定ウィンドウと同じツールバー型のタブ（アイコン + ラベル）になる。
- タブのアイコンはそのカテゴリの先頭コマンドの `RegionGlyph` を `ImageRenderer` で画像化して使う。
  行のグリフと同じ描画なので、タブと行の見た目が一致する。
- 各タブは `Form(.grouped)` に `Section` 1 つ。見出しはカテゴリ名、右端に「n / m を使用中」（n = 有効な数、m = タブ内の数）。
- ウィンドウ幅は 480。

### 4.2 行（CommandRow）

左から: `Toggle`（`.switch` スタイル、ラベルなし） / `RegionGlyph` / 名前（ループ系は末尾に ⟳） / `KeyboardShortcuts.Recorder`。

- Toggle は `CommandSettings.isEnabled` に束縛し、変更で `setEnabled` を呼ぶ。
- Recorder は無効のとき `.disabled(true)` にする。KeyboardShortcuts はキーを記録した時点でホットキーを登録するため、
  無効中に記録できてしまうと「無効なのに効く」状態になる。これを防ぐ。
- 無効行は名前とグリフも `.secondary` 色にする。

### 4.3 RegionGlyph（新設）

- 24 × 15 pt の画面を表す角丸の枠線と、その中の区画を塗った小さな図。
- 区画の形は `LayoutCalculator.frame(for: action, in: reference, current: sample)` を基準画面の大きさで割って 0...1 に正規化して得る。
  `reference` は `CGRect(x: 0, y: 0, width: 1200, height: 600)`（LayoutCalculator は幅を floor するので、2・3・4 で割り切れる大きさにする）。
  サイズ系には代表的な現在枠 `sample = CGRect(x: 300, y: 120, width: 600, height: 360)` を渡し、
  「高さを最大化」なら縦長、「幅を最大化」なら横長、「中央に配置」なら中央の矩形として描かれる。
- NS 座標（左下原点）で得た枠を描画時に上下反転する。
- ループ系は系列の先頭の区画を描き、名前の横に ⟳ を添える（グリフ自体には重ねない）。
- 塗りは `.accentColor`、枠線は `.secondary`。無効時は両方 `.tertiary`。

## 5. エラー処理と互換性

- 有効/無効の読み書きは UserDefaults なので失敗を扱わない。
- 既存ユーザーの UserDefaults には `command.*.enabled` が存在しないため、`isEnabledByDefault` が効いて既存 8 個が有効、
  キーは `KeyboardShortcuts.Name` が同名なのでそのまま。移行処理は不要。
- 同じキーを 2 つのコマンドに割り当てた場合の挙動は KeyboardShortcuts 任せ（MVP と同じ）。設定画面での重複検出はしない。

## 6. テスト

| 対象 | 内容 |
|---|---|
| LayoutCalculatorTests | 1/4 の 4 区画、四隅の 4 区画、1/6 の 6 区画が隙間も重なりもなく visibleFrame を埋める（幅 1000 × 高さ 700 と、原点オフセット付きの奇数サイズで）。端数が右・上に寄る。 |
| LayoutCalculatorTests | 高さを最大化・幅を最大化・中央に配置が §2.2 の枠になる。現在枠が visibleFrame より大きいときに縮む。はみ出すときに原点が内側へ寄る。 |
| LayoutCalculatorTests | 全 SnapAction の結果が visibleFrame に収まる（既存の総当たりテストに `current` を足す）。 |
| SnapCommandTests | コマンドは 27 個、区画は 27 種。allCases はカテゴリ順。`isEnabledByDefault` が true なのは既存 8 個だけ。既存 8 個の rawValue が MVP の名前と一致。各カテゴリの `commands` が allCases の部分列。 |
| CommandSettingsTests | 設定なしで既定値を返す。`setEnabled` 後に読み戻せる。別インスタンスでも同じ UserDefaults なら同じ値。`onChange` が呼ばれる。 |
| SnapEngineTests | 中央に配置を FakeWindowService で通し、適用された枠が中央になる。 |
| CycleResolverTests | 変更なし（系列の仕組みは同じ）。 |

`ShortcutRegistrar` と `RegionGlyph` は Carbon / SwiftUI に依存するので単体テストは書かない。
動作確認は実機で行う（有効化 → キー記録 → 動作、無効化 → キーが他アプリに通る、再起動後も状態が残る）。

## 7. 付随作業

- README のショートカット表をカテゴリ別に更新し、有効/無効の説明を加える。
- `.gitignore` に `.superpowers/` と `.playwright-mcp/` を追加する（ブレインストーム用の生成物）。
