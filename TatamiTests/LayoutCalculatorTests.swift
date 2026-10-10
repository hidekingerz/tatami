import CoreGraphics
import Testing
@testable import Tatami

struct LayoutCalculatorTests {
    /// 幅 1000・高さ 700 は 3 でも 2 でも割り切れない。
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    /// Dock を左に置き、プライマリの左側にある画面を想定した原点オフセット。
    let offsetScreen = CGRect(x: -1440, y: 25, width: 1440, height: 875)

    @Test func 最大化はvisibleFrameそのもの() {
        #expect(LayoutCalculator.frame(for: .maximize, in: screen) == screen)
    }

    @Test func 左半分と右半分は隙間なく幅を埋める() {
        let left = LayoutCalculator.frame(for: .leftHalf, in: screen)
        let right = LayoutCalculator.frame(for: .rightHalf, in: screen)
        #expect(left == CGRect(x: 0, y: 0, width: 500, height: 700))
        #expect(right == CGRect(x: 500, y: 0, width: 500, height: 700))
    }

    @Test func 奇数幅の半分は右に端数を寄せる() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 700)
        let left = LayoutCalculator.frame(for: .leftHalf, in: odd)
        let right = LayoutCalculator.frame(for: .rightHalf, in: odd)
        #expect(left.width == 500)
        #expect(right.minX == 500)
        #expect(right.width == 501)
    }

    @Test func 上半分と下半分は隙間なく高さを埋める_上に端数を寄せる() {
        let top = LayoutCalculator.frame(for: .topHalf, in: screen)
        let bottom = LayoutCalculator.frame(for: .bottomHalf, in: screen)
        // NS 座標は下が原点。700 / 2 = 350 で割り切れるが、原点オフセット付きで端数も検証する。
        #expect(bottom == CGRect(x: 0, y: 0, width: 1000, height: 350))
        #expect(top == CGRect(x: 0, y: 350, width: 1000, height: 350))

        let oddTop = LayoutCalculator.frame(for: .topHalf, in: offsetScreen)
        let oddBottom = LayoutCalculator.frame(for: .bottomHalf, in: offsetScreen)
        #expect(oddBottom == CGRect(x: -1440, y: 25, width: 1440, height: 437))
        #expect(oddTop == CGRect(x: -1440, y: 462, width: 1440, height: 438))
    }

    @Test func 三分割は隙間なく幅を埋める_右に端数を寄せる() {
        let left = LayoutCalculator.frame(for: .leftThird, in: screen)
        let center = LayoutCalculator.frame(for: .centerThird, in: screen)
        let right = LayoutCalculator.frame(for: .rightThird, in: screen)
        #expect(left == CGRect(x: 0, y: 0, width: 333, height: 700))
        #expect(center == CGRect(x: 333, y: 0, width: 333, height: 700))
        #expect(right == CGRect(x: 666, y: 0, width: 334, height: 700))
    }

    @Test func 三分の二は三分の一と組み合わせて幅を埋める() {
        let leftTwo = LayoutCalculator.frame(for: .leftTwoThirds, in: screen)
        let rightTwo = LayoutCalculator.frame(for: .rightTwoThirds, in: screen)
        #expect(leftTwo == CGRect(x: 0, y: 0, width: 666, height: 700))
        #expect(rightTwo == CGRect(x: 333, y: 0, width: 667, height: 700))
    }

    @Test(arguments: SnapAction.allCases)
    func 全区画が原点オフセット付きvisibleFrameの内側に収まる(action: SnapAction) {
        let frame = LayoutCalculator.frame(for: action, in: offsetScreen)
        #expect(offsetScreen.contains(frame), "\(action) が画面外にはみ出している: \(frame)")
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test func 原点オフセット付きでも三分割は端から端まで埋める() {
        let left = LayoutCalculator.frame(for: .leftThird, in: offsetScreen)
        let right = LayoutCalculator.frame(for: .rightThird, in: offsetScreen)
        #expect(left.minX == offsetScreen.minX)
        #expect(right.maxX == offsetScreen.maxX)
    }
}
