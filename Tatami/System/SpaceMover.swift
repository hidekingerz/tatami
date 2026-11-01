import AppKit
import ApplicationServices

/// 窓のデスクトップ移動で起こりうる失敗。
enum SpaceMoveError: Error, Equatable, Sendable {
    /// Mission Control の「デスクトップ N へ切り替え」がオフ。
    case shortcutDisabled(desktop: Int)
    /// 修飾キーが離されないまま上限を過ぎた。
    case modifiersHeld
    /// 上限までに窓がいまのデスクトップに現れない。
    case windowNotOnScreen
    /// タイトルバーに部品でない点が見つからない。
    case noGrabPoint
    /// 利用者がマウスボタンを押している、または掴んでいる間にマウスを動かした。
    case interrupted
    /// キーを送ってもデスクトップが切り替わらない（存在しない番号、またはすでにそこ）。
    case spaceDidNotChange(desktop: Int)
    /// 切り替わったが窓が付いてこなかった。
    case windowLeftBehind
    /// CGEvent を作れなかった。
    case eventPostFailed
    /// 窓の枠を読めなかった（WindowService の失敗）。
    case frameUnreadable
}

/// SpaceMover の待ち時間。既定値はスパイクで決める。
struct SpaceMoverTiming: Sendable {
    var modifierReleaseTimeout: Duration = .seconds(1)
    var onScreenTimeout: Duration = .seconds(1)
    /// 0 なら leftMouseDragged を送らない。
    var dragOffset: CGFloat = 0
    var afterMouseDown: Duration = .milliseconds(80)
    var spaceChangeTimeout: Duration = .seconds(1)
    var afterSpaceChange: Duration = .milliseconds(150)
    var leftBehindTimeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(20)
    /// キー送信前に spaceChangeCount がこの間変わらなければ「落ち着いた」とみなす。
    var settleInterval: Duration = .milliseconds(300)
    /// 落ち着くのを待つ上限。超えたらそのまま進む。
    var settleTimeout: Duration = .seconds(1)
}

/// デスクトップの切替と、窓を掴んだままの切替による移動。
@MainActor
/// 投げるのは SpaceMoveError か、キャンセル時の CancellationError のみ。
protocol SpaceMoving {
    /// activeSpaceDidChangeNotification が来るたびに増える。Runner は raise の前後で比べて、自分以外の切替を検知する。
    var spaceChangeCount: Int { get }
    /// 何も掴まずにキーだけ送り、切替の通知が来れば true。来なければ false（例外にしない）。
    func switchTo(desktop: Int) async throws -> Bool
    /// 呼び出し側は activate + raise 済み。move 自身が「見えている」「掴む点の直下がこの窓」を確かめてから掴む。
    func move(_ window: WindowHandle, toDesktop desktop: Int) async throws
}

/// 「タイトルバーを掴む → Mission Control の『デスクトップ N へ切り替え』キー → 離す」で窓を運ぶ実装。
/// 掴んだ点に別の窓があると無関係な窓を運んでしまうため、掴む前に目的の窓がそこにあることを必ず確かめる。
@MainActor
final class CGEventSpaceMover: SpaceMoving {
    /// 掴んでよい AX ロール（許可リスト）。ロールが読めない要素も許可する。
    /// 拒否リストにしないのは、距離 0 の down/up が本物のクリックになる経路があり、漏れがそのまま事故になるため。
    static let allowedRoles: Set<String> = [
        "AXWindow", "AXGroup", "AXToolbar", "AXStaticText", "AXTabGroup", "AXWebArea", "AXUnknown",
    ]

    /// AX 呼び出し 1 回あたりの待ち時間の上限（秒）。
    private static let messagingTimeout: Float = 1
    /// 掴んでいる間にマウスがこれ以上動いたら利用者の操作とみなす。
    private static let interruptDistance: CGFloat = 10
    private static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    private(set) var spaceChangeCount = 0
    /// 直近の move で採った掴む点の候補番号（0 始まり）。デバッグ表示用。
    private(set) var lastGrabCandidateIndex: Int?

    private let shortcuts: any MissionControlShortcutReading
    private let enumerator: any WindowEnumerating
    private let windowService: any WindowService
    private let timing: SpaceMoverTiming
    private var observer: (any NSObjectProtocol)?

