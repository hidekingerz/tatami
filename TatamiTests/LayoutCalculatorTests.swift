import CoreGraphics
import Testing
@testable import Tatami

struct LayoutCalculatorTests {
    /// 幅 1000・高さ 700 は 3 でも 2 でも割り切れない。
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    /// Dock を左に置き、プライマリの左側にある画面を想定した原点オフセット。
    let offsetScreen = CGRect(x: -1440, y: 25, width: 1440, height: 875)

    /// 区画系の計算では使われない現在枠。サイズ系（Task 2）で意味を持つ。
    let window = CGRect(x: 100, y: 100, width: 400, height: 300)
    /// 幅 1003・高さ 701 は 2・3・4 のどれでも割り切れない。
    let oddScreen = CGRect(x: 0, y: 0, width: 1003, height: 701)

    static let fourths: [SnapAction] = [.firstFourth, .secondFourth, .thirdFourth, .lastFourth]
    static let quarters: [SnapAction] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
    static let sixths: [SnapAction] = [
        .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
    ]

    @Test func 最大化はvisibleFrameそのもの() {
        #expect(LayoutCalculator.frame(for: .maximize, in: screen, current: window) == screen)
    }

    @Test func 左半分と右半分は隙間なく幅を埋める() {
        let left = LayoutCalculator.frame(for: .leftHalf, in: screen, current: window)
        let right = LayoutCalculator.frame(for: .rightHalf, in: screen, current: window)
        #expect(left == CGRect(x: 0, y: 0, width: 500, height: 700))
        #expect(right == CGRect(x: 500, y: 0, width: 500, height: 700))
    }

