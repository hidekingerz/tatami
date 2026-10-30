import CoreGraphics
import Testing
@testable import Tatami

struct RegionMatcherTests {
    let visible = CGRect(x: 0, y: 45, width: 1920, height: 1010)

    @Test func 区画ちょうどの枠はその区画() {
        for action in RegionMatcher.candidates {
            let frame = LayoutCalculator.frame(for: action, in: visible, current: visible)
            #expect(RegionMatcher.closestAction(to: frame, in: visible) == action, "\(action)")
        }
    }

    @Test func 少しずれた枠も同じ区画() {
        let frame = LayoutCalculator.frame(for: .leftTwoThirds, in: visible, current: visible).insetBy(dx: 10, dy: 10)
        #expect(RegionMatcher.closestAction(to: frame, in: visible) == .leftTwoThirds)
    }

    @Test func 自由サイズはnil() {
        #expect(RegionMatcher.closestAction(to: CGRect(x: 300, y: 300, width: 700, height: 500), in: visible) == nil)
    }

    @Test func サイズ系は候補に出ない() {
        #expect(!RegionMatcher.candidates.contains(.maximizeHeight))
        #expect(!RegionMatcher.candidates.contains(.maximizeWidth))
        #expect(!RegionMatcher.candidates.contains(.center))
        #expect(RegionMatcher.candidates.count == 24)
    }

    @Test func IoUの計算() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(RegionMatcher.intersectionOverUnion(a, a) == 1)
        #expect(RegionMatcher.intersectionOverUnion(a, CGRect(x: 50, y: 0, width: 100, height: 100)) == CGFloat(50) / 150)
        #expect(RegionMatcher.intersectionOverUnion(a, CGRect(x: 200, y: 0, width: 10, height: 10)) == 0)
    }
}
