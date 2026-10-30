# レイアウトセット（複数ウィンドウの一括配置とスペース間の回収） 設計書

作成日: 2026-10-30
対象: hidekingerz/tatami
前提: [Raycast 互換レイアウト設計書](2026-10-10-raycast-layouts-and-toggles-design.md) の構成
（SnapCommand → SnapAction → LayoutCalculator、CommandSettings、ShortcutRegistrar、設定画面のタブ）を引き継ぐ。
モック: Claude Design「Tatami Layout Set Picker」（ピッカーの一覧と展開の 2 枚）
https://claude.ai/artifact/2XeB1e7pU3hHzYjg3x3u1q （利用者のアカウントで開ける。実装者が開けない場合は §4.1 の文章を正とする）。

## 1. 目的と成功条件

いまの tatami は「最前面の 1 枚を 1 区画へ」しかできない。複数のアプリを決まった形に並べるには
アプリを切り替えながらショートカットを何回も押す必要がある。
これを「レイアウトセット」として保存し、ピッカーから選んで一発で適用できるようにする。

利用者が挙げた具体的な場面は 2 つ。

- 作業: herdr を動かしている WezTerm の窓を左 2/3、動作確認用の Chrome を右 1/3。
- 連絡（回収）: LINE / Discord / Teams は普段「連絡用」のデスクトップに置いているが、
  作業中に別のデスクトップへ持ち出して散らかる。これを連絡用デスクトップへ連れ戻し、1/3 ずつ横に並べ直す。

後者のために、ウィンドウを別のデスクトップ（macOS の Space）へ移す手段が要る。
公開 API は存在しないので、Rectangle Pro と同じ「タイトルバーを掴んだままスペース切替キーを送る」方式を採る（§5）。
非公開 API（SkyLight の `CGSMoveWindowsToManagedSpace` など）は使わない。
Apple が「実装詳細であり予告なく変わる」と明言しており、壊れたときに tatami 側で直せないため。

成功条件:

- 設定画面でセットを作れる（手で行を組む方法と、いまの配置を取り込む方法の両方）。
- グローバルキーでピッカーが開き、↑↓ と Enter、またはクリックでセットを適用できる。
  セットごとにも直接キーを割り当てられ、そちらはピッカーを出さずに適用する。
- 適用すると、各行のウィンドウが指定の区画に置かれる。デスクトップ番号を持つ行は、そのデスクトップへ移ってから置かれる。
- 見つからない行（アプリが起動していない、絞り込みに合う窓がない）は飛ばして続行し、終わったあと結果を短く表示する。
- セット、行、キー割当は再起動後も残る。既存の 27 コマンドの動作と設定には影響しない。
- モデルの保存と読み出し、行とウィンドウの照合、区画への丸め、Mission Control ショートカット設定の読み取りが単体テストで検証されている。

## 2. 要件

### 2.1 用語

| 用語 | 意味 |
|---|---|
| セット (LayoutSet) | 名前と行の並びを持つ単位。ピッカーの 1 行、ショートカット 1 つに対応する。 |
| 行 (LayoutRow) | 「どのアプリの、どの窓を、どの区画に、どのデスクトップで」の 1 件。 |
| 区画 | 既存の `SnapAction`（27 種）。計算は `LayoutCalculator` をそのまま使う。 |
| デスクトップ番号 | Mission Control の「デスクトップ N」の N（1〜10）。macOS のスペースには名前も固定 ID もないため番号で指す。 |
| ピッカー | グローバルキーで中央に出るパレット。検索欄、セットの一覧、キーのヒント。 |

### 2.2 セットと行

```
LayoutSet
  id: UUID                 // 保存とショートカット名に使う。作成時に採番し変えない
  name: String             // ピッカーに出す名前。重複可
  rows: [LayoutRow]        // 上から順に適用する。並び替え可

LayoutRow
  id: UUID
  bundleIdentifier: String // 例 "com.google.Chrome"
  appName: String          // 表示用。保存時点の localizedName。照合には使わない
  titleFilter: String      // 空なら絞り込みなし。空でなければ「タイトルにこの文字列を含む」（大文字小文字を区別しない）
  action: SnapAction?      // nil は「区画を変えない」（保存で丸めきれなかった窓に使う）
  desktop: Int?            // nil は「デスクトップを変えない」。1...10
```

- 1 つのセットに同じアプリの行が複数あってよい（WezTerm の窓 2 枚を左右に、など）。
  照合は行ごとに独立に行い、すでに別の行に使った窓は候補から外す（§2.4）。
- `action` と `desktop` がともに nil の行は「何もしない行」として保存を許す（取り込みで普通に生まれるため）。
  適用では照合もせず無視し、結果の件数にも入れない。設定画面では薄い色で「何もしない」と表示し、利用者が区画を選ぶか消すかを判断する。
- セットの編集は `CommandSettings` と同じく、触った瞬間に保存する（保存/キャンセルのある下書きにはしない）。
- セットの数、行の数に上限は設けない。

### 2.3 ピッカー

- グローバルキー「ピッカーを開く」で、メインディスプレイの中央に出す。既定キーはなし（既存の新規コマンドと同じ方針）。
  メニューバーのメニューにも「レイアウトセット…」を置き、同じピッカーを開く。
- 構成はモックのとおり。上に検索欄とセット数、中にセットの行、下にキーのヒント。
  行は左から: 区画グリフ（行の区画を 1 枚の画面に重ねたもの）、名前、内訳の要約、デスクトップ番号のバッジ、割当キー。
