import Foundation

/// ショートカット 1 つに対応するコマンド。
/// ループ系は複数の区画を順に巡り、単発系は 1 つの区画に固定される。
enum SnapCommand: CaseIterable, Sendable {
    case cycleLeft
    case cycleRight
    case topHalf
    case bottomHalf
    case maximize
    case centerThird

    /// このコマンドが巡る区画の系列。単発系は 1 要素。
    var sequence: [SnapAction] {
        switch self {
        case .cycleLeft: [.leftHalf, .leftThird, .leftTwoThirds]
        case .cycleRight: [.rightHalf, .rightThird, .rightTwoThirds]
        case .topHalf: [.topHalf]
        case .bottomHalf: [.bottomHalf]
        case .maximize: [.maximize]
        case .centerThird: [.centerThird]
        }
    }
}
