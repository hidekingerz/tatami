import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct SnapEngineTests {
    let windows = FakeWindowService()
    let permission = FakePermission()
    let screens = FakeScreenProvider.single

    /// visibleFrame (0, 45, 1920, 1010) の NS 座標を AX 座標にしたもの。
    /// AX の y = 1080 - (45 + 1010) = 25。
    let visibleAX = CGRect(x: 0, y: 25, width: 1920, height: 1010)

    func makeEngine(onFailure: @escaping @MainActor (SnapFailure) -> Void = { _ in }) -> SnapEngine {
        SnapEngine(windowService: windows, screens: screens, permission: permission, onFailure: onFailure)
    }

    @Test func 最大化はvisibleFrameをAX座標で適用する() {
        let engine = makeEngine()
        engine.perform(.maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 左半分はAX座標で左側の枠になる() {
        let engine = makeEngine()
        engine.perform(.cycleLeft)
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 25, width: 960, height: 1010)])
    }

    @Test func 上半分はAX座標でyが小さい側になる() {
        let engine = makeEngine()
        engine.perform(.topHalf)
        // NS: y = 45 + 505 = 550, height = 505 → AX: y = 1080 - (550 + 505) = 25
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 25, width: 1920, height: 505)])
    }

    @Test func 下半分はAX座標でyが大きい側になる() {
        let engine = makeEngine()
        engine.perform(.bottomHalf)
        // NS: y = 45, height = 505 → AX: y = 1080 - (45 + 505) = 530
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 530, width: 1920, height: 505)])
    }

    @Test func 同じキーを3回押すと半分_1_3_2_3と進む() {
        let engine = makeEngine()
        engine.perform(.cycleRight)
        engine.perform(.cycleRight)
        engine.perform(.cycleRight)
        let widths = windows.setFrameCalls.map(\.width)
        #expect(widths == [960, 640, 1280])
        #expect(engine.memory?.action == .rightTwoThirds)
    }

    @Test func 最小幅制約で1_3にならなくてもループは進む() {
        windows.minimumWidth = 800
        let engine = makeEngine()
        engine.perform(.cycleLeft)   // 半分 960
        engine.perform(.cycleLeft)   // 1/3 を要求するが 800 に丸められる
        #expect(windows.currentFrame.width == 800)
        engine.perform(.cycleLeft)   // 実枠 800 と記憶が一致するので 2/3 へ
        #expect(windows.setFrameCalls.last?.width == 1280)
    }

    @Test func 最小幅制約で右端からはみ出したら画面内へ戻す() {
        windows.minimumWidth = 800
        let engine = makeEngine()
        engine.perform(.cycleRight)   // 右半分 960
        engine.perform(.cycleRight)   // 右 1/3 (x = 1280, 幅 640) を要求するが幅 800 に丸められる
        #expect(windows.currentFrame.maxX == 1920)
        #expect(windows.setFrameCalls.last == CGRect(x: 1120, y: 25, width: 800, height: 1010))
        #expect(engine.memory?.action == .rightThird)
        #expect(engine.memory?.appliedFrame == windows.currentFrame)
    }

    @Test func setFrameが失敗したら失敗フックを呼び記憶を作らない() {
        windows.setFrameError = .axError(.failure)
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.maximize)
        #expect(captured.count == 1)
        if case .window(.axError(.failure)) = captured.first {} else {
            Issue.record("window(axError(failure)) ではなく \(String(describing: captured.first))")
        }
        #expect(engine.memory == nil)
    }

    @Test func 権限がなければsetFrameを呼ばず再要求する() {
        permission.isTrusted = false
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        #expect(permission.requestAccessCount == 1)
        #expect(captured.count == 1)
        if case .notTrusted = captured[0] {} else {
            Issue.record("notTrusted ではなく \(captured[0])")
        }
    }

    @Test func ウィンドウが取れなければ失敗フックを呼ぶ() {
        windows.focusedWindowError = .noFocusedWindow
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        #expect(captured.count == 1)
        if case .window(.noFocusedWindow) = captured[0] {} else {
            Issue.record("window(noFocusedWindow) ではなく \(captured[0])")
        }
    }

    @Test func 適用後の読み直しに失敗しても記憶を壊さない() {
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.cycleLeft)
        let before = engine.memory
        #expect(before?.action == .leftHalf)

        windows.frameErrorAfterSet = .axError(.failure)
        engine.perform(.cycleLeft)
        #expect(windows.setFrameCalls.count == 2)
        #expect(engine.memory == before)
        #expect(captured.count == 1)
    }

    @Test func 画面が見つからなければmainScreenにフォールバックする() {
        windows.currentFrame = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        let engine = makeEngine()
        engine.perform(.maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 画面もmainScreenもなければ失敗フックを呼ぶ() {
        var captured: [SnapFailure] = []
        let empty = FakeScreenProvider(primaryHeight: 1080, screens: [], mainScreen: nil)
        let engine = SnapEngine(windowService: windows, screens: empty, permission: permission,
                                onFailure: { captured.append($0) })
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        if case .noScreen = captured.first {} else {
            Issue.record("noScreen ではなく \(String(describing: captured.first))")
        }
    }
}