- 検索は名前とアプリ名への部分一致（大文字小文字を区別しない）。曖昧一致はしない。
- キー操作: ↑↓ で選択、Enter で適用して閉じる、esc で閉じる、→ / ← で選択中のセットの内訳を開閉、⌘Enter で設定画面のそのセットを開く。
  クリックでも適用する。
- 内訳を開くと、行ごとに「アプリ名、区画名、デスクトップ番号」を出す。適用前の予告であり、ここではウィンドウの照合はしない
  （モックの「起動していない・飛ばします」のような照合結果は適用後の結果表示に出す。§2.5）。
- ピッカーが開いている間（tatami 自身が前面のとき）に既存 27 コマンドのキーを押しても何もせず beep する。
  判定は `ShortcutRegistrar` のハンドラで `NSApp.isActive` を見て行い、`SnapEngine` には手を入れない。
  ピッカー自身や設定画面を区画に置いてしまう事故を防ぐための措置で、ピッカーを閉じれば従来どおり動く。
- セットが 0 件のときは「設定でセットを作ってください」と 1 行出し、Enter で設定画面を開く。

### 2.4 適用の挙動

1. ピッカーを閉じる（ピッカーから呼ばれた場合）。
2. 行を上から順に処理する。`action` と `desktop` がともに nil の行は無視する。それ以外の行ごとに:
   1. `bundleIdentifier` が一致する起動中の通常アプリを探す。なければ「起動していない」として飛ばす。
   2. そのアプリの窓（最小化を含む、全デスクトップ）から、`titleFilter` に合い、フルスクリーンでなく、まだ他の行に使っていないものを選ぶ。
      候補が複数あれば §3.4 の並び（いまのデスクトップで見えている窓を前面順に、そのあとに残り）で最初のもの。
      起動しているが合う窓がなければ「合う窓がない」、合う窓がフルスクリーンだけなら「フルスクリーン」として飛ばす。
   3. 最小化されていれば戻す。
   4. `desktop` がない行は窓を `AXRaise` するだけで、アプリはアクティブにしない（アプリ切替を行数分起こさないため。
      別デスクトップにある窓でも `setFrame` は効くので、その場では切り替えずに配置する）。
   5. `desktop` がある行はアプリをアクティブにして窓を raise し、§5 の手順でそのデスクトップへ移す。
      移動の成否は §5 のとおり検知し、失敗は「失敗」として記録する。移動に失敗しても手順 6 の配置は行う（少なくとも並ぶことを優先する）。
   6. `action` があれば、窓がいまある画面の visibleFrame で `LayoutCalculator.frame(for:in:current:)` を計算し、
      既存の SnapEngine と同じ補正（最小サイズではみ出したら内側へ寄せる）をかけて適用する。
3. 全行が終わったら結果を表示する（§2.5）。最後に `desktop` を処理した行の窓が前面に残り、利用者はそのデスクトップにいる。

- 1 行の失敗（AX エラー、§5 の各種失敗）はその行を「失敗」として記録し、次の行へ進む。全体を中断しない。
  1 つの行が「配置した」と「移動に失敗した」の両方を持つことがある。
- 適用中は「適用中…」の HUD を出し、終わったら結果の HUD に置き換える。
- アクセシビリティ権限がなければ、既存コマンドと同じく権限を要求して何もしない。
- 適用中は同じセットの再適用を受け付けない（二重に走らせない）。別のセットや単発コマンドも、適用中は無視して beep する。
- 既存の `CycleMemory`（ループ系の記憶）は適用の最後にクリアする。配置が変わったあとに古い記憶でループが続くのを避ける。

### 2.5 結果の表示

- 適用が終わったら、画面中央下に 2 秒だけ HUD（音量表示のような小さなパネル）を出す。
  例: 「連絡: 3 件中 2 件を配置 ・ Teams は起動していません」。全件成功なら「連絡: 3 件を配置」。
- 飛ばした理由は「起動していない」「合う窓がない」「フルスクリーン」と、失敗の各種（§5 の `SpaceMoveError` ごとに文言を持つ）。
  行の順に「 ・ 」でつなぐ。表示時間は文字数に応じて 2〜4 秒。
- 通知センター（UserNotifications）は使わない。権限の確認が増えるわりに、見たいのはその瞬間だけのため。

### 2.6 セットの作り方

**手で組む**: 設定画面の「セット」タブで「セットを追加」→ 名前を入れ、行を追加する。
行は「アプリ（起動中の通常アプリの一覧から選ぶ。一覧にないものは bundle identifier を直接入力）」
「タイトルの絞り込み（任意）」「区画（27 個から。カテゴリ別のメニューでグリフ付き。『変えない』も選べる）」
「デスクトップ（1〜10 または『変えない』）」。行はドラッグで並び替え、削除できる。

**いまの配置を保存**: 同じタブの「いまの配置を保存」を押すと、

1. いま表示中のデスクトップで画面に見えている通常ウィンドウ（レイヤー 0、デスクトップ要素を除く、tatami 自身を除く）を前面から順に集める。
2. 各窓の枠を、その窓がある画面の visibleFrame で 27 区画それぞれの枠と比べ、重なり率（IoU）が最大かつ 0.9 以上の区画を `action` にする。
   どれも 0.9 未満なら `action = nil`（変えない）。
3. 「このセットはデスクトップ何番ですか」を 1 回だけ聞く（1〜10、または「指定しない」）。答えを全行の `desktop` に入れる。
   macOS は現在のデスクトップ番号を公開 API で教えてくれないため、tatami は推測しない。
4. `titleFilter` は常に空にする。ブラウザのようにタイトルがアクティブなタブで変わるアプリでは、取り込んだ瞬間のタイトルは
   翌日に当たらないため。同じアプリの窓が複数ある行は、行の順（前面順）で当てる。
   設定画面ではそうした行に「同じアプリが複数あります。区別するなら絞り込みを入れてください」と添える。
