import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct WindowPlacerTests {
    let windows = FakeWindowService()
    let screens = FakeScreenProvider.single
    let visibleAX = CGRect(x: 0, y: 25, width: 1920, height: 1010)

    @Test func 最大化はvisibleFrameをAX座標で適用する() throws {
        let placer = WindowPlacer(windowService: windows, screens: screens)
        let applied = try placer.place(windows.window, action: .maximize)
        #expect(windows.setFrameCalls == [visibleAX])
        #expect(applied == visibleAX)
    }

    @Test func 中央に配置は大きさを変えず中央へ() throws {
        windows.currentFrame = CGRect(x: 0, y: 25, width: 800, height: 600)
        let placer = WindowPlacer(windowService: windows, screens: screens)
        try placer.place(windows.window, action: .center)
        // NS: x = floor((1920-800)/2) = 560, y = floor(45 + (1010-600)/2) = 250 → AX y = 1080 - (250+600) = 230
        #expect(windows.setFrameCalls == [CGRect(x: 560, y: 230, width: 800, height: 600)])
    }

    @Test func 最小幅で右端からはみ出したら画面内へ戻す() throws {
        windows.minimumWidth = 800
        let placer = WindowPlacer(windowService: windows, screens: screens)
        let applied = try placer.place(windows.window, action: .rightThird)
        #expect(applied == CGRect(x: 1120, y: 25, width: 800, height: 1010))
        #expect(windows.setFrameCalls.count == 2)
    }

    @Test func 画面が見つからなければmainScreenにフォールバックする() throws {
        windows.currentFrame = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        try WindowPlacer(windowService: windows, screens: screens).place(windows.window, action: .maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 画面もmainScreenもなければnoScreen() {
        let empty = FakeScreenProvider(primaryHeight: 1080, screens: [], mainScreen: nil)
        let placer = WindowPlacer(windowService: windows, screens: empty)
        #expect(throws: PlacementError.noScreen) {
            try placer.place(windows.window, action: .maximize)
        }
        #expect(windows.setFrameCalls.isEmpty)
    }
}
