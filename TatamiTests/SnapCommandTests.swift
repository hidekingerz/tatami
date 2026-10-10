import Testing
@testable import Tatami

struct SnapCommandTests {
    @Test func 区画は10種類ある() {
        #expect(SnapAction.allCases.count == 10)
    }

    @Test func コマンドは8種類ある() {
        #expect(SnapCommand.allCases.count == 8)
    }

    @Test func 設定画面の並びは左右ループ_上下_最大化_1_3の左中右() {
        #expect(SnapCommand.allCases == [
            .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .maximize, .leftThird, .centerThird, .rightThird,
        ])
    }

    @Test func 左ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleLeft.sequence == [.leftHalf, .leftThird, .leftTwoThirds])
    }

    @Test func 右ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleRight.sequence == [.rightHalf, .rightThird, .rightTwoThirds])
    }

    @Test(arguments: [
        (SnapCommand.topHalf, SnapAction.topHalf),
        (SnapCommand.bottomHalf, SnapAction.bottomHalf),
        (SnapCommand.maximize, SnapAction.maximize),
        (SnapCommand.leftThird, SnapAction.leftThird),
        (SnapCommand.centerThird, SnapAction.centerThird),
        (SnapCommand.rightThird, SnapAction.rightThird),
    ])
    func 単発コマンドの系列は1要素(command: SnapCommand, action: SnapAction) {
        #expect(command.sequence == [action])
    }
}
