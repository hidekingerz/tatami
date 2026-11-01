@testable import Tatami

/// テスト用の SpaceMoving。呼び出しを記録し、切替の成否と移動の失敗を差し替えられる。
@MainActor
final class FakeSpaceMover: SpaceMoving {
    /// テストが直接増やして「activate で切り替わった」を再現する。FakeWindowService.onRaise から増やすとよい。
    var spaceChangeCount = 0
    private(set) var switchCalls: [Int] = []
    /// switchTo の戻り値。true なら spaceChangeCount も +1 する。
    var switchResult = true
    /// move の呼び出し。error を投げた呼び出しも記録する。
    private(set) var calls: [(window: WindowHandle, desktop: Int)] = []
    /// move で投げるエラー。nil なら成功。
    var error: SpaceMoveError?

    func switchTo(desktop: Int) async throws -> Bool {
        switchCalls.append(desktop)
        if switchResult {
            spaceChangeCount += 1
        }
        return switchResult
    }

    func move(_ window: WindowHandle, toDesktop desktop: Int) async throws {
        calls.append((window: window, desktop: desktop))
        if let error { throw error }
    }
}