5. 新しいセット「名称未設定」として行を並べ、編集状態で開く。利用者はここで名前を付け、要らない行を消す。

### 2.7 ショートカット

- 「ピッカーを開く」は `KeyboardShortcuts.Name("layoutSets.picker")`、既定キーなし。
- セットごとのキーは `KeyboardShortcuts.Name("layoutSet.<uuid>")`、既定キーなし。
  セットを削除したら `KeyboardShortcuts.reset` でキーも消す（UserDefaults にゴミを残さない）。
- セットの追加・削除時に ShortcutRegistrar がハンドラを登録・解除する。既存の 27 コマンドの登録には触らない。

### 2.8 セットアップ要件

- 行き先の指定に macOS の「デスクトップ N へ切り替え」ショートカットを使う（§5）。
  これはシステム設定 → キーボード → キーボードショートカット → Mission Control にあり、初期状態ではオフ。
  利用者が自分でオンにする必要がある。
- tatami は `com.apple.symbolichotkeys` の設定を読み、デスクトップ番号を持つ行があるのにその番号のショートカットがオフなら、
  設定画面の「セット」タブの上部と、適用後の HUD に「デスクトップ 3 へ切り替えるショートカットがオフです」と出す。
  システム設定を開くボタンを添える。
- Mission Control の「最新の使用状況に基づいて操作スペースを自動的に並べ替える」（`com.apple.dock` の `mru-spaces`、未設定ならオン）が
  オンだと、デスクトップの番号が使うたびに入れ替わり、番号で行き先を指せない。利用者の環境では初期状態どおりオンである。
  tatami は適用のたびにこの値を読み、オンなら **デスクトップ番号への移動を飛ばして区画の配置だけ行う**
  （番号が信用できない状態で ⌃N を送ると、無関係なデスクトップへ運んでしまうため）。HUD には
  「自動並べ替えがオンなのでデスクトップ移動を飛ばしました」と出す。
  「セット」タブにはオンのとき警告を出し、「オフにする」ボタンを置く。押すと「Dock を再起動します。デスクトップの並びが変わることがあります」
  という確認を出し、了承後に `defaults write com.apple.dock mru-spaces -bool false` と `killall Dock` を tatami が実行する。
  確認なしには実行しない。オフなら警告は出ず、設計どおり番号で運ぶ。
  （レビューでは「個人ユーティリティが Dock を再起動する経路を持つのは責任範囲を超える。システム設定を開くだけでよい」という指摘があった。
  利用者がボタンを望んだため残すが、書き込みはテスト対象外であり、失敗したらその旨を表示して利用者にシステム設定を案内する。）
- デスクトップ番号は Mission Control の並び全体の通し番号で、複数ディスプレイでは別のディスプレイのデスクトップを指すことがある。
  複数ディスプレイでのデスクトップ指定は本設計の対象外とし、README には「番号は Mission Control の並びの通し番号」と書く。

### 2.9 スコープ外

- アプリの起動（起動していない行は飛ばす）。
- デスクトップの作成・削除、名前付け。
- 複数ディスプレイにまたがるデスクトップ指定、ディスプレイ間の移動。
- スリープ復帰やディスプレイ接続をきっかけにした自動適用。
- セットのエクスポート/インポート、iCloud 同期。
- Stage Manager。フルスクリーンの窓は AX の一覧に含まれるので、`kAXFullScreenAttribute` で見分けて「フルスクリーン」として飛ばす（対象にはしない）。
- デスクトップの総数の検出（`com.apple.spaces` の plist は macOS のバージョンで形が変わるため読まない）。存在しない番号への移動は §5 の成否検知で「失敗」になる。
- ピッカーでの曖昧検索、使用頻度順の並び替え。

## 3. アーキテクチャ

### 3.1 変更の全体像

```
TatamiApp
 ├─ MenuBarExtra ─ MenuBarView (+ 「レイアウトセット…」)
 ├─ Settings ─ SettingsView (TabView: 既存 6 タブ + LayoutSetsTab)
 │     └─ LayoutSetsTab ─ LayoutSetEditor / LayoutRowEditor / 「いまの配置を保存」
 │           ├─ LayoutSetStore (保存)  ──────────────┐
 │           └─ LayoutCapture (いまの配置 → 行)      │
 ├─ PickerPanel (NSPanel) ─ PickerView ─ LayoutSetStore│
 └─ ShortcutRegistrar ─ 27 コマンド + picker + セットごと ◄┘
       │                      │
       ▼                      ▼
 SnapEngine.perform(command)  LayoutSetRunner.apply(set)
       │                      │  LayoutSetPlanner (純粋: 行 ↔ 窓の照合、計画)
       │                      │  SpaceMover (タイトルバー掴み + ⌃N)
       └──── WindowPlacer ────┘  (区画計算 + はみ出し補正。SnapEngine から切り出す)
                │
        WindowService / WindowEnumerator / ScreenProviding
```

- 依存方向は従来どおり App → Engine → System/Model。
- `SnapEngine` の「区画を計算して適用し、はみ出しを補正する」部分を `WindowPlacer` に切り出し、
  単発コマンドとセット適用の両方から使う。SnapEngine の外から見える振る舞いは変えない。
- `LayoutSetPlanner` は I/O を持たない純粋な型にし、照合と飛ばし理由の決定をテストで固める。
  `LayoutSetRunner` が Planner の計画を順に実行する。

### 3.2 Model（新設: Tatami/Model/LayoutSet.swift）

```swift
struct LayoutSet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rows: [LayoutRow]
}

struct LayoutRow: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String
    var titleFilter: String
    var action: SnapAction?
    var desktop: Int?
}
```

