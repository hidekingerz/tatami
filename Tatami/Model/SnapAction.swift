import Foundation

/// ウィンドウを配置する区画。
enum SnapAction: CaseIterable, Sendable {
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
}
