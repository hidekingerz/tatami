import Foundation

/// 配置または移動に失敗した行と、その行で最初に起きたエラー。
struct FailedRow: Sendable {
    let row: LayoutRow
    let error: any Error
}

/// レイアウトセット 1 回分の適用結果。
struct LayoutRunResult: Sendable {
    let set: LayoutSet
    /// 成功した行。配置した行に加え、デスクトップ移動だけの行（配置なし）が誤りなく終わったものも入れる。
    /// 自動並べ替えがオンで移動を飛ばしたデスクトップ移動だけの行は、何もしていないので入れない。
    let placed: [LayoutRow]
    let skipped: [SkippedRow]
    let failed: [FailedRow]
    /// 自動並べ替えがオンでデスクトップ移動を飛ばした。
    let skippedDesktopMoves: Bool

    /// HUD の文言（§2.5）。
    var summary: String {
        var seen = Set<UUID>()
        let rowCount = (placed + skipped.map(\.row) + failed.map(\.row)).filter { seen.insert($0.id).inserted }.count
        guard rowCount > 0 else { return "\(set.name): 配置する行がありません" }

        let count = placed.count == rowCount ? "\(rowCount) 件を配置" : "\(rowCount) 件中 \(placed.count) 件を配置"
        var parts = ["\(set.name): \(count)"]
        // 理由は行の順に並べる。1 行は skipped か failed のどちらか一方にしか入らない。
        for row in set.rows {
            if let failure = failed.first(where: { $0.row.id == row.id }) {
                parts.append(Self.message(for: failure.error, appName: row.appName))
            } else if let skip = skipped.first(where: { $0.row.id == row.id }) {
                parts.append(Self.message(for: skip.reason, appName: row.appName))
            }
        }
        if skippedDesktopMoves {
            parts.append("自動並べ替えがオンなのでデスクトップ移動を飛ばしました")
        }
        return parts.joined(separator: " ・ ")
    }

    private static func message(for reason: SkipReason, appName: String) -> String {
        switch reason {
        case .appNotRunning: "\(appName) は起動していません"
        case .noMatchingWindow: "\(appName) に合う窓がありません"
        case .fullScreen: "\(appName) はフルスクリーンです"
        }
    }

    private static func message(for error: any Error, appName: String) -> String {
        switch error as? SpaceMoveError {
        case .shortcutDisabled(let desktop)?: "デスクトップ \(desktop) へ切り替えるショートカットがオフです"
        case .modifiersHeld?: "修飾キーが押されたままだったので \(appName) を移動できませんでした"
        case .windowNotOnScreen?: "\(appName) を前面に出せませんでした"
        case .noGrabPoint?: "\(appName) のタイトルバーを掴めませんでした"
        case .interrupted?: "マウスが動いたので \(appName) の移動を中止しました"
        case .spaceDidNotChange(let desktop)?: "デスクトップ \(desktop) へ切り替わりませんでした"
        case .windowLeftBehind?: "\(appName) が付いてきませんでした"
        case .eventPostFailed?, .frameUnreadable?, nil: "\(appName) の配置に失敗しました"
        }
    }
}

/// レイアウトセットを行の順に適用する（設計書 §2.4）。
///
/// 実行中だけ「tatami が信じている現在のデスクトップ番号」を持ち、activate などで自分以外の切替が起きたら
/// 分からなくなったものとして nil に戻す。すでに目的のデスクトップにある窓を掴んで無駄に待つのを避けるため。
@MainActor
final class LayoutSetRunner {
    /// 窓が見えるのを待つ間の問い合わせ間隔。
    private static let pollInterval: Duration = .milliseconds(20)

    private(set) var isRunning = false

    private let enumerator: any WindowEnumerating
    private let windowService: any WindowService
    private let placer: WindowPlacer
    private let spaceMover: any SpaceMoving
    private let dockPreferences: any DockPreferencesReading
    private let permission: any PermissionChecking
    private let onScreenTimeout: Duration
    private let settleInterval: Duration
    private let onStarted: @MainActor (LayoutSet) -> Void
    private let onFinished: @MainActor (LayoutRunResult) -> Void

    /// - Parameters:
    ///   - onScreenTimeout: raise 後に窓が見えるまで待つ上限。
    ///   - settleInterval: 窓が見えてから切替の通知を数える前に待つ時間。activate が起こした切替の通知は遅れて届くことがある。
    init(
        enumerator: any WindowEnumerating, windowService: any WindowService, placer: WindowPlacer,
        spaceMover: any SpaceMoving, dockPreferences: any DockPreferencesReading,
        permission: any PermissionChecking,
        onScreenTimeout: Duration = .seconds(1),
        settleInterval: Duration = .milliseconds(300),
        onStarted: @escaping @MainActor (LayoutSet) -> Void,
        onFinished: @escaping @MainActor (LayoutRunResult) -> Void
    ) {
        self.enumerator = enumerator
        self.windowService = windowService
        self.placer = placer
        self.spaceMover = spaceMover
        self.dockPreferences = dockPreferences
        self.permission = permission
        self.onScreenTimeout = onScreenTimeout
        self.settleInterval = settleInterval
        self.onStarted = onStarted
        self.onFinished = onFinished
    }