    @Test func 奇数幅の半分は右に端数を寄せる() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 700)
        let left = LayoutCalculator.frame(for: .leftHalf, in: odd, current: window)
        let right = LayoutCalculator.frame(for: .rightHalf, in: odd, current: window)
        #expect(left.width == 500)
        #expect(right.minX == 500)
        #expect(right.width == 501)
    }

    @Test func 上半分と下半分は隙間なく高さを埋める_上に端数を寄せる() {
        let top = LayoutCalculator.frame(for: .topHalf, in: screen, current: window)
        let bottom = LayoutCalculator.frame(for: .bottomHalf, in: screen, current: window)
        // NS 座標は下が原点。700 / 2 = 350 で割り切れるが、原点オフセット付きで端数も検証する。
        #expect(bottom == CGRect(x: 0, y: 0, width: 1000, height: 350))
        #expect(top == CGRect(x: 0, y: 350, width: 1000, height: 350))

        let oddTop = LayoutCalculator.frame(for: .topHalf, in: offsetScreen, current: window)
        let oddBottom = LayoutCalculator.frame(for: .bottomHalf, in: offsetScreen, current: window)
        #expect(oddBottom == CGRect(x: -1440, y: 25, width: 1440, height: 437))
        #expect(oddTop == CGRect(x: -1440, y: 462, width: 1440, height: 438))
    }

    @Test func 三分割は隙間なく幅を埋める_右に端数を寄せる() {
        let left = LayoutCalculator.frame(for: .leftThird, in: screen, current: window)
        let center = LayoutCalculator.frame(for: .centerThird, in: screen, current: window)
        let right = LayoutCalculator.frame(for: .rightThird, in: screen, current: window)
        #expect(left == CGRect(x: 0, y: 0, width: 333, height: 700))
        #expect(center == CGRect(x: 333, y: 0, width: 333, height: 700))
        #expect(right == CGRect(x: 666, y: 0, width: 334, height: 700))
    }

    @Test func 三分の二は三分の一と組み合わせて幅を埋める() {
        let leftTwo = LayoutCalculator.frame(for: .leftTwoThirds, in: screen, current: window)
        let rightTwo = LayoutCalculator.frame(for: .rightTwoThirds, in: screen, current: window)
        #expect(leftTwo == CGRect(x: 0, y: 0, width: 666, height: 700))
        #expect(rightTwo == CGRect(x: 333, y: 0, width: 667, height: 700))
    }

    @Test(arguments: SnapAction.allCases)
    func 全区画が原点オフセット付きvisibleFrameの内側に収まる(action: SnapAction) {
        let frame = LayoutCalculator.frame(for: action, in: offsetScreen, current: window)
        #expect(offsetScreen.contains(frame), "\(action) が画面外にはみ出している: \(frame)")
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test func 原点オフセット付きでも三分割は端から端まで埋める() {
        let left = LayoutCalculator.frame(for: .leftThird, in: offsetScreen, current: window)
        let right = LayoutCalculator.frame(for: .rightThird, in: offsetScreen, current: window)
        #expect(left.minX == offsetScreen.minX)
        #expect(right.maxX == offsetScreen.maxX)
    }

    @Test func 四分割は隙間なく幅を埋める_右に端数を寄せる() {
        let frames = Self.fourths.map { LayoutCalculator.frame(for: $0, in: oddScreen, current: window) }
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 250, height: 701))
        #expect(frames[1] == CGRect(x: 250, y: 0, width: 250, height: 701))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 250, height: 701))
        #expect(frames[3] == CGRect(x: 750, y: 0, width: 253, height: 701))
    }

    @Test func 四隅は半分の幅と高さの組み合わせ_右上に端数を寄せる() {
        #expect(LayoutCalculator.frame(for: .bottomLeftQuarter, in: oddScreen, current: window)
                == CGRect(x: 0, y: 0, width: 501, height: 350))
        #expect(LayoutCalculator.frame(for: .bottomRightQuarter, in: oddScreen, current: window)
                == CGRect(x: 501, y: 0, width: 502, height: 350))
        #expect(LayoutCalculator.frame(for: .topLeftQuarter, in: oddScreen, current: window)
                == CGRect(x: 0, y: 350, width: 501, height: 351))
        #expect(LayoutCalculator.frame(for: .topRightQuarter, in: oddScreen, current: window)
                == CGRect(x: 501, y: 350, width: 502, height: 351))
    }

    @Test func 六分割は三分の一の幅と半分の高さの組み合わせ() {
        #expect(LayoutCalculator.frame(for: .bottomLeftSixth, in: oddScreen, current: window)
                == CGRect(x: 0, y: 0, width: 334, height: 350))
        #expect(LayoutCalculator.frame(for: .topCenterSixth, in: oddScreen, current: window)
                == CGRect(x: 334, y: 350, width: 334, height: 351))
        #expect(LayoutCalculator.frame(for: .topRightSixth, in: oddScreen, current: window)
                == CGRect(x: 668, y: 350, width: 335, height: 351))
        #expect(LayoutCalculator.frame(for: .bottomRightSixth, in: oddScreen, current: window)
                == CGRect(x: 668, y: 0, width: 335, height: 350))
    }

    /// 同じ分割に属する区画が、隙間も重なりもなく visibleFrame を埋めることを総当たりで確かめる。
    @Test(arguments: [Self.fourths, Self.quarters, Self.sixths],
          [CGRect(x: 0, y: 0, width: 1000, height: 700),
           CGRect(x: 0, y: 0, width: 1003, height: 701),
           CGRect(x: -1440, y: 25, width: 1440, height: 875)])
    func 分割は隙間も重なりもなく画面を埋める(group: [SnapAction], visible: CGRect) {
        let frames = group.map { LayoutCalculator.frame(for: $0, in: visible, current: window) }
        for frame in frames {
            #expect(visible.contains(frame), "\(frame) が \(visible) からはみ出している")
        }
        let area = frames.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == visible.width * visible.height)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                #expect(a.intersection(b).isEmpty, "\(a) と \(b) が重なっている")
            }
        }
    }

    @Test func 高さを最大化は幅とxを保って縦いっぱいにする() {
        let frame = LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: window)
        #expect(frame == CGRect(x: 100, y: 0, width: 400, height: 700))
    }

    @Test func 幅を最大化は高さとyを保って横いっぱいにする() {
        let frame = LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: window)
        #expect(frame == CGRect(x: 0, y: 100, width: 1000, height: 300))
    }

    @Test func 中央に配置は大きさを保って画面中央に置く() {
        let frame = LayoutCalculator.frame(for: .center, in: screen, current: window)
        #expect(frame == CGRect(x: 300, y: 200, width: 400, height: 300))
    }

    @Test func 中央に配置の端数は切り捨てる_原点オフセット付き() {
        // offsetScreen の中心は (-720, 462.5)。幅 400・高さ 300 なら x = -920, y = 312.5 → 312。
        let frame = LayoutCalculator.frame(for: .center, in: offsetScreen, current: window)
        #expect(frame == CGRect(x: -920, y: 312, width: 400, height: 300))
    }

    @Test func 現在枠が画面より大きければ縮める() {
        let huge = CGRect(x: -50, y: -50, width: 1200, height: 900)
        #expect(LayoutCalculator.frame(for: .center, in: screen, current: huge) == screen)
        #expect(LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: huge) == screen)
        #expect(LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: huge) == screen)
    }

    @Test func 高さを最大化で右にはみ出すなら内側へ寄せる() {
        let nearRightEdge = CGRect(x: 800, y: 100, width: 400, height: 300)
        let frame = LayoutCalculator.frame(for: .maximizeHeight, in: screen, current: nearRightEdge)
        #expect(frame == CGRect(x: 600, y: 0, width: 400, height: 700))
    }

    @Test func 幅を最大化で上にはみ出すなら内側へ寄せる() {
        let nearTop = CGRect(x: 100, y: 600, width: 400, height: 300)
        let frame = LayoutCalculator.frame(for: .maximizeWidth, in: screen, current: nearTop)
        #expect(frame == CGRect(x: 0, y: 400, width: 1000, height: 300))
    }

    @Test(arguments: SnapAction.allCases)
    func 現在枠が画面外にあっても全区画が画面内に収まる(action: SnapAction) {
        let outside = CGRect(x: 5000, y: -3000, width: 1600, height: 1200)
        let frame = LayoutCalculator.frame(for: action, in: offsetScreen, current: outside)
        #expect(offsetScreen.contains(frame), "\(action) が画面外にはみ出している: \(frame)")
    }
}
