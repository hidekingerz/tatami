import Foundation

/// ウィンドウを配置する区画。
///
/// rawValue はケース名で、レイアウトセットの保存に使う。
/// 保存済みデータが読めなくなるので、ケース名を変更してはならない（`SnapCommand.rawValue` と同じ規則）。
enum SnapAction: String, CaseIterable, Codable, Sendable {
    // 半分と最大化
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    // 横 1/3 と 2/3
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    // 横 1/4
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    // 四隅（横半分 × 縦半分）
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // 1/6（横 1/3 × 縦半分）
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    // サイズ系（現在枠に依存する）
    case maximizeHeight
    case maximizeWidth
    case center
}

extension SnapAction {
    /// 設定画面とピッカーに出す区画名。単発コマンドの `SnapCommand.title` と同じ文字列。
    var title: String {
        switch self {
        case .leftHalf: "左半分"
        case .rightHalf: "右半分"
        case .topHalf: "上半分"
        case .bottomHalf: "下半分"
        case .maximize: "最大化"
        case .leftThird: "左 1/3"
        case .centerThird: "中央 1/3"
        case .rightThird: "右 1/3"
        case .leftTwoThirds: "左 2/3"
        case .rightTwoThirds: "右 2/3"
        case .firstFourth: "左 1/4"
        case .secondFourth: "左から 2 番目の 1/4"
        case .thirdFourth: "左から 3 番目の 1/4"
        case .lastFourth: "右 1/4"
        case .topLeftQuarter: "左上"
        case .topRightQuarter: "右上"
        case .bottomLeftQuarter: "左下"
        case .bottomRightQuarter: "右下"
        case .topLeftSixth: "左上 1/6"
        case .topCenterSixth: "中央上 1/6"
        case .topRightSixth: "右上 1/6"
        case .bottomLeftSixth: "左下 1/6"
        case .bottomCenterSixth: "中央下 1/6"
        case .bottomRightSixth: "右下 1/6"
        case .maximizeHeight: "高さを最大化"
        case .maximizeWidth: "幅を最大化"
        case .center: "中央に配置"
        }
    }
}
