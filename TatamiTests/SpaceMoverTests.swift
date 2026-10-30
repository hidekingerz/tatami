import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct SpaceMoverTests {
    @Test func 掴む点の候補は4点() {
        let frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        #expect(CGEventSpaceMover.grabCandidates(for: frame) == [
            CGPoint(x: 180, y: 60), CGPoint(x: 500, y: 60), CGPoint(x: 860, y: 60), CGPoint(x: 500, y: 56),
        ])
    }

    @Test func 幅が狭ければ端の候補を外す() {
        let frame = CGRect(x: 100, y: 50, width: 150, height: 600)
        #expect(CGEventSpaceMover.grabCandidates(for: frame) == [CGPoint(x: 175, y: 60), CGPoint(x: 175, y: 56)])
    }

    @Test func 掴んでよいロールは許可リスト() {
        #expect(CGEventSpaceMover.allowedRoles.contains("AXWindow"))
        #expect(CGEventSpaceMover.allowedRoles.contains("AXGroup"))
        #expect(!CGEventSpaceMover.allowedRoles.contains("AXButton"))
        #expect(!CGEventSpaceMover.allowedRoles.contains("AXTab"))
        #expect(!CGEventSpaceMover.allowedRoles.contains("AXComboBox"))
    }
}
