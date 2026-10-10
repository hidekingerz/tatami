import CoreGraphics
@testable import Tatami

@MainActor
struct FakeScreenProvider: ScreenProviding {
    var primaryHeight: CGFloat
    var screens: [ScreenRegion]
    var mainScreen: ScreenRegion?

    /// 1920×1080 の単一画面。メニューバー 25pt、Dock 45pt を除いた visibleFrame。
    static let single = FakeScreenProvider(
        primaryHeight: 1080,
        screens: [ScreenRegion(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 45, width: 1920, height: 1010)
        )],
        mainScreen: ScreenRegion(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 45, width: 1920, height: 1010)
        )
    )
}
