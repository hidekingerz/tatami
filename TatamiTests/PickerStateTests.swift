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
