import Foundation
import Testing
@testable import Tatami

struct LayoutSetTests {
    @Test func SnapActionはケース名で保存される() throws {
        let data = try JSONEncoder().encode([SnapAction.leftTwoThirds, .topLeftQuarter])
        #expect(String(data: data, encoding: .utf8) == #"["leftTwoThirds","topLeftQuarter"]"#)
    }

    @Test func 区画名は単発コマンドと同じ() {
        #expect(SnapAction.leftHalf.title == "左半分")
        #expect(SnapAction.leftTwoThirds.title == SnapCommand.leftTwoThirds.title)
        #expect(SnapAction.topLeftQuarter.title == SnapCommand.topLeftQuarter.title)
        #expect(SnapAction.center.title == SnapCommand.center.title)
        for command in SnapCommand.allCases where !command.isCycle {
            #expect(command.sequence[0].title == command.title)
        }
    }

    @Test func セットはJSONで往復する() throws {
        let set = LayoutSet(name: "作業", rows: [
            LayoutRow(bundleIdentifier: "com.github.wez.wezterm", appName: "WezTerm",
                      titleFilter: "herdr", action: .leftTwoThirds, desktop: nil),
            LayoutRow(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome",
                      action: .rightThird, desktop: 3),
        ])
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(LayoutSet.self, from: data)
        #expect(decoded == set)
    }

    @Test func デスクトップの範囲外はnilに丸める() throws {
        let json = #"{"id":"6B7B6B4C-0000-0000-0000-000000000001","bundleIdentifier":"a","appName":"A","titleFilter":"","action":null,"desktop":11}"#
        let row = try JSONDecoder().decode(LayoutRow.self, from: Data(json.utf8))
        #expect(row.desktop == nil)
        let zero = json.replacingOccurrences(of: "\"desktop\":11", with: "\"desktop\":0")
        #expect(try JSONDecoder().decode(LayoutRow.self, from: Data(zero.utf8)).desktop == nil)
    }

    @Test func 何もしない行の判定() {
        #expect(LayoutRow(bundleIdentifier: "a", appName: "A").isNoOp)
        #expect(!LayoutRow(bundleIdentifier: "a", appName: "A", action: .maximize).isNoOp)
        #expect(!LayoutRow(bundleIdentifier: "a", appName: "A", desktop: 2).isNoOp)
    }

    /// 将来の版で足された区画名を古い版で読んでも、その行が「変えない」になるだけでセット全体は読める。
    @Test func 未知の区画名はnilに丸めてセットは読める() throws {
        let json = #"{"id":"6B7B6B4C-0000-0000-0000-000000000002","name":"s","rows":[{"id":"6B7B6B4C-0000-0000-0000-000000000003","bundleIdentifier":"a","appName":"A","titleFilter":"","action":"futureRegion","desktop":2}]}"#
        let set = try JSONDecoder().decode(LayoutSet.self, from: Data(json.utf8))
        #expect(set.rows.count == 1)
        #expect(set.rows[0].action == nil)
        #expect(set.rows[0].desktop == 2)
    }
}
