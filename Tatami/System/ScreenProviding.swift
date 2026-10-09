import CoreGraphics

/// 接続中のディスプレイ情報。NS 座標（左下原点）。
@MainActor
protocol ScreenProviding {
    /// プライマリ画面（原点 (0,0) を持つ画面）の高さ。座標変換の基準。
    var primaryHeight: CGFloat { get }
    /// 接続中の全画面。
    var screens: [ScreenRegion] { get }
    /// フォールバックに使う画面。
    var mainScreen: ScreenRegion? { get }
}
