import CoreGraphics

/// AX 座標（左上原点）と NS 座標（左下原点）を相互変換する純粋関数。
///
/// どちらの座標系もプライマリ画面（`NSScreen.screens[0]`）を基準にする。
/// y 軸だけが反転するので、`y' = primaryHeight - (y + height)` を両方向に適用する。
enum CoordinateConverter {
    /// AX 座標 → NS 座標。
    static func toScreen(_ axFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipY(axFrame, primaryHeight: primaryHeight)
    }

    /// NS 座標 → AX 座標。
    static func toAccessibility(_ screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipY(screenFrame, primaryHeight: primaryHeight)
    }

    private static func flipY(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryHeight - (frame.minY + frame.height),
            width: frame.width,
            height: frame.height
        )
    }
}