- `SnapAction` に `Codable`（rawValue 文字列）を足す。ケース名を保存するので、ケースの改名は保存互換を壊す。
  コメントでその旨を残す（`SnapCommand.rawValue` と同じ扱い）。
- `desktop` は 1...10 に限る。デコード時に範囲外なら nil に丸める。
- `action` のデコードで未知のケース名（将来の版で足された区画を古い版で読んだ場合）は nil に丸める。
  1 行の失敗でセット全体を壊れたデータ扱いにしない。

### 3.3 LayoutSetStore（新設、App 層）

```swift
@MainActor @Observable
final class LayoutSetStore {
    init(defaults: UserDefaults = .standard)
    private(set) var sets: [LayoutSet]
    func set(id: UUID) -> LayoutSet?
    func add(_ set: LayoutSet)
    func update(_ set: LayoutSet)
    func remove(id: UUID)
    func move(fromOffsets: IndexSet, toOffset: Int)
    @ObservationIgnored var onChange: (([LayoutSet]) -> Void)?   // ShortcutRegistrar がセットのキー登録を合わせ直す
}
```

- 保存先は UserDefaults キー `layoutSets.v1`、値は `[LayoutSet]` を JSON エンコードした Data。
  `CommandSettings` と同じく UserDefaults を注入できるようにし、テストでは suite 付きを使う。
- デコードに失敗したら空配列として起動し、壊れたデータは `layoutSets.v1.corrupt` に退避してログに残す（黙って上書きしない）。
- 1 つのファイルや別ストレージにしない理由: セットは多くても十数件で、既存設定と同じ場所にある方が見通しがよい。

### 3.4 ウィンドウの列挙（System 層）

既存の `WindowService` は「最前面のフォーカス窓」しか扱わない。セットには列挙とタイトルが要るので、別のプロトコルを足す。

```swift
struct WindowInfo: Hashable, Sendable {
    let handle: WindowHandle
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let title: String
    let frameAX: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool          // kAXFullScreenAttribute ("AXFullScreen")
}

@MainActor
protocol WindowEnumerating {
    /// 起動中の通常アプリ（activationPolicy == .regular）の窓。全デスクトップ、最小化・フルスクリーンを含む。
    /// 並びは「いまのデスクトップで見えている窓を前面順に、そのあとに残り（別デスクトップ・最小化）を AX の順で」。
    /// アプリが起動していなければ nil、起動しているが窓がなければ []。
    func windows(ofBundleIdentifier id: String) -> [WindowInfo]?
    /// いまのデスクトップで画面に見えている通常ウィンドウを前面から順に。「いまの配置を保存」用。
    func onScreenWindows() -> [WindowInfo]
    /// いまのデスクトップで window が画面に見えているか。SpaceMover の事前・事後確認用。
    func isOnScreen(_ window: WindowHandle) -> Bool
}

@MainActor
protocol WindowService {   // 既存に追加
    func unminimize(_ window: WindowHandle) throws
    func raise(_ window: WindowHandle) throws      // アプリの activate + AXRaise
}
```

- `windows(ofBundleIdentifier:)` は `NSWorkspace.shared.runningApplications` から pid を引き、`kAXWindowsAttribute` を読む。
  各要素の `kAXTitleAttribute`、`kAXMinimizedAttribute`、`kAXFullScreenAttribute`、位置と大きさを読む。
  AX の窓一覧はデスクトップをまたいで返り、フルスクリーンの窓も含む（Planner が除く）。
  AX の順は前面順が保証されないので、CGWindowList（下）で見えている窓を前面順に先頭へ並べ直す。
- `onScreenWindows()` は `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` で
  レイヤー 0、`kCGWindowAlpha > 0`、所有者が通常アプリ（`activationPolicy == .regular`）、tatami 自身でない窓を前面順に取り、
  所有者 pid ごとに AX の窓一覧と枠の一致（各辺 ±2pt）で突き合わせて `WindowHandle` とタイトルを得る。
  一致した AX 要素は候補から消費する（同じ枠の窓が 2 枚あっても同じ要素に二重一致しない）。一致しない窓は捨てる。
- `isOnScreen(_:)` は同じ突き合わせで、その窓が CGWindowList の on-screen にあるかを返す。
- `AXUIElementSetMessagingTimeout` は既存と同じ 1 秒。応答しないアプリで全体が止まらないようにする。
  `onScreenWindows()` は見えている pid の数だけ AX を叩くので、応答しないアプリが複数あるとその秒数だけ止まる。取り込みボタンでしか使わない。

### 3.5 LayoutSetPlanner（新設、Engine 層、純粋）

```swift
enum SkipReason: Equatable, Sendable { case appNotRunning, noMatchingWindow, fullScreen }

struct PlannedStep: Equatable, Sendable {
    let row: LayoutRow
    let window: WindowInfo
}

struct SkippedRow: Equatable, Sendable {
    let row: LayoutRow
    let reason: SkipReason
}

struct LayoutPlan: Equatable, Sendable {
    let steps: [PlannedStep]
    let skipped: [SkippedRow]
}

enum LayoutSetPlanner {
    /// windowsByBundle: bundleIdentifier → その順の窓（起動しているが窓なしは []、起動していなければキーなし）。
    /// 行の順に照合し、使った窓は次の行の候補から外す。何もしない行は無視する。
    static func plan(_ set: LayoutSet, windowsByBundle: [String: [WindowInfo]]) -> LayoutPlan
}
```

