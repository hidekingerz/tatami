import CoreGraphics

/// いまのデスクトップで見えている窓を、区画に丸めて `LayoutRow` にする。
@MainActor
struct LayoutCapture {
    let enumerator: any WindowEnumerating
    let screens: any ScreenProviding

    init(enumerator: any WindowEnumerating, screens: any ScreenProviding) {
        self.enumerator = enumerator
        self.screens = screens
    }

    /// いまの配置を行にする。desktop は全行に同じ値。
    /// タイトルはタブなどで変わるので titleFilter は常に空（同じアプリの窓は行の順で当てる）。
    func capture(desktop: Int?) -> [LayoutRow] {
        enumerator.onScreenWindows().map { window in
            let frameNS = CoordinateConverter.toScreen(window.frameAX, primaryHeight: screens.primaryHeight)
            let region = ScreenLocator.region(containing: frameNS, in: screens.screens) ?? screens.mainScreen
            let action = region.flatMap { RegionMatcher.closestAction(to: frameNS, in: $0.visibleFrame) }
            return LayoutRow(
                bundleIdentifier: window.bundleIdentifier,
                appName: window.appName,
                titleFilter: "",
                action: action,
                desktop: desktop
            )
        }
    }
}
