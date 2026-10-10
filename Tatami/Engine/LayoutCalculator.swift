import CoreGraphics

/// 区画の目標枠を計算する純粋関数。入出力とも NS 座標（左下原点）。
///
/// 分割の端数は右端・上端の区画に寄せ、区画同士に隙間と重なりを作らない。
/// `current` はウィンドウの現在枠で、サイズ系の区画だけが使う。
enum LayoutCalculator {
    static func frame(for action: SnapAction, in visible: CGRect, current: CGRect) -> CGRect {
        switch action {
        case .maximize:
            return visible

        case .leftHalf: return cell(column: 0, of: 2, row: 0, of: 1, in: visible)
        case .rightHalf: return cell(column: 1, of: 2, row: 0, of: 1, in: visible)
        // NS 座標は下が原点なので、行 0 が下半分。
        case .bottomHalf: return cell(column: 0, of: 1, row: 0, of: 2, in: visible)
        case .topHalf: return cell(column: 0, of: 1, row: 1, of: 2, in: visible)

        case .leftThird: return cell(column: 0, of: 3, row: 0, of: 1, in: visible)
        case .centerThird: return cell(column: 1, of: 3, row: 0, of: 1, in: visible)
        case .rightThird: return cell(column: 2, of: 3, row: 0, of: 1, in: visible)
        case .leftTwoThirds:
            let third = column(0, of: 3, in: visible)
            return CGRect(x: visible.minX, y: visible.minY, width: third.width * 2, height: visible.height)
        case .rightTwoThirds:
            let third = column(0, of: 3, in: visible)
            return CGRect(x: visible.minX + third.width, y: visible.minY,
                          width: visible.width - third.width, height: visible.height)

        case .firstFourth: return cell(column: 0, of: 4, row: 0, of: 1, in: visible)
        case .secondFourth: return cell(column: 1, of: 4, row: 0, of: 1, in: visible)
        case .thirdFourth: return cell(column: 2, of: 4, row: 0, of: 1, in: visible)
        case .lastFourth: return cell(column: 3, of: 4, row: 0, of: 1, in: visible)

        case .topLeftQuarter: return cell(column: 0, of: 2, row: 1, of: 2, in: visible)
        case .topRightQuarter: return cell(column: 1, of: 2, row: 1, of: 2, in: visible)
        case .bottomLeftQuarter: return cell(column: 0, of: 2, row: 0, of: 2, in: visible)
        case .bottomRightQuarter: return cell(column: 1, of: 2, row: 0, of: 2, in: visible)

        case .topLeftSixth: return cell(column: 0, of: 3, row: 1, of: 2, in: visible)
        case .topCenterSixth: return cell(column: 1, of: 3, row: 1, of: 2, in: visible)
        case .topRightSixth: return cell(column: 2, of: 3, row: 1, of: 2, in: visible)
        case .bottomLeftSixth: return cell(column: 0, of: 3, row: 0, of: 2, in: visible)
        case .bottomCenterSixth: return cell(column: 1, of: 3, row: 0, of: 2, in: visible)
        case .bottomRightSixth: return cell(column: 2, of: 3, row: 0, of: 2, in: visible)
        }
    }

    /// visible を columns 列 × rows 行に等分したときのセル。
    private static func cell(column c: Int, of columns: Int, row r: Int, of rows: Int, in visible: CGRect) -> CGRect {
        let x = column(c, of: columns, in: visible)
        let y = row(r, of: rows, in: visible)
        return CGRect(x: x.x, y: y.y, width: x.width, height: y.height)
    }

    /// visible を count 列に等分したときの index 番目（左から 0 始まり）の x と幅。端数は最後の列に寄せる。
    private static func column(_ index: Int, of count: Int, in visible: CGRect) -> (x: CGFloat, width: CGFloat) {
        let base = (visible.width / CGFloat(count)).rounded(.down)
        let x = visible.minX + base * CGFloat(index)
        let width = index == count - 1 ? visible.maxX - x : base
        return (x, width)
    }

    /// visible を count 行に等分したときの index 番目（下から 0 始まり）の y と高さ。端数は最上段に寄せる。
    private static func row(_ index: Int, of count: Int, in visible: CGRect) -> (y: CGFloat, height: CGFloat) {
        let base = (visible.height / CGFloat(count)).rounded(.down)
        let y = visible.minY + base * CGFloat(index)
        let height = index == count - 1 ? visible.maxY - y : base
        return (y, height)
    }
}
