import Foundation
import Testing
@testable import Tatami

@MainActor
final class PickerStateTests {
    let suiteName = "dev.hidekingerz.tatamiTests.PickerState.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let sets = [
        LayoutSet(name: "作業", rows: [LayoutRow(bundleIdentifier: "wez", appName: "WezTerm", action: .leftTwoThirds)]),
        LayoutSet(name: "連絡", rows: [LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird)]),
    ]

    func items(_ tab: PickerTab, _ query: String, sets: [LayoutSet]? = nil, favorites: Set<SnapAction> = []) -> [PickerItem] {
        PickerState.items(tab: tab, sets: sets ?? self.sets, favorites: favorites, query: query)
    }

    // MARK: - タブごとの一覧

    @Test func セットタブは空の検索でセットだけ全部() {
        #expect(items(.sets, "").compactMap(\.setValue).map(\.name) == ["作業", "連絡"])
        #expect(items(.sets, "").allSatisfy { $0.region == nil })
    }

    @Test func 区画タブは空の検索で27区画をカテゴリ順() {
        #expect(items(.regions, "").compactMap(\.region) == SnapAction.allInCategoryOrder)
    }

    @Test func お気に入りは区画の先頭にカテゴリ順で浮く() {
        let regions = items(.regions, "", favorites: [.center, .rightThird]).compactMap(\.region)
        #expect(regions.prefix(2) == [.rightThird, .center])
        #expect(regions.count == 27)
        #expect(Set(regions).count == 27)
    }

    @Test func セット名はアプリ名でも前方一致() {
        #expect(items(.sets, "連").compactMap(\.setValue).map(\.name) == ["連絡"])
        #expect(items(.sets, "wez").compactMap(\.setValue).map(\.name) == ["作業"])
        #expect(items(.sets, "line").compactMap(\.setValue).map(\.name) == ["連絡"])
    }

    @Test func 検索は今のタブだけが対象() {
        #expect(items(.sets, "> 1/3").isEmpty)
        #expect(items(.regions, "> 1/3") == [.region(.rightThird)])
        #expect(items(.regions, "連").isEmpty)
    }

    @Test func セットが0件ならセットタブは空() {
        #expect(items(.sets, "", sets: []).isEmpty)
    }

    // MARK: - もう一方のタブの一致件数

    @Test func 検索が空ならもう一方の件数は0() {
        #expect(PickerState.otherTabMatchCount(tab: .sets, sets: sets, favorites: [], query: "") == 0)
        #expect(PickerState.otherTabMatchCount(tab: .regions, sets: sets, favorites: [], query: "  ") == 0)
    }

    @Test func 検索中はもう一方のタブで一致する件数() {
        #expect(PickerState.otherTabMatchCount(tab: .sets, sets: sets, favorites: [], query: "> 1/3") == 1)
        #expect(PickerState.otherTabMatchCount(tab: .regions, sets: sets, favorites: [], query: "連") == 1)
        #expect(PickerState.otherTabMatchCount(tab: .regions, sets: sets, favorites: [], query: "zzz") == 0)
    }

    // MARK: - タブの切り替えと記憶

    @Test func 未設定ならセットタブで始まる() {
        #expect(PickerState(defaults: defaults).tab == .sets)
    }

    @Test func タブを変えると保存され別インスタンスで読める() {
        let state = PickerState(defaults: defaults)
        state.tab = .regions
        #expect(defaults.string(forKey: PickerTab.defaultsKey) == "regions")
        #expect(PickerState(defaults: defaults).tab == .regions)
    }

    @Test func 不正な保存値はセットタブ() {
        defaults.set("bogus", forKey: PickerTab.defaultsKey)
        #expect(PickerState(defaults: defaults).tab == .sets)
    }

    @Test func toggleTabで行き来する() {
        let state = PickerState(defaults: defaults)
        state.toggleTab()
        #expect(state.tab == .regions)
        state.toggleTab()
        #expect(state.tab == .sets)
    }

    @Test func タブを変えると選択と内訳は戻り検索は残る() {
        let state = PickerState(defaults: defaults)
        state.query = "mi"
        state.selectedIndex = 3
        state.expandedID = sets[0].id
        state.tab = .regions
        #expect(state.selectedIndex == 0)
        #expect(state.expandedID == nil)
        #expect(state.query == "mi")
    }

    @Test func 開き直しても前回のタブのまま() {
        let state = PickerState(defaults: defaults)
        state.tab = .regions
        state.query = "mi"
        state.reset()
        #expect(state.tab == .regions)
        #expect(state.query == "")
    }

    @Test func タブのラベルともう一方() {
        #expect(PickerTab.allCases.map(\.label) == ["セット", "区画"])
        #expect(PickerTab.sets.other == .regions)
        #expect(PickerTab.regions.other == .sets)
    }
}
