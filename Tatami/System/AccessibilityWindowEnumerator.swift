import AppKit
import ApplicationServices

/// AX と CGWindowList を突き合わせる WindowEnumerating の実装。
struct AccessibilityWindowEnumerator: WindowEnumerating {
    /// AX 呼び出し 1 回あたりの待ち時間の上限（秒）。AccessibilityWindowService と同じ。
    private static let messagingTimeout: Float = 1
    /// AX の枠と CG の枠を同じ窓とみなす誤差（各辺）。
    private static let frameTolerance: CGFloat = 2

    /// CGWindowList の 1 項目（必要な分だけ）。
    private typealias OnScreenEntry = (pid: pid_t, bounds: CGRect)

    init() {}

    func windows(ofBundleIdentifier id: String) -> [WindowInfo]? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == id && $0.activationPolicy == .regular
        }
        guard !apps.isEmpty else { return nil }

        var axByPID: [pid_t: [WindowInfo]] = [:]
        for app in apps {
            axByPID[app.processIdentifier] = axWindows(of: app)
        }
        let pids = Set(axByPID.keys)
        let visibleEntries = onScreenList().filter { pids.contains($0.pid) }
        // 見えている窓を前面順に先頭へ。突き合わせで消費されなかったものを AX の順で後ろへ。
        var remaining = axByPID
        let visible = match(cg: visibleEntries, ax: &remaining)
        let rest = apps.flatMap { remaining[$0.processIdentifier] ?? [] }
        return visible + rest
    }

    func onScreenWindows() -> [WindowInfo] {
        let entries = onScreenList()
        var axByPID: [pid_t: [WindowInfo]] = [:]
        for entry in entries where axByPID[entry.pid] == nil {
            // pid ごとの AX 一覧は 1 回だけ読む。
            guard let app = NSRunningApplication(processIdentifier: entry.pid) else {
                axByPID[entry.pid] = []
                continue
            }
            axByPID[entry.pid] = axWindows(of: app)
        }
        return match(cg: entries, ax: &axByPID)
    }

    func isOnScreen(_ window: WindowHandle) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window.element, &pid) == .success,
              let frame = try? frameAX(of: window.element)
        else { return false }
        return onScreenList().contains { $0.pid == pid && Self.framesMatch($0.bounds, frame) }
    }

    // MARK: - AX

    /// そのアプリの kAXWindowsAttribute を AX の順に読む。枠が読めない要素は捨てる。
    private func axWindows(of app: NSRunningApplication) -> [WindowInfo] {
        let pid = app.processIdentifier
        let bundleIdentifier = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        // 応答しないアプリで全体が止まらないよう待ち時間を短く切る（子要素には引き継がれない）。
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }

        return elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            guard let frame = try? frameAX(of: element) else { return nil }
            return WindowInfo(
                handle: WindowHandle(element: element),
                pid: pid,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                title: Self.string(kAXTitleAttribute, of: element) ?? "",
                frameAX: frame,
                isMinimized: Self.bool(kAXMinimizedAttribute, of: element) ?? false,
                isFullScreen: Self.bool("AXFullScreen", of: element) ?? false
            )
        }
    }

    private func frameAX(of element: AXUIElement) throws -> CGRect {
        // 読み方は AccessibilityWindowService.frame(of:) と同じ。
        try AccessibilityWindowService().frame(of: WindowHandle(element: element))
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    // MARK: - CGWindowList

    /// いまのデスクトップで見えているレイヤー 0 の窓を前面順に。tatami 自身と通常アプリでない所有者は除く。
    private func onScreenList() -> [OnScreenEntry] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var regularByPID: [pid_t: Bool] = [:]
        var entries: [OnScreenEntry] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha > 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let isRegular = regularByPID[pid] ?? {
                let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
                regularByPID[pid] = regular
                return regular
            }()
            guard isRegular else { continue }
            entries.append((pid: pid, bounds: bounds))
        }
        return entries
    }

    // MARK: - 突き合わせ

    /// CG の各項目について、同じ pid の AX 一覧から枠が一致し未消費の要素を探す。
    /// 見つかれば ax から取り除いて（消費して）結果に加える。見つからない項目は捨てる。
    private func match(cg entries: [OnScreenEntry], ax: inout [pid_t: [WindowInfo]]) -> [WindowInfo] {
        var result: [WindowInfo] = []
        for entry in entries {
            guard var candidates = ax[entry.pid],
                  let index = candidates.firstIndex(where: { Self.framesMatch($0.frameAX, entry.bounds) })
            else { continue }
            result.append(candidates.remove(at: index))
            ax[entry.pid] = candidates
        }
        return result
    }

    private static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
            && abs(a.maxX - b.maxX) <= frameTolerance && abs(a.maxY - b.maxY) <= frameTolerance
    }
}
