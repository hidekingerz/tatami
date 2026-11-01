import CoreGraphics
@testable import Tatami

/// テスト用の WindowEnumerating。答えをそのまま返す。
@MainActor
final class FakeWindowEnumerator: WindowEnumerating {
    /// bundle id ごとの窓。キーがなければ「起動していない」。
    var windowsByBundle: [String: [WindowInfo]] = [:]
    var onScreen: [WindowInfo] = []
    /// isOnScreen の答え。
    var onScreenHandles: Set<WindowHandle> = []

    func windows(ofBundleIdentifier id: String) -> [WindowInfo]? {
        windowsByBundle[id]
    }

    func onScreenWindows() -> [WindowInfo] {
        onScreen
    }

    func isOnScreen(_ window: WindowHandle) -> Bool {
        onScreenHandles.contains(window)
    }
}
