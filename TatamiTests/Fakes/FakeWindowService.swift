import ApplicationServices
import CoreGraphics
@testable import Tatami

/// テスト用の WindowService。枠はメモリ上に持ち、setFrame に制約を掛けられる。
@MainActor
final class FakeWindowService: WindowService {
    var window = WindowHandle(element: AXUIElementCreateApplication(1))
    var currentFrame = CGRect(x: 0, y: 0, width: 800, height: 600)

    /// focusedWindow() で投げるエラー。nil なら成功。
    var focusedWindowError: WindowServiceError?
    /// frame(of:) で投げるエラー。nil なら成功。
    var frameError: WindowServiceError?
    /// setFrame 直後の 1 回の frame(of:) だけで投げるエラー。読み直し失敗を再現する。
    var frameErrorAfterSet: WindowServiceError?
    /// setFrame で投げるエラー。
    var setFrameError: WindowServiceError?
    /// ウィンドウの最小幅。目標がこれより小さければこの幅に丸められる。
    var minimumWidth: CGFloat = 0

    private(set) var setFrameCalls: [CGRect] = []
    private var pendingReadError: WindowServiceError?

    func focusedWindow() throws -> WindowHandle {
        if let focusedWindowError { throw focusedWindowError }
        return window
    }

    func frame(of window: WindowHandle) throws -> CGRect {
        if let frameError { throw frameError }
        if let pendingReadError {
            self.pendingReadError = nil
            throw pendingReadError
        }
        return currentFrame
    }

    func setFrame(_ frame: CGRect, of window: WindowHandle) throws {
        if let setFrameError { throw setFrameError }
        setFrameCalls.append(frame)
        pendingReadError = frameErrorAfterSet
        var applied = frame
        if applied.width < minimumWidth {
            applied.size.width = minimumWidth
        }
        currentFrame = applied
    }
}
