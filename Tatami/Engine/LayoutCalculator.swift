import CoreGraphics

/// 区画の目標枠を計算する純粋関数。入出力とも NS 座標（左下原点）。
///
/// 分割の端数は右端・上端の区画に寄せ、区画同士に隙間と重なりを作らない。
enum LayoutCalculator {
    static func frame(for action: SnapAction, in visible: CGRect) -> CGRect {
        let halfWidth = (visible.width / 2).rounded(.down)
        let halfHeight = (visible.height / 2).rounded(.down)
        let thirdWidth = (visible.width / 3).rounded(.down)

        switch action {
        case .maximize:
            return visible

        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY,
                          width: visible.width - halfWidth, height: visible.height)

        // NS 座標は下が原点なので、下半分が minY から始まり、上半分に端数を寄せる。
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY + halfHeight,
                          width: visible.width, height: visible.height - halfHeight)

        case .leftThird:
            return CGRect(x: visible.minX, y: visible.minY, width: thirdWidth, height: visible.height)
        case .centerThird:
            return CGRect(x: visible.minX + thirdWidth, y: visible.minY, width: thirdWidth, height: visible.height)
        case .rightThird:
            return CGRect(x: visible.minX + thirdWidth * 2, y: visible.minY,
                          width: visible.width - thirdWidth * 2, height: visible.height)

        case .leftTwoThirds:
            return CGRect(x: visible.minX, y: visible.minY, width: thirdWidth * 2, height: visible.height)
        case .rightTwoThirds:
            return CGRect(x: visible.minX + thirdWidth, y: visible.minY,
                          width: visible.width - thirdWidth, height: visible.height)
        }
    }
}
