import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

struct LayoutSetPlannerTests {
    /// テスト用の窓。pid ごとに別の AXUIElement を作って handle を区別する。
    static func window(_ bundle: String, _ title: String, pid: pid_t, minimized: Bool = false, fullScreen: Bool = false) -> WindowInfo {
        WindowInfo(handle: WindowHandle(element: AXUIElementCreateApplication(pid)), pid: pid,
                   bundleIdentifier: bundle, appName: bundle, title: title,
                   frameAX: CGRect(x: 0, y: 0, width: 100, height: 100), isMinimized: minimized, isFullScreen: fullScreen)
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

    @Test func 三行目は窓が尽きてnoMatchingWindow() {
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

    @Test func 起動しているが窓がなければnoMatchingWindow() {
        let plan = LayoutSetPlanner.plan(LayoutSet(name: "s", rows: [row("slack")]), windowsByBundle: ["slack": []])
        #expect(plan.skipped.map(\.reason) == [.noMatchingWindow])
    }

    @Test func フルスクリーンの窓は候補から外しそれしかなければfullScreen() {
        // pid を変えて handle を区別する（同じ pid だと CFEqual で同じ窓になる）。
        let full = Self.window("chrome", "GitHub", pid: 4, fullScreen: true)
        let plan = LayoutSetPlanner.plan(LayoutSet(name: "s", rows: [row("chrome"), row("chrome")]),
                                         windowsByBundle: ["chrome": [full, Self.chrome]])
        #expect(plan.steps.map(\.window) == [Self.chrome])
        #expect(plan.skipped.map(\.reason) == [.fullScreen])
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