- `titleFilter` が空なら先頭の未使用の窓、空でなければタイトルに部分一致（`localizedCaseInsensitiveContains`）する先頭の未使用の窓。
- `windowsByBundle` にキーがなければ `appNotRunning`。あるが合う窓がなければ、合う窓のうちフルスクリーンのものがあれば `fullScreen`、なければ `noMatchingWindow`。
- フルスクリーンの窓は候補から外す（raise でフルスクリーン空間へ飛び、タイトルバーがないため掴めない）。

### 3.6 WindowPlacer（SnapEngine から切り出し、Engine 層）

```swift
@MainActor
struct WindowPlacer {
    init(windowService: any WindowService, screens: any ScreenProviding)
    /// 窓がいまある画面で action の枠を計算して適用し、はみ出しを補正する。適用後の AX 枠を返す。
    func place(_ window: WindowHandle, action: SnapAction) throws -> CGRect
}
```

- 中身は現在の `SnapEngine.perform` の手順 4〜6（画面特定、`LayoutCalculator.frame`、`setFrame`、`originKeptInside`）。
- `SnapEngine` はこれを呼ぶ形に書き換える。既存の SnapEngineTests はそのまま通ること。

### 3.7 SpaceMover（新設、System 層）

```swift
@MainActor
protocol SpaceMoving {
    /// window を「デスクトップ desktop へ切り替え」のショートカットで運ぶ。
    /// 呼び出し側は raise 済みであること。move 自身が「いまのデスクトップに見えている」「掴む点の直下がその窓」を確かめてから掴む。
    func move(_ window: WindowHandle, toDesktop desktop: Int) async throws
}

enum SpaceMoveError: Error, Equatable, Sendable {
    case shortcutDisabled(desktop: Int)   // Mission Control のショートカットがオフ
    case modifiersHeld                    // 修飾キーが離されないまま 1 秒過ぎた
    case windowNotOnScreen                // raise したのに 1 秒以内にいまのデスクトップに現れない
    case noGrabPoint                      // タイトルバーに部品でない点が見つからない
    case interrupted                      // 掴んでいる間に利用者がマウスを動かした
    case spaceDidNotChange(desktop: Int)  // キーを送ってもデスクトップが切り替わらない（存在しない番号、またはすでにそこ）
    case windowLeftBehind                 // 切り替わったが窓が付いてこなかった
    case eventPostFailed
}
```

実装と手順は §5。`MissionControlShortcuts`（§3.8）からキーを、`WindowEnumerating.isOnScreen` から見えているかを引く。

### 3.8 MissionControlShortcuts（新設、System 層）

```swift
struct KeyCombo: Equatable, Sendable { let keyCode: CGKeyCode; let modifiers: CGEventFlags }

protocol MissionControlShortcutReading: Sendable {
    /// 「デスクトップ N へ切り替え」が有効なら、そのキー。無効または未設定なら nil。
    func switchToDesktopShortcut(_ desktop: Int) -> KeyCombo?
}
```

- `CFPreferencesCopyAppValue("AppleSymbolicHotKeys", "com.apple.symbolichotkeys")` を読む。
  デスクトップ 1〜10 は ID 118〜127。各項目の `enabled` と `value.parameters`（[文字, キーコード, 修飾キーのビット]）を使う。
  利用者がキーを変えていても、ここから読んだキーをそのまま送るので追従できる（Rectangle Pro が手動設定にしている部分）。
- 解析は辞書を受け取る純粋関数に分け、テストで固める。
- 設定アプリが保存するまで反映されないことがあるので、適用のたびに読み直す（キャッシュしない）。

同じファイルに Dock 側の設定も置く。

```swift
protocol DockPreferencesReading: Sendable {
    /// 「最新の使用状況に基づいて操作スペースを自動的に並べ替える」。未設定なら true。
    var rearrangesSpacesAutomatically: Bool { get }
    /// オフにして Dock を再起動する（§2.8）。確認は呼び出し側（設定画面）が行う。
    func disableAutomaticRearrangement() throws
}
```

- 読みは `CFPreferencesCopyAppValue("mru-spaces", "com.apple.dock")`。書きは `CFPreferencesSetAppValue` + `CFPreferencesAppSynchronize`
  のあと `Process` で `/usr/bin/killall Dock`。
- `LayoutSetRunner` は適用の最初に `rearrangesSpacesAutomatically` を読み、true なら全行の `desktop` を nil 扱いにして
  結果に `skippedDesktopMoves: true` を立てる。HUD はこれを見て文言を足す。

### 3.9 LayoutSetRunner（新設、Engine 層）

```swift
@MainActor
final class LayoutSetRunner {
    init(enumerator: any WindowEnumerating, windowService: any WindowService, placer: WindowPlacer,
         spaceMover: any SpaceMoving, dockPreferences: any DockPreferencesReading,
         permission: any PermissionChecking,
         onStarted: @escaping @MainActor (LayoutSet) -> Void,
         onFinished: @escaping @MainActor (LayoutRunResult) -> Void)
    private(set) var isRunning: Bool
    /// 実行中・権限なしなら何もせず false を返す（呼び出し側が beep する）。
    @discardableResult
    func apply(_ set: LayoutSet) async -> Bool
}

struct FailedRow: Sendable { let row: LayoutRow; let error: any Error }

struct LayoutRunResult: Sendable {
    let set: LayoutSet
    let placed: [LayoutRow]            // action を適用できた行
    let skipped: [SkippedRow]          // 照合で飛ばした行
    let failed: [FailedRow]            // 移動または配置で例外が出た行（placed と重なりうる）
    let skippedDesktopMoves: Bool      // 自動並べ替えがオンでデスクトップ移動を飛ばした
    var summary: String                // HUD の文言（§2.5）
}
```

