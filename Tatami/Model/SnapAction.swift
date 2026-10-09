import Foundation

/// ウィンドウを配置する区画。
enum SnapAction: CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
}
