import ApplicationServices
import CoreGraphics

/// ウィンドウ操作で起こりうる失敗。
enum WindowServiceError: Error, Sendable, Equatable {
    /// 最前面アプリが取れない。
    case noFrontmostApplication
    /// 最前面アプリにフォーカスウィンドウがない（デスクトップなど）。
    case noFocusedWindow
    /// AX API がエラーを返した。
    case axError(AXError)
    /// AXValue の中身を取り出せなかった。
    case invalidValue
}

/// 最前面ウィンドウの取得と枠の読み書き。座標はすべて AX 座標（左上原点）。
@MainActor
protocol WindowService {
    /// 最前面アプリのフォーカスウィンドウ。
    func focusedWindow() throws -> WindowHandle
    /// 現在の枠。
    func frame(of window: WindowHandle) throws -> CGRect
    /// 枠を設定する。実装は size → position → size の順で適用する。
    func setFrame(_ frame: CGRect, of window: WindowHandle) throws
    /// 最小化を戻す（kAXMinimizedAttribute = false）。
    func unminimize(_ window: WindowHandle) throws
    /// アプリ内で前面に出す（kAXMainAttribute = true、kAXRaiseAction）。アプリはアクティブにしない。
    func raise(_ window: WindowHandle) throws
    /// その窓のアプリを unhide する（隠されたアプリの窓は raise しても見えないため）。アクティブにはしない。
    func unhide(_ window: WindowHandle) throws
    /// その窓のアプリを unhide してからアクティブにする。
    func activate(_ window: WindowHandle) throws
}
