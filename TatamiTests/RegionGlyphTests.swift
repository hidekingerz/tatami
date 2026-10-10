import CoreGraphics
import Testing
@testable import Tatami

struct RegionGlyphTests {
    @Test func 左半分は左側の半分() {
        #expect(RegionGlyph.normalizedRegion(for: .leftHalf) == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func 右上の四隅は右上() {
        #expect(RegionGlyph.normalizedRegion(for: .topRightQuarter) == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test func 中央に配置は代表枠を中央に置いた形() {
        #expect(RegionGlyph.normalizedRegion(for: .center) == CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6))
    }

    @Test func 高さを最大化は縦長_幅を最大化は横長() {
        let tall = RegionGlyph.normalizedRegion(for: .maximizeHeight)
        let wide = RegionGlyph.normalizedRegion(for: .maximizeWidth)
        #expect(tall == CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        #expect(wide == CGRect(x: 0, y: 0.2, width: 1, height: 0.6))
    }

    @Test(arguments: SnapAction.allCases)
    func 全区画が0から1の範囲に収まり空でない(action: SnapAction) {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let region = RegionGlyph.normalizedRegion(for: action)
        #expect(unit.contains(region), "\(action): \(region)")
        #expect(region.width > 0 && region.height > 0)
    }
}
