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
                   frameAX: CGRect(x: 0, y: 25, width: 800, height: 600), isMinimized: minimized, isFullScreen: false)
    }
    static let line = window("line", "LINE", pid: 1)
    static let discord = window("discord", "Discord", pid: 2, minimized: true)

    func makeRunner(rearranges: Bool = false,
                    onStarted: @escaping @MainActor (LayoutSet) -> Void = { _ in },
                    onFinished: @escaping @MainActor (LayoutRunResult) -> Void = { _ in }) -> LayoutSetRunner {
        LayoutSetRunner(enumerator: enumerator, windowService: windows,
                        placer: WindowPlacer(windowService: windows, screens: FakeScreenProvider.single),
                        spaceMover: mover, dockPreferences: FakeDockPreferences(rearrangesSpacesAutomatically: rearranges),
                        permission: permission, onScreenTimeout: .milliseconds(50), settleInterval: .zero,
                        onStarted: onStarted, onFinished: onFinished)
    }

    let set = LayoutSet(name: "連絡", rows: [
        LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird, desktop: 3),
        LayoutRow(bundleIdentifier: "discord", appName: "Discord", action: .centerThird, desktop: nil),
        LayoutRow(bundleIdentifier: "teams", appName: "Microsoft Teams", action: .rightThird, desktop: 3),
    ])

    /// 窓はすべて「いまのデスクトップに見えている」状態にしておく。別デスクトップの再現は各テストで外す。
    func allOnScreen() {
        enumerator.onScreenHandles = [Self.line.handle, Self.discord.handle]
    }

    /// 利用者がデスクトップ 1 にいて、LINE はデスクトップ 3 にある典型。switchTo(3) で切り替わり、LINE はそのまま見える。
    @Test func 成功と飛ばしが結果に入り移動は不要なら起こさない() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        var results: [LayoutRunResult] = []
        var started: [String] = []
        let runner = makeRunner(onStarted: { started.append($0.name) }, onFinished: { results.append($0) })
        let ok = await runner.apply(set)
        #expect(ok)
        #expect(started == ["連絡"])
        #expect(results.count == 1)
        let result = results[0]
        #expect(result.placed == [set.rows[0], set.rows[1]])
        #expect(result.skipped.map(\.reason) == [.appNotRunning])
        #expect(result.failed.isEmpty)
        #expect(!result.skippedDesktopMoves)
        #expect(mover.switchCalls == [3])                                          // 利用者を 3 へ
        #expect(mover.calls.isEmpty)                                               // LINE は 3 で見えているので掴まない
        #expect(windows.activateCalls == [Self.line.handle, Self.line.handle])     // desktop 行で 1 回 + 終わりに 1 回
        #expect(windows.raiseCalls == [Self.line.handle, Self.discord.handle])
        #expect(windows.unminimizeCalls == [Self.discord.handle])
        #expect(windows.setFrameCalls.count == 2)
        #expect(result.summary == "連絡: 3 件中 2 件を配置 ・ Microsoft Teams は起動していません")
    }

    /// LINE がデスクトップ 1 にあり、activate で利用者が 1 へ連れ戻される場合。掴んで 3 へ運ぶ。
    @Test func activateで別デスクトップへ切り替わった窓は掴んで運ぶ() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        windows.onRaise = { [mover] handle in
            if handle == Self.line.handle { mover.spaceChangeCount += 1 }   // activate が起こした切替
        }
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(mover.switchCalls == [3])
        #expect(mover.calls.map { $0.window } == [Self.line.handle])
        #expect(mover.calls.map { $0.desktop } == [3])
        #expect(results[0].failed.isEmpty)
    }

    /// 同じデスクトップへ運ぶ行が 2 つあっても、切替は 1 回、掴む操作は 0 回。
    @Test func 同じ番号への切替は1回だけで既にある窓は掴まない() async {
        let set = LayoutSet(name: "連絡", rows: [
            LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird, desktop: 3),
            LayoutRow(bundleIdentifier: "discord", appName: "Discord", action: .centerThird, desktop: 3),
        ])
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(mover.switchCalls == [3])
        #expect(mover.calls.isEmpty)
        #expect(results[0].placed.count == 2)
        #expect(results[0].summary == "連絡: 2 件を配置")
    }

    /// raise しても見えてこない（activate が拒否された等）行は失敗。配置は行う。
    @Test func 見えてこない窓は失敗にするが配置はする() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        enumerator.onScreenHandles = [Self.discord.handle]
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        let result = results[0]
        #expect(result.failed.map(\.row) == [set.rows[0]])
        if case .windowNotOnScreen? = result.failed[0].error as? SpaceMoveError {} else {
            Issue.record("windowNotOnScreen ではなく \(result.failed[0].error)")
        }
        #expect(result.placed == [set.rows[0], set.rows[1]])
        #expect(mover.calls.isEmpty)
        #expect(result.summary == "連絡: 3 件中 2 件を配置 ・ LINE を前面に出せませんでした ・ Microsoft Teams は起動していません")
    }

    @Test func spaceMoverが投げたらfailedに入るが配置は行い次の行へ進む() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        windows.onRaise = { [mover] _ in mover.spaceChangeCount += 1 }      // 毎回 activate で切り替わる想定
        mover.error = .shortcutDisabled(desktop: 3)
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        let result = results[0]
        #expect(result.failed.map(\.row) == [set.rows[0]])
        #expect(result.placed == [set.rows[0], set.rows[1]])
        #expect(windows.setFrameCalls.count == 2)
        #expect(result.summary == "連絡: 3 件中 2 件を配置 ・ デスクトップ 3 へ切り替えるショートカットがオフです ・ Microsoft Teams は起動していません")
    }

    /// 存在しない番号は最初の行で spaceDidNotChange になり、同じ番号の残りの行は掴まずに失敗にする。
    @Test func 切り替わらなかった番号は以後掴まない() async {
        let set = LayoutSet(name: "s", rows: [
            LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .leftThird, desktop: 5),
            LayoutRow(bundleIdentifier: "discord", appName: "Discord", action: .centerThird, desktop: 5),
        ])
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        mover.switchResult = false
        windows.onRaise = { [mover] _ in mover.spaceChangeCount += 1 }
        mover.error = .spaceDidNotChange(desktop: 5)
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(mover.calls.count == 1)
        #expect(results[0].failed.count == 2)
        #expect(results[0].summary == "s: 2 件を配置 ・ デスクトップ 5 へ切り替わりませんでした ・ デスクトップ 5 へ切り替わりませんでした")
    }

    @Test func 起動しているが窓がなければ合う窓がない() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord], "teams": []]
        allOnScreen()
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(results[0].skipped.map(\.reason) == [.noMatchingWindow])
        #expect(results[0].summary == "連絡: 3 件中 2 件を配置 ・ Microsoft Teams に合う窓がありません")
    }

    @Test func 自動並べ替えがオンならデスクトップ移動を飛ばす() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        var results: [LayoutRunResult] = []
        _ = await makeRunner(rearranges: true, onFinished: { results.append($0) }).apply(set)
        #expect(mover.switchCalls.isEmpty)
        #expect(mover.calls.isEmpty)
        #expect(results[0].skippedDesktopMoves)
        #expect(results[0].placed.count == 2)
        #expect(results[0].summary.hasSuffix(" ・ 自動並べ替えがオンなのでデスクトップ移動を飛ばしました"))
    }

    @Test func 権限がなければ何もせずfalse() async {
        permission.isTrusted = false
        var results: [LayoutRunResult] = []
        let started = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(!started)
        #expect(results.isEmpty)
        #expect(permission.requestAccessCount == 1)
        #expect(windows.raiseCalls.isEmpty)
    }

    @Test func 何もしない行は件数に入らず終わりに先頭行のアプリをアクティブにする() async {
        let set = LayoutSet(name: "s", rows: [
            LayoutRow(bundleIdentifier: "line", appName: "LINE"),
            LayoutRow(bundleIdentifier: "line", appName: "LINE", action: .maximize),
        ])
        enumerator.windowsByBundle = ["line": [Self.line]]
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(set)
        #expect(results[0].summary == "s: 1 件を配置")
        #expect(windows.activateCalls == [Self.line.handle])                       // desktop 行がないので終わりの 1 回だけ
    }

    @Test func 対象行がなければその旨() async {
        var results: [LayoutRunResult] = []
        _ = await makeRunner(onFinished: { results.append($0) }).apply(LayoutSet(name: "空"))
        #expect(results[0].summary == "空: 配置する行がありません")
        #expect(windows.activateCalls.isEmpty)
    }

    @Test func 行の順に処理する() async {
        enumerator.windowsByBundle = ["line": [Self.line], "discord": [Self.discord]]
        allOnScreen()
        _ = await makeRunner().apply(set)
        #expect(windows.raiseCalls == [Self.line.handle, Self.discord.handle])
    }
}
