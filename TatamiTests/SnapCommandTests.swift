import Testing
@testable import Tatami

struct SnapCommandTests {
    @Test func 区画は27種類ある() {
        #expect(SnapAction.allCases.count == 27)
    }

    @Test func コマンドは27種類ある() {
        #expect(SnapCommand.allCases.count == 27)
    }

    @Test func コマンドはカテゴリ順に並ぶ() {
        let categories = SnapCommand.allCases.map(\.category)
        let expected = SnapCommand.Category.allCases.flatMap { category in
            Array(repeating: category, count: category.commands.count)
        }
        #expect(categories == expected)
        #expect(SnapCommand.Category.allCases == [.halves, .thirds, .fourths, .quarters, .sixths, .size])
    }

    @Test func カテゴリごとのコマンド数() {
        #expect(SnapCommand.Category.halves.commands == [.cycleLeft, .cycleRight, .topHalf, .bottomHalf])
        #expect(SnapCommand.Category.thirds.commands
                == [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
        #expect(SnapCommand.Category.fourths.commands == [.firstFourth, .secondFourth, .thirdFourth, .lastFourth])
        #expect(SnapCommand.Category.quarters.commands
                == [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter])
        #expect(SnapCommand.Category.sixths.commands == [
            .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
        ])
        #expect(SnapCommand.Category.size.commands == [.maximize, .maximizeHeight, .maximizeWidth, .center])
    }

    @Test func 既定で有効なのはMVPの8コマンドだけ() {
        let enabled = SnapCommand.allCases.filter(\.isEnabledByDefault)
        #expect(Set(enabled) == [
            .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .maximize, .leftThird, .centerThird, .rightThird,
        ])
    }

    /// KeyboardShortcuts は名前の文字列をキーに UserDefaults へ保存する。
    /// 既存ユーザーのキー割当を引き継ぐため、MVP の名前と一致していなければならない。
    @Test func 既存8コマンドのrawValueはMVPのKeyboardShortcuts名と一致する() {
        #expect(SnapCommand.cycleLeft.rawValue == "cycleLeft")
        #expect(SnapCommand.cycleRight.rawValue == "cycleRight")
        #expect(SnapCommand.topHalf.rawValue == "topHalf")
        #expect(SnapCommand.bottomHalf.rawValue == "bottomHalf")
        #expect(SnapCommand.maximize.rawValue == "maximize")
        #expect(SnapCommand.leftThird.rawValue == "leftThird")
        #expect(SnapCommand.centerThird.rawValue == "centerThird")
        #expect(SnapCommand.rightThird.rawValue == "rightThird")
    }

    @Test func rawValueは重複しない() {
        #expect(Set(SnapCommand.allCases.map(\.rawValue)).count == SnapCommand.allCases.count)
    }

    @Test func 左ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleLeft.sequence == [.leftHalf, .leftThird, .leftTwoThirds])
        #expect(SnapCommand.cycleLeft.isCycle)
    }

    @Test func 右ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleRight.sequence == [.rightHalf, .rightThird, .rightTwoThirds])
        #expect(SnapCommand.cycleRight.isCycle)
    }

    @Test func ループ系は左右の2つだけ() {
        #expect(SnapCommand.allCases.filter(\.isCycle) == [.cycleLeft, .cycleRight])
    }

    @Test(arguments: SnapCommand.allCases.filter { !$0.isCycle })
    func 単発コマンドの系列は1要素(command: SnapCommand) {
        #expect(command.sequence.count == 1)
    }

    @Test(arguments: [
        (SnapCommand.topHalf, SnapAction.topHalf),
        (SnapCommand.maximize, SnapAction.maximize),
        (SnapCommand.secondFourth, SnapAction.secondFourth),
        (SnapCommand.bottomRightQuarter, SnapAction.bottomRightQuarter),
        (SnapCommand.topCenterSixth, SnapAction.topCenterSixth),
        (SnapCommand.center, SnapAction.center),
    ])
    func 単発コマンドは同名の区画に対応する(command: SnapCommand, action: SnapAction) {
        #expect(command.sequence == [action])
    }

    @Test func 表示名は空でなく重複しない() {
        let titles = SnapCommand.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }
}
