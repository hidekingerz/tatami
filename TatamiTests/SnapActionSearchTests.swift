import Testing
@testable import Tatami

struct SnapActionSearchTests {
    /// query で絞った区画（カテゴリ順）。
    func filter(_ query: String) -> [SnapAction] {
        let tokens = PickerQuery.tokens(query)
        return SnapAction.allInCategoryOrder.filter { PickerQuery.matches(tokens: tokens, terms: $0.searchTerms) }
    }

    @Test func 全区画に小文字の語彙がある() {
        for action in SnapAction.allCases {
            #expect(!action.searchTerms.isEmpty, "\(action)")
            #expect(action.searchTerms.allSatisfy { $0 == $0.lowercased() }, "\(action)")
            #expect(action.searchTerms.contains(action.title.lowercased()), "\(action)")
        }
    }

    @Test func 記号と分数で右三分の一だけになる() {
        #expect(filter("> 1/3") == [.rightThird])
        #expect(filter("r3") == [.rightThird])
        #expect(filter("migi 1/3") == [.rightThird])
        #expect(filter("右 1/3") == [.rightThird])
    }

    @Test func 左の記号で左系がまとめて残る() {
        let expected: [SnapAction] = [.leftHalf, .leftThird, .leftTwoThirds, .firstFourth,
                                      .topLeftQuarter, .bottomLeftQuarter, .topLeftSixth, .bottomLeftSixth]
        #expect(filter("<") == expected)
        #expect(filter("left") == expected)
    }

    @Test func 四隅はどちらの順でも効く() {
        #expect(filter("<^") == [.topLeftQuarter, .topLeftSixth])
        #expect(filter("^<") == [.topLeftQuarter, .topLeftSixth])
        #expect(filter(">v 1/6") == [.bottomRightSixth])
    }

    @Test func ローマ字と略号() {
        #expect(filter("hanbun") == [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
        #expect(filter("l23") == [.leftTwoThirds])
        #expect(filter("q2") == [.secondFourth])
        #expect(filter("max") == [.maximize, .maximizeHeight, .maximizeWidth])
        #expect(filter("takasa") == [.maximizeHeight])
    }

    @Test func lで右四分の一は残らない() {
        #expect(!filter("l").contains(.lastFourth))
        #expect(filter("l").contains(.leftHalf))
    }

    @Test func 数字の2は左三分の二と左から2番目の両方() {
        #expect(filter("2") == [.leftTwoThirds, .rightTwoThirds, .secondFourth])
    }
}
