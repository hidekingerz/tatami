import CoreGraphics
import Foundation

/// 列挙した窓 1 枚の情報。座標は AX 座標（左上原点）。
struct WindowInfo: Hashable, Sendable {
    let handle: WindowHandle
    let pid: pid_t
    let bundleIdentifier: String
    /// NSRunningApplication.localizedName。なければ bundleIdentifier。
    let appName: String
    /// kAXTitleAttribute。なければ ""。
    let title: String
    let frameAX: CGRect
    let isMinimized: Bool
    /// "AXFullScreen"。なければ false。
    let isFullScreen: Bool
}

/// 起動中アプリの窓の列挙。
@MainActor
protocol WindowEnumerating {
    /// 起動中の通常アプリ（activationPolicy == .regular）の窓。全デスクトップ、最小化・フルスクリーンを含む。
    /// 並びは「いまのデスクトップで見えている窓を CGWindowList の前面順に、そのあと残りを AX の順で」。
    /// アプリが起動していなければ nil、起動しているが窓がなければ []。
    func windows(ofBundleIdentifier id: String) -> [WindowInfo]?
    /// いまのデスクトップで画面に見えているレイヤー 0 の窓を前面から順に。tatami 自身と補助アプリは除く。
    func onScreenWindows() -> [WindowInfo]
    /// いまのデスクトップで window が見えているか。
    func isOnScreen(_ window: WindowHandle) -> Bool
}
