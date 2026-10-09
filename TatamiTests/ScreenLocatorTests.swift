import CoreGraphics
import Testing
@testable import Tatami

struct ScreenLocatorTests {
    let primary = ScreenRegion(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 985)
    )
    let secondary = ScreenRegion(
        frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1415)
    )
    var screens: [ScreenRegion] { [primary, secondary] }

    @Test func 中心がプライマリにあればプライマリ() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == primary)
    }

    @Test func 中心がセカンダリにあればセカンダリ() {
        let window = CGRect(x: 2000, y: 100, width: 400, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == secondary)
    }

    @Test func 画面をまたぐウィンドウは中心のある側() {
        // x: 1700〜2300。中心は 2000 なのでセカンダリ。
        let window = CGRect(x: 1700, y: 100, width: 600, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == secondary)
    }

    @Test func 中心が境界線上なら配列で先に来る画面() {
        // 中心 x = 1920。プライマリの frame は maxX = 1920 を含まない（CGRect.contains は半開区間）。
        // セカンダリの minX = 1920 は含むので、決定的にセカンダリになる。
        let window = CGRect(x: 1720, y: 100, width: 400, height: 300)
        let region = ScreenLocator.region(containing: window, in: screens)
        #expect(region == secondary)
    }

    @Test func どの画面にも含まれなければnil() {
        let window = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        #expect(ScreenLocator.region(containing: window, in: screens) == nil)
    }

    @Test func 画面が空ならnil() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(ScreenLocator.region(containing: window, in: []) == nil)
    }
}
