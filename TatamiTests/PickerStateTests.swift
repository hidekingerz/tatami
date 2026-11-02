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