- §2.4 の順で進める。`onStarted` は「適用中…」の HUD 用。
- `async` にするのは §5 の待ちのため。AX 呼び出し自体はメインアクターで行う。
- `windows(ofBundleIdentifier:)` が nil（起動していない）なら `windowsByBundle` にキーを入れず、`[]`（窓なし）ならキーを入れて空配列にする。
  起動しているが窓のないアプリに「起動していません」と出さないため。

### 3.10 LayoutCapture（新設、Engine 層）

```swift
enum RegionMatcher {
    /// frameNS に最も近い区画。IoU が threshold 未満なら nil。
    static func closestAction(to frameNS: CGRect, in visible: CGRect, threshold: CGFloat = 0.9) -> SnapAction?
}

@MainActor
struct LayoutCapture {
    init(enumerator: any WindowEnumerating, screens: any ScreenProviding)
    /// いまの配置を行にする。desktop は全行に同じ値を入れる。
    func capture(desktop: Int?) -> [LayoutRow]
}
```

- `RegionMatcher` はサイズ系 3 つ（maximizeHeight / maximizeWidth / center）を候補から外す。これらは現在枠に依存し、保存の意味がない。
- `titleFilter` は常に空（§2.6）。

### 3.11 ShortcutRegistrar の拡張

```swift
enum ShortcutRegistrar {
    static let pickerName: KeyboardShortcuts.Name                                            // "layoutSets.picker"
    static func register(engine: SnapEngine, settings: CommandSettings, isBusy: @escaping @MainActor () -> Bool)   // 既存 + ガード
    static func registerLayoutSets(store: LayoutSetStore, isBusy: @escaping @MainActor () -> Bool,
                                   onPicker: @escaping @MainActor () -> Void,
                                   onApply: @escaping @MainActor (LayoutSet) -> Void)
}
```

- `registerLayoutSets` は「ピッカーを開く」と各セットのハンドラを登録し、`store.onChange` で追加・削除に追従する。
  削除されたセットは `KeyboardShortcuts.removeHandler(for:)` と `KeyboardShortcuts.reset` でキーごと消す。
- Registrar は Runner や Picker を知らず、クロージャで受け取る。
- ピッカーを開くキーも含め、すべてのハンドラは「適用中（`isBusy`）なら beep して無視」。既存 27 コマンドはさらに「tatami 自身が前面なら beep」（§2.3）。

### 3.12 AppModel

- `LayoutSetStore`、`LayoutSetRunner`、`PickerController` を保持し、`start()` で `registerLayoutSets` を呼ぶ。
  テストホスト下では既存と同じく何もしない。

## 4. UI

### 4.1 ピッカー（PickerPanel / PickerView）

- `NSPanel`（`.titled` なし、`.nonactivatingPanel` ではなく通常の key window。検索欄に文字を入れるため）。
  幅 620、高さは内容に応じる。メインディスプレイの中央、少し上寄り（モックと同じく上から 1/5 程度）。
  `level = .floating`、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`
  （どのデスクトップでも出る、フルスクリーン空間の上にも出せてその空間を離れない、Mission Control に出ない）。
  フォーカスを失ったら閉じる。
- 中身は SwiftUI（`NSHostingView`）。見た目はモックに従う。アクセント色は `Color.accentColor`。
  行のグリフは `RegionGlyph` を拡張し、複数の区画を 1 枚に重ねて描けるようにする（`RegionGlyph(actions: [SnapAction])`）。
- 選択中の行は塗りつぶし、未選択は透明。デスクトップ番号は枠線のバッジ、キーは角丸の小さなラベル、未割当なら「未割当」。
- キー操作は §2.3。↑↓ は端で止まる（循環しない）。検索欄に文字を入れると一覧が絞られ、選択は先頭に戻る。

### 4.2 設定画面「セット」タブ（LayoutSetsTab）

- 既存の `TabView` の末尾にタブを足す。アイコンは `rectangle.3.group`（SF Symbols）。
  タブごとの幅は変えられないので、ウィンドウ幅を 480 から 640 に広げる。既存タブは `Form` なので広がっても崩れない。
- 上部: 「ピッカーを開く」の `KeyboardShortcuts.Recorder`。その下に、§2.8 の警告（該当があるときだけ）。
- 中央: セットの一覧（`List`）。各セットは `DisclosureGroup` で、ヘッダに名前（インライン編集可）と `Recorder`、
  開くと行の一覧と「行を追加」。行は `LayoutRowEditor`。
- 行のエディタ: アプリの `Picker`（起動中の通常アプリを名前順。先頭に「bundle identifier を入力…」）、
  絞り込みの `TextField`（プレースホルダ「タイトルに含む文字（任意）」）、
  区画の `Menu`（カテゴリごとのサブメニュー、各項目に `RegionGlyph` と `SnapCommand.title` に対応する区画名。先頭に「変えない」）、
  デスクトップの `Picker`（「変えない」、1〜10）、削除ボタン。行は `onMove` で並び替え。
- 下部: 「セットを追加」「いまの配置を保存」。後者は押すと §2.6 の番号を聞くシートを出し、確定で新しいセットを編集状態で開く。
- 区画名は既存の `SnapCommand.title` と揃える。`SnapAction` には表示名がないので、`SnapAction.title` を足し、
  単発コマンドと同じ文字列にする（例: `.leftTwoThirds` → 「左 2/3」、`.leftHalf` → 「左半分」）。

### 4.3 メニューバー

- 「設定…」の上に「レイアウトセット…」を足す。セットが 1 件以上あれば、その下にセット名を直接並べ、選ぶと即適用する。

### 4.4 結果 HUD

- 中央下（下端から 120 pt）に出る角丸のパネル。文言は §2.5。文字数に応じて 2〜4 秒で消える。クリックで即閉じる。
  適用中は「<セット名> を適用中…」を出し、終了時に結果へ置き換える。再表示のときは前の消去タイマーを止める。
- `NSPanel`、`level = .statusBar`、`ignoresMouseEvents = false`、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`。