    init(
        shortcuts: any MissionControlShortcutReading, enumerator: any WindowEnumerating,
        windowService: any WindowService, timing: SpaceMoverTiming = SpaceMoverTiming()
    ) {
        self.shortcuts = shortcuts
        self.enumerator = enumerator
        self.windowService = windowService
        self.timing = timing
        // 生成時から購読し、切替のたびにカウンタを増やす。キュー .main なのでメインアクター上で呼ばれる。
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spaceChangeCount += 1
            }
        }
    }

    isolated deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// 掴む点の候補（順に試す）。(a) minX+80,minY+10 (b) midX,minY+10 (c) maxX-40,minY+10 (d) midX,minY+6。
    /// 幅 200 未満なら (a)(c) を外す。
    static func grabCandidates(for frameAX: CGRect) -> [CGPoint] {
        let a = CGPoint(x: frameAX.minX + 80, y: frameAX.minY + 10)
        let b = CGPoint(x: frameAX.midX, y: frameAX.minY + 10)
        let c = CGPoint(x: frameAX.maxX - 40, y: frameAX.minY + 10)
        let d = CGPoint(x: frameAX.midX, y: frameAX.minY + 6)
        return frameAX.width < 200 ? [b, d] : [a, b, c, d]
    }

    func switchTo(desktop: Int) async throws -> Bool {
        guard let combo = shortcuts.switchToDesktopShortcut(desktop) else {
            throw SpaceMoveError.shortcutDisabled(desktop: desktop)
        }
        try await waitForModifierRelease()
        try await waitForSpaceCountToSettle()
        let before = spaceChangeCount
        try postKey(combo)
        guard await waitForSpaceChange(since: before, timeout: timing.spaceChangeTimeout) else {
            return false
        }
        try await Task.sleep(for: timing.afterSpaceChange)
        return true
    }

    func move(_ window: WindowHandle, toDesktop desktop: Int) async throws {
        lastGrabCandidateIndex = nil
        // 1. キーを読む。
        guard let combo = shortcuts.switchToDesktopShortcut(desktop) else {
            throw SpaceMoveError.shortcutDisabled(desktop: desktop)
        }
        // 2. 修飾キーとマウスボタンが離されるまで待つ。
        try await waitForModifierRelease()
        // 遅れて届く activate 由来の通知を自分の切替と取り違えないよう、カウンタが落ち着くまで待つ。
        // 窓は通知より先に見えるようになるため、落ち着く前に控えた before では 9 の待ちが即座に真になり、
        // 運べていないのに成功と報告してしまう。マウスボタンを押す前に待つ（押したまま待たない）。
        // 落ち着く間に切替が起きると窓の位置関係が変わりうるので、3・4 の確認はこのあとで行う。
        try await waitForSpaceCountToSettle()
        // 3. 窓がいまのデスクトップに見えるまで待つ（raise による切替や最小化復帰のアニメーション待ち）。
        guard try await poll(timeout: timing.onScreenTimeout, until: { self.enumerator.isOnScreen(window) }) else {
            throw SpaceMoveError.windowNotOnScreen
        }
        // 4. 掴む点の直下がこの窓で、部品でないことを確かめる。
        let frame: CGRect
        do {
            frame = try windowService.frame(of: window)
        } catch {
            throw SpaceMoveError.frameUnreadable
        }
        guard let (index, grabPoint) = findGrabPoint(on: window, frame: frame) else {
            throw SpaceMoveError.noGrabPoint
        }
        lastGrabCandidateIndex = index

        // 5. マウス位置を控える。ここから先はどの経路でも必ず離して戻す。
        guard let savedLocation = CGEvent(source: nil)?.location else {
            throw SpaceMoveError.eventPostFailed
        }
        var releasePoint = grabPoint
        var released = false
        defer {
            if !released {
                _ = postMouse(.leftMouseUp, at: releasePoint)
                CGWarpMouseCursorPosition(savedLocation)
            }
        }

        // 6. 掴む。
        guard postMouse(.mouseMoved, at: grabPoint), postMouse(.leftMouseDown, at: grabPoint) else {
            throw SpaceMoveError.eventPostFailed
        }
        if timing.dragOffset != 0 {
            let dragPoint = CGPoint(x: grabPoint.x + timing.dragOffset, y: grabPoint.y)
            guard postMouse(.leftMouseDragged, at: dragPoint) else {
                throw SpaceMoveError.eventPostFailed
            }
            releasePoint = dragPoint
        }

        // 7. 待つ間に利用者がマウスを動かしていたら中断する。
        try await Task.sleep(for: timing.afterMouseDown)
        if let location = CGEvent(source: nil)?.location,
           hypot(location.x - grabPoint.x, location.y - grabPoint.y) >= Self.interruptDistance {
            throw SpaceMoveError.interrupted
        }

        // 8〜9. キーを送り、切替を待つ。
        let before = spaceChangeCount
        try postKey(combo)
        guard await waitForSpaceChange(since: before, timeout: timing.spaceChangeTimeout) else {
            throw SpaceMoveError.spaceDidNotChange(desktop: desktop)
        }
        try await Task.sleep(for: timing.afterSpaceChange)

        // 10〜11. 離してマウスを戻す（正常経路。defer で二重に送らない）。
        _ = postMouse(.leftMouseUp, at: releasePoint)
        CGWarpMouseCursorPosition(savedLocation)
        released = true

        // 12. 窓が付いてきたか確かめる。
        guard try await poll(timeout: timing.leftBehindTimeout, until: { self.enumerator.isOnScreen(window) }) else {
            throw SpaceMoveError.windowLeftBehind
        }
    }

    // MARK: - 待ち

    /// spaceChangeCount が settleInterval のあいだ変わらなくなるまで pollInterval ずつ待つ。
    /// settleTimeout を超えても変わり続けるなら、そのまま進む。
    private func waitForSpaceCountToSettle() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timing.settleTimeout
        var lastCount = spaceChangeCount
        var stableSince = clock.now
        while clock.now - stableSince < timing.settleInterval, clock.now < deadline {
            try await Task.sleep(for: timing.pollInterval)
            if spaceChangeCount != lastCount {
                lastCount = spaceChangeCount
                stableSince = clock.now
            }
        }
    }

    /// 修飾キーとマウス左ボタンが離されるまで待つ。上限を超えたら、修飾キーなら modifiersHeld、ボタンなら interrupted。
    private func waitForModifierRelease() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timing.modifierReleaseTimeout
        while true {
            let modifiersDown = !CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMask).isEmpty
            let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if !modifiersDown && !buttonDown { return }
            if clock.now >= deadline {
                throw modifiersDown ? SpaceMoveError.modifiersHeld : SpaceMoveError.interrupted
            }
            try await Task.sleep(for: timing.pollInterval)
        }
    }

    /// condition が true になるまで pollInterval ずつ待つ。timeout までにならなければ false。
    private func poll(timeout: Duration, until condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline { return false }
            try await Task.sleep(for: timing.pollInterval)
        }
        return true
    }

    /// spaceChangeCount が count より増えるのを timeout まで待つ。
    /// 「カウンタの監視」と「タイムアウト」を競走させ、先に終わった方の結果を返す。
    private func waitForSpaceChange(since count: Int, timeout: Duration) async -> Bool {
        await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await self.pollSpaceChange(since: count)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return false
            }
            // 先に終わった方を採り、残りは取り消す（取り消されたタスクの CancellationError は捨てる）。
            let result = (try? await group.next()) ?? false
            group.cancelAll()
            return result
        }
    }

    /// spaceChangeCount が count を超えるまで pollInterval ずつ待つ。取り消されれば CancellationError。
    private func pollSpaceChange(since count: Int) async throws -> Bool {
        while spaceChangeCount <= count {
            try await Task.sleep(for: timing.pollInterval)
        }
        return true
    }

    // MARK: - ヒットテスト

    /// 候補を順に試し、直下の要素がこの窓に属し、ロールが許可リストに入る（または読めない）最初の点を返す。
    private func findGrabPoint(on window: WindowHandle, frame: CGRect) -> (index: Int, point: CGPoint)? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        for (index, point) in Self.grabCandidates(for: frame).enumerated() {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
                  let hit
            else { continue }
            AXUIElementSetMessagingTimeout(hit, Self.messagingTimeout)
            let role = Self.copyAttribute(kAXRoleAttribute, of: hit) as? String
            if let role, !Self.allowedRoles.contains(role) { continue }
            let owner: CFTypeRef? = role == kAXWindowRole ? hit : Self.copyAttribute(kAXWindowAttribute, of: hit)
            guard let owner, CFGetTypeID(owner) == AXUIElementGetTypeID(), CFEqual(owner, window.element) else {
                continue
            }
            return (index, point)
        }
        return nil
    }

    private static func copyAttribute(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    // MARK: - イベント送信

    /// マウスイベントを作って送る。作れなければ false。
    private func postMouse(_ type: CGEventType, at point: CGPoint) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left
        ) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    /// keyDown → keyUp を修飾キー付きで送る。
    private func postKey(_ combo: KeyCombo) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: combo.keyCode, keyDown: false)
        else { throw SpaceMoveError.eventPostFailed }
        down.flags = combo.modifiers
        up.flags = combo.modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