    /// 実行中・権限なしなら何もせず false。権限なしのときは requestAccess を呼ぶ。
    @discardableResult
    func apply(_ set: LayoutSet) async -> Bool {
        guard !isRunning else { return false }
        guard permission.isTrusted else {
            permission.requestAccess()
            return false
        }
        isRunning = true
        defer { isRunning = false }
        onStarted(set)

        let skipMoves = dockPreferences.rearrangesSpacesAutomatically
        var currentDesktop: Int?
        var unreachable: Set<Int> = []
        // この実行で switchTo が切替を確かめた番号。
        var confirmedDesktops: Set<Int> = []
        var lastDesktopWindow: WindowHandle?
        var firstPlacedWindow: WindowHandle?

        // nil（起動していない）は入れず、[]（窓がない）はそのまま入れる。
        var windowsByBundle: [String: [WindowInfo]] = [:]
        for id in Set(set.rows.map(\.bundleIdentifier)) {
            if let windows = enumerator.windows(ofBundleIdentifier: id) {
                windowsByBundle[id] = windows
            }
        }
        let plan = LayoutSetPlanner.plan(set, windowsByBundle: windowsByBundle)

        var placed: [LayoutRow] = []
        var failed: [FailedRow] = []

        for step in plan.steps {
            let row = step.row
            let window = step.window.handle
            // 行につき最初の 1 つだけ記録する。
            var rowError: (any Error)?
            func record(_ error: any Error) {
                if rowError == nil { rowError = error }
            }

            do {
                if step.window.isMinimized {
                    try windowService.unminimize(window)
                }
                if let desktop = row.desktop, !skipMoves {
                    try await bring(
                        window, to: desktop, currentDesktop: &currentDesktop, unreachable: &unreachable,
                        confirmedDesktops: &confirmedDesktops, lastDesktopWindow: &lastDesktopWindow
                    )
                } else {
                    // 隠されたアプリの窓は raise しても見えないので先に unhide する（activate する行は activate が行う）。
                    try windowService.unhide(window)
                    try windowService.raise(window)
                }
            } catch {
                record(error)
            }

            // 移動に失敗しても配置は行う（少なくとも並ぶことを優先する）。
            if let action = row.action {
                do {
                    try placer.place(window, action: action)
                    placed.append(row)
                    if firstPlacedWindow == nil { firstPlacedWindow = window }
                } catch {
                    record(error)
                }
            } else if row.desktop != nil, !skipMoves, rowError == nil {
                // デスクトップ移動だけの行は、誤りなく運べたら成功として数える。
                placed.append(row)
            }
            if let rowError {
                failed.append(FailedRow(row: row, error: rowError))
            }
        }

        // キーボードフォーカスを見えている窓へ移す。raise だけでは元のアプリにフォーカスが残る。
        if let focus = lastDesktopWindow ?? firstPlacedWindow {
            try? windowService.activate(focus)
        }

        let movedAnyDesktop = plan.steps.contains { $0.row.desktop != nil }
        onFinished(LayoutRunResult(
            set: set, placed: placed, skipped: plan.skipped, failed: failed,
            skippedDesktopMoves: skipMoves && movedAnyDesktop
        ))
        return true
    }

    /// 窓をデスクトップ desktop へ連れていく（設計書 §2.4 手順 5）。失敗は投げる。
    private func bring(
        _ window: WindowHandle, to desktop: Int, currentDesktop: inout Int?, unreachable: inout Set<Int>,
        confirmedDesktops: inout Set<Int>, lastDesktopWindow: inout WindowHandle?
    ) async throws {
        // この実行で切り替わらなかった番号へは、掴んで待つことを繰り返さない。
        if unreachable.contains(desktop) {
            throw SpaceMoveError.spaceDidNotChange(desktop: desktop)
        }
        if currentDesktop != desktop {
            // false は「すでにそこ」か「存在しない」で区別できないので、仮にそこにいるとみなす。
            if try await spaceMover.switchTo(desktop: desktop) {
                confirmedDesktops.insert(desktop)
            }
            currentDesktop = desktop
        }

        let before = spaceMover.spaceChangeCount
        try windowService.activate(window)
        try windowService.raise(window)
        lastDesktopWindow = window

        guard await waitUntilOnScreen(window) else {
            throw SpaceMoveError.windowNotOnScreen
        }
        if settleInterval > .zero {
            try? await Task.sleep(for: settleInterval)
        }
        // activate が別デスクトップへの切替を起こしたら、いまの番号は分からない。
        if spaceMover.spaceChangeCount > before {
            currentDesktop = nil
        }
        guard currentDesktop != desktop else { return }   // 窓はもう目的のデスクトップにある

        do {
            try await spaceMover.move(window, toDesktop: desktop)
            currentDesktop = desktop
        } catch SpaceMoveError.spaceDidNotChange(let number) where confirmedDesktops.contains(number) {
            // この実行で切り替われた番号なのに切り替わらなかったのは、遅れた（または重複した）通知で
            // 「activate で切り替わった」と誤って判断し、すでにそこにいたため。窓は目的のデスクトップにある。
            currentDesktop = number
        } catch SpaceMoveError.spaceDidNotChange(let number) {
            unreachable.insert(number)
            throw SpaceMoveError.spaceDidNotChange(desktop: number)
        }
    }

    /// 窓がいまのデスクトップに見えるまで、onScreenTimeout を上限に待つ。
    private func waitUntilOnScreen(_ window: WindowHandle) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + onScreenTimeout
        while !enumerator.isOnScreen(window) {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: Self.pollInterval)
        }
        return true
    }
}