## 5. スペース間移動の仕組み

公開 API がないため、macOS の「ウィンドウを掴んだままデスクトップ切替キーを押すと窓ごと移る」挙動を使う。

この操作は、成功すれば目的の窓を運ぶが、失敗の仕方によっては**無関係な窓を運んでしまう**（掴んだ点に別の窓があった場合）。
そのため `move` は「掴む前に目的の窓がそこにあること」を必ず確かめ、確かめられなければ掴まない。

手順（`SpaceMover.move(_:toDesktop:)`。呼び出し側はアプリをアクティブにして窓を raise 済み）:

1. `MissionControlShortcuts` から「デスクトップ N へ切り替え」のキーを読む。nil なら `shortcutDisabled`。
2. 修飾キー（control / option / shift / command）が離されるまで待つ（`CGEventSource.flagsState(.combinedSessionState)` を 20 ms 間隔で、上限 1 秒）。
   超えたら `modifiersHeld`。押したまま ⌃N を送ると ⌃⌥N になり何も起きないため、黙って進まない。
3. 窓がいまのデスクトップに見えるまで待つ（`WindowEnumerating.isOnScreen` を 20 ms 間隔で、上限 1 秒。
   raise によるデスクトップ切替や最小化復帰のアニメーションが終わるのを待つ）。超えたら `windowNotOnScreen`。
4. 窓の現在枠を読み直し、掴む点の候補を順に試す: (a) `minX + 80, minY + 10`（信号機の右）、(b) `midX, minY + 10`（タイトルバー中央）、
   (c) `maxX - 40, minY + 10`（右端）、(d) `midX, minY + 3`（最上端の帯。タブ付きブラウザの空き）。
   各候補で `AXUIElementCopyElementAtPosition(systemWide, x, y)` を取り、その要素の `kAXWindowAttribute` が目的の窓と一致し、
   かつ要素の `kAXRoleAttribute` が操作部品（`AXButton`, `AXTab`, `AXRadioButton`, `AXTextField`, `AXPopUpButton`, `AXMenuButton`, `AXCheckBox`, `AXSlider`）
   でない最初の候補を採る。どれも通らなければ `noGrabPoint`（窓は動かさない）。
5. いまのマウス位置を保存する。
6. `NSWorkspace.activeSpaceDidChangeNotification` の購読を始める。
7. `CGEvent` で掴む点へ `mouseMoved` → `leftMouseDown` を送る（`.cghidEventTap`）。`dragOffset` が 0 でなければ続けて
   `leftMouseDragged` を掴む点 + `(dragOffset, 0)` へ送る（ドラッグ閾値を越えないと移動を始めないアプリ向け。既定 0、スパイクで決める）。
8. `afterMouseDown`（既定 80 ms）待つ。その間に実マウスが掴む点から 10 pt 以上離れていたら `interrupted`。
9. 読んだキーで `keyDown` → `keyUp` を送る（修飾キーは `flags` に立てる）。
10. 6 の通知を待つ（上限 `spaceChangeTimeout`、既定 1 秒）。来なければ `spaceDidNotChange(desktop:)`（存在しない番号、またはすでにそのデスクトップ）。
    来たらさらに `afterSpaceChange`（既定 150 ms）待つ。
11. `leftMouseUp` を送る。
12. マウス位置を 5 の位置へ戻す（`CGWarpMouseCursorPosition`）。
13. 窓が新しいデスクトップで見えているか `isOnScreen` で確かめる（上限 500 ms）。見えなければ `windowLeftBehind`。

- 7 以降で例外が出たら必ず `leftMouseUp` を送ってから投げる（押しっぱなしにしない）。`defer` で行う。
- 待ち時間と `dragOffset` は `SpaceMoverTiming` にまとめ、スパイク（§8）の結果で既定値を決める。
- `spaceDidNotChange` のとき窓はいまのデスクトップに残る。続く区画の適用はそこで行う（§2.4 手順 5）。
- 呼び出し側（Runner）は `desktop` のある行で `NSRunningApplication.activate()` → `raise` のあと `move` を呼ぶ。
  macOS 14 以降の協調アクティベーションで activate が拒否されることがあるが、その場合は手順 3 で `windowNotOnScreen` になり、
  無関係な窓を掴むことはない。

## 6. エラー処理と互換性

- 既存ユーザーには `layoutSets.v1` がないので空で起動する。既存の設定・キーには触らない。
- `SnapAction` の `Codable` 追加はケース名で保存する。将来の改名は保存互換を壊すので、改名するときは移行を書く。
- セット適用中のショートカットは無視して beep する。ピッカーが開いているときの単発コマンドは通常どおり動く。
- `SpaceMover` が投げた行は「失敗」として HUD に出すが、区画の配置は行ってから次の行へ進む。
- アクセシビリティ権限が途中で取り消された場合、AX 呼び出しが失敗して行が「失敗」になる。既存と同じく beep し、権限メニューが出る。

## 7. テスト

