import CoreGraphics

/// 1 枚のディスプレイの領域。NS 座標（左下原点）。
struct ScreenRegion: Equatable, Sendable {
    /// ディスプレイ全体。
    let frame: CGRect
    /// メニューバーと Dock を除いた領域。
    let visibleFrame: CGRect
}

/// ウィンドウがどの画面にあるかを決める純粋関数。
enum ScreenLocator {
    /// ウィンドウの中心点を含む最初の画面を返す。含む画面がなければ nil。
    static func region(containing windowFrame: CGRect, in screens: [ScreenRegion]) -> ScreenRegion? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.first { $0.frame.contains(center) }
    }
}
