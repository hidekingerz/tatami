import Testing
@testable import Tatami

struct SnapCommandTests {
    @Test func 区画は10種類ある() {
        #expect(SnapAction.allCases.count == 10)
    }

    @Test func コマンドは6種類ある() {
        #expect(SnapCommand.allCases.count == 6)
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
        (SnapCommand.centerThird, SnapAction.centerThird),
    ])
    func 単発コマンドの系列は1要素(command: SnapCommand, action: SnapAction) {
        #expect(command.sequence == [action])
    }
}