| 対象 | 内容 |
|---|---|
| LayoutSetTests | `LayoutSet` / `LayoutRow` の Codable 往復。`SnapAction` のケース名で保存される。`desktop` の範囲外（0、11）は nil に丸まる。未知の `action` 名は nil に丸まりセット全体は読める。 |
| LayoutSetStoreTests | 空で起動。add / update / remove / move が保存され、別インスタンスで読める。壊れた JSON は退避キーに移り空で起動。`onChange` が呼ばれる。 |
| LayoutSetPlannerTests | 絞り込みなしで先頭の窓。絞り込みありで部分一致（大文字小文字無視）。同じアプリの 2 行で別の窓が選ばれる。起動していない → appNotRunning。起動しているが窓なし → noMatchingWindow。フルスクリーンだけ → fullScreen。最小化の窓も候補になる。何もしない行は照合されない。 |
| RegionMatcherTests | 27 区画ちょうどの枠がその区画になる。少しずれた枠（IoU 0.95）も同じ区画。自由サイズ（IoU 0.5）は nil。サイズ系 3 つは候補に出ない。 |
| MissionControlShortcutsTests | 固定の辞書から、有効な 118 → ⌃1 のキーコードと修飾キーを得る。`enabled = false` → nil。項目なし → nil。119〜127 → デスクトップ 2〜10。 |
| WindowPlacerTests | 既存 SnapEngineTests の配置部分を移し、`FakeWindowService` で中央に配置・はみ出し補正が従来どおり。 |
| LayoutSetRunnerTests | Fake の enumerator / windowService / spaceMover / placer / dockPreferences で、2 行成功 1 行 skip の結果。デスクトップありの行で activate + spaceMover が呼ばれ、なしの行では raise だけ。spaceMover が投げたら failed に入るが配置は行い、次の行へ進む。自動並べ替えがオンなら spaceMover が一度も呼ばれず `skippedDesktopMoves` が立つ。両方 nil の行は照合されず件数にも入らない。起動しているが窓のないアプリは「合う窓がない」。`onStarted` が最初に呼ばれる。 |
| SpaceMoverTests | 掴む点の候補（純粋関数）が 4 点で正しい座標。幅 200 未満では (a) と (c) を外す。 |
| DockPreferencesTests | 値なし → true。false が保存されていれば false。（書き込みと Dock 再起動はテストしない） |
| LayoutCaptureTests | Fake の onScreenWindows から行ができる。titleFilter は常に空。 |
| SnapEngineTests / 既存 | 変更なしで通る。 |

`SpaceMover` の実装、ピッカー、設定タブ、HUD は OS と UI に依存するので単体テストは書かない。実機確認の項目は計画側で列挙する。

## 8. リスクと先に確かめること

計画の最初に、捨てる前提のスパイクで次を確かめる。結果で §5 の待ち時間と掴む点を決める。

スパイクの形: 別バイナリにはしない（署名が変わるたびにアクセシビリティ権限を取り直すことになる）。
tatami 本体のメニューに、`defaults write dev.hidekingerz.tatami debugMenu -bool YES` のときだけ出る「デバッグ」項目を足し、
そこから「最前面の窓をデスクトップ N へ」「最前面アプリの窓一覧をログに出す」などを呼べるようにする。
実行と観察は利用者が手元で行い、結果を報告してもらう（Claude Code のシェルからは画面を観察できない）。
計画はこのための手順書と確認表を含める。スパイクの結果を待つ間、Model・Store・Planner・ピッカー・設定タブなど
スペース移動と独立な部分は先に進めてよい。デバッグ項目は完成時に残してよいが、フラグなしでは出ないこと。

1. `leftMouseDown` + ⌃N + `leftMouseUp` の擬似操作で、Chrome / Safari / Finder / WezTerm / LINE / Discord / Teams の窓が macOS 26 で別デスクトップへ移るか。
   `leftMouseDragged` を挟む変種（`dragOffset` = 2）も試し、安定する方を既定にする。
   §5 手順 4 のヒットテストがどの候補点を選んだかもログで見る。移らないアプリがあれば「このアプリは対象外」と README に書く。
2. 別デスクトップにある窓に `activate` + `AXRaise` をすると、そのデスクトップへ切り替わるか。
   同じアプリの窓がいまのデスクトップにもある場合（切り替わらない可能性が高い）も試し、`windowNotOnScreen` で止まることを見る。
3. `kAXWindowsAttribute` が別デスクトップ・フルスクリーンの窓を返し、`kAXFullScreenAttribute` が読めるか。
4. `com.apple.symbolichotkeys` の ID 118〜127 と `parameters` の形が macOS 26 でも同じか。
5. いまのデスクトップで、目的の窓と同じ位置に別アプリの窓を置いた状態で、別デスクトップの窓を対象にする → 別アプリの窓が動かないこと（§5 の検証が効くこと）。
6. フルスクリーンのアプリの上でピッカーと HUD が出て、その空間を離れないこと。
7. WezTerm の `window_decorations` の値を記録する。`RESIZE`（タイトルバーなし）なら掴めないので README に書く。

これらが崩れた場合は設計に戻る。特に 1 が全滅なら、スペース移動を落として「いまのデスクトップで並べるだけ」に縮める判断を利用者に仰ぐ。

## 9. 付随作業

- README に「レイアウトセット」の節を足す: 作り方、ピッカー、デスクトップ移動の仕組みと制約
  （Mission Control ショートカットをオンにする、複数ディスプレイは対象外、存在しない番号は無視される）。
- 設定画面のウィンドウ幅の変更を既存の実機確認項目に反映する。

## 10. ビルダーに委ねること

- ピッカーと HUD の細かな寸法、アニメーション、フォントサイズ。
- 設定タブのレイアウトの細部（モックはピッカーのみ）。
- `WindowEnumerating` の AX 実装の詳細と、CG の窓情報と AX 要素の突き合わせの許容誤差。
- 待ち時間の最終値（§5、スパイクで決める）。
- テスト用 Fake の設計（既存の `TatamiTests/Fakes` に倣う）。
