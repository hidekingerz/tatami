import Foundation

/// ショートカット 1 つに対応するコマンド。
/// ループ系は複数の区画を順に巡り、単発系は 1 つの区画に固定される。
///
/// rawValue は KeyboardShortcuts の名前と有効/無効の保存キーに使う。
/// 既存 8 コマンドの rawValue は MVP の `KeyboardShortcuts.Name` と同じ文字列にしてあり、
/// ユーザーが変更済みのキー割当を引き継ぐ。変更してはならない。
enum SnapCommand: String, CaseIterable, Sendable {
    // 半分
    case cycleLeft
    case cycleRight
    case topHalf
    case bottomHalf
    // 1/3
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    // 1/4
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    // 四隅
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // 1/6
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    // サイズ
    case maximize
    case maximizeHeight
    case maximizeWidth
    case center

    /// 設定画面のタブに対応する分類。allCases の順がタブの順。
    enum Category: CaseIterable, Sendable {
        case halves
        case thirds
        case fourths
        case quarters
        case sixths
        case size
    }

    /// このコマンドが巡る区画の系列。単発系は 1 要素。
    var sequence: [SnapAction] {
        switch self {
        case .cycleLeft: [.leftHalf, .leftThird, .leftTwoThirds]
        case .cycleRight: [.rightHalf, .rightThird, .rightTwoThirds]
        case .topHalf: [.topHalf]
        case .bottomHalf: [.bottomHalf]
        case .leftThird: [.leftThird]
        case .centerThird: [.centerThird]
        case .rightThird: [.rightThird]
        case .leftTwoThirds: [.leftTwoThirds]
        case .rightTwoThirds: [.rightTwoThirds]
        case .firstFourth: [.firstFourth]
        case .secondFourth: [.secondFourth]
        case .thirdFourth: [.thirdFourth]
        case .lastFourth: [.lastFourth]
        case .topLeftQuarter: [.topLeftQuarter]
        case .topRightQuarter: [.topRightQuarter]
        case .bottomLeftQuarter: [.bottomLeftQuarter]
        case .bottomRightQuarter: [.bottomRightQuarter]
        case .topLeftSixth: [.topLeftSixth]
        case .topCenterSixth: [.topCenterSixth]
        case .topRightSixth: [.topRightSixth]
        case .bottomLeftSixth: [.bottomLeftSixth]
        case .bottomCenterSixth: [.bottomCenterSixth]
        case .bottomRightSixth: [.bottomRightSixth]
        case .maximize: [.maximize]
        case .maximizeHeight: [.maximizeHeight]
        case .maximizeWidth: [.maximizeWidth]
        case .center: [.center]
        }
    }

    /// 押すたびに区画が切り替わるループ系か。
    var isCycle: Bool { sequence.count > 1 }

    var category: Category {
        switch self {
        case .cycleLeft, .cycleRight, .topHalf, .bottomHalf: .halves
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth: .fourths
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter: .quarters
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: .sixths
        case .maximize, .maximizeHeight, .maximizeWidth, .center: .size
        }
    }

    /// 設定画面に表示するラベル。
    var title: String {
        switch self {
        case .cycleLeft: "左半分 → 左 1/3 → 左 2/3"
        case .cycleRight: "右半分 → 右 1/3 → 右 2/3"
        case .topHalf: "上半分"
        case .bottomHalf: "下半分"
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
        case .maximize: "最大化"
        case .maximizeHeight: "高さを最大化"
        case .maximizeWidth: "幅を最大化"
        case .center: "中央に配置"
        }
    }

    /// 初回起動（設定なし）で有効か。MVP にあった 8 コマンドだけ true。
    var isEnabledByDefault: Bool {
        switch self {
        case .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .maximize, .leftThird, .centerThird, .rightThird:
            true
        default:
            false
        }
    }
}

extension SnapCommand.Category {
    /// タブに表示する名前。
    var title: String {
        switch self {
        case .halves: "半分"
        case .thirds: "1/3"
        case .fourths: "1/4"
        case .quarters: "四隅"
        case .sixths: "1/6"
        case .size: "サイズ"
        }
    }

    /// このカテゴリのコマンド。`SnapCommand.allCases` の順。
    var commands: [SnapCommand] {
        SnapCommand.allCases.filter { $0.category == self }
    }
}
