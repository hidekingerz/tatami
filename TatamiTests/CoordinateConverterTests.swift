import CoreGraphics
import Testing
@testable import Tatami

struct CoordinateConverterTests {
    /// プライマリ画面の高さ。
    let primaryHeight: CGFloat = 1080

    @Test func プライマリ画面の左上のウィンドウ() {
        // AX: 左上原点で (0, 0) は画面の左上。NS: 左下原点なので y = 1080 - 100 = 980。
        let ax = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: 0, y: 980, width: 200, height: 100))
    }

    @Test func プライマリ画面の左下のウィンドウ() {
        let ns = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ax = CoordinateConverter.toAccessibility(ns, primaryHeight: primaryHeight)
        #expect(ax == CGRect(x: 0, y: 980, width: 200, height: 100))
    }

    @Test func 右側のセカンダリ画面では_x_はそのまま() {
        let ax = CGRect(x: 1920 + 10, y: 50, width: 300, height: 200)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns.minX == 1930)
        #expect(ns == CGRect(x: 1930, y: 1080 - 250, width: 300, height: 200))
    }

    @Test func 左側のセカンダリ画面では_x_が負になる() {
        let ax = CGRect(x: -1440, y: 0, width: 100, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: -1440, y: 980, width: 100, height: 100))
    }

    @Test func プライマリより上にある画面では_AX_の_y_が負になる() {
        // プライマリの上に高さ 900 の画面がある。その画面の上端は AX では y = -900。
        let ax = CGRect(x: 0, y: -900, width: 100, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: 0, y: 1080 + 800, width: 100, height: 100))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 1, height: 1),
        CGRect(x: 123, y: 456, width: 789, height: 12),
        CGRect(x: -1440, y: -900, width: 640, height: 480),
        CGRect(x: 3000, y: 2000, width: 10, height: 10),
    ])
    func 往復変換は元に戻る(frame: CGRect) {
        let roundTrip = CoordinateConverter.toAccessibility(
            CoordinateConverter.toScreen(frame, primaryHeight: primaryHeight),
            primaryHeight: primaryHeight
        )
        #expect(roundTrip == frame)
    }
}
