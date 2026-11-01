import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct LayoutCaptureTests {
    let enumerator = FakeWindowEnumerator()
    let screens = FakeScreenProvider.single   // visible NS (0,45,1920,1010) → AX (0,25,1920,1010)

    /// pid は窓ごとに変えて handle を区別する（同じ pid だと AXUIElementCreateApplication が CFEqual で等しくなる）。
    static func window(_ bundle: String, _ app: String, _ title: String, pid: pid_t, frameAX: CGRect) -> WindowInfo {
        WindowInfo(handle: WindowHandle(element: AXUIElementCreateApplication(pid)), pid: pid,
                   bundleIdentifier: bundle, appName: app, title: title, frameAX: frameAX, isMinimized: false, isFullScreen: false)
    }

    @Test func 窓ごとに区画へ丸めた行ができる() {
        enumerator.onScreen = [
            Self.window("wez", "WezTerm", "host: herdr", pid: 1, frameAX: CGRect(x: 0, y: 25, width: 1280, height: 1010)),
            Self.window("chrome", "Google Chrome", "GitHub", pid: 2, frameAX: CGRect(x: 1280, y: 25, width: 640, height: 1010)),
            Self.window("finder", "Finder", "Desktop", pid: 3, frameAX: CGRect(x: 300, y: 300, width: 700, height: 500)),
        ]
        let rows = LayoutCapture(enumerator: enumerator, screens: screens).capture(desktop: 2)
        #expect(rows.map(\.bundleIdentifier) == ["wez", "chrome", "finder"])
        #expect(rows.map(\.appName) == ["WezTerm", "Google Chrome", "Finder"])
        #expect(rows.map(\.action) == [.leftTwoThirds, .rightThird, nil])
        #expect(rows.map(\.desktop) == [2, 2, 2])
        #expect(rows.map(\.titleFilter) == ["", "", ""])
    }

    /// タイトルはタブで変わるので、同じアプリが 2 枚あっても絞り込みは入れない（行の順で当てる）。
    @Test func 同じアプリが2枚あっても絞り込みは空のまま() {
        enumerator.onScreen = [
            Self.window("wez", "WezTerm", "host: herdr", pid: 1, frameAX: CGRect(x: 0, y: 25, width: 960, height: 1010)),
            Self.window("wez", "WezTerm", "host: tatami", pid: 4, frameAX: CGRect(x: 960, y: 25, width: 960, height: 1010)),
            Self.window("chrome", "Google Chrome", "GitHub", pid: 2, frameAX: CGRect(x: 0, y: 25, width: 1920, height: 1010)),
        ]
        let rows = LayoutCapture(enumerator: enumerator, screens: screens).capture(desktop: nil)
        #expect(rows.map(\.titleFilter) == ["", "", ""])
        #expect(rows.map(\.action) == [.leftHalf, .rightHalf, .maximize])
        #expect(rows.map(\.desktop) == [nil, nil, nil])
    }
}
