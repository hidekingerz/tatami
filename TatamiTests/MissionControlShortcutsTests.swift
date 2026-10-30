import CoreGraphics
import Testing
@testable import Tatami

struct MissionControlShortcutsTests {
    /// システム設定が保存する形。parameters は [文字コード, キーコード, 修飾キー]。65535 は文字なし。
    static func entry(enabled: Bool, keyCode: Int, modifiers: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, keyCode, modifiers], "type": "standard"]]
    }

    @Test func デスクトップ1は118でctrl1になる() {
        let hotKeys = ["118": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000)]
        let combo = MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys)
        #expect(combo == KeyCombo(keyCode: 18, modifiers: .maskControl))
    }

    @Test func デスクトップ2から10は119から127() {
        #expect(MissionControlShortcuts.hotKeyID(forDesktop: 2) == 119)
        #expect(MissionControlShortcuts.hotKeyID(forDesktop: 10) == 127)
        let hotKeys = ["127": Self.entry(enabled: true, keyCode: 29, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 10, in: hotKeys)?.keyCode == 29)
    }

    @Test func 無効ならnil() {
        let hotKeys = ["118": Self.entry(enabled: false, keyCode: 18, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys) == nil)
    }

    @Test func 項目がなければnil() {
        #expect(MissionControlShortcuts.shortcut(forDesktop: 3, in: [:]) == nil)
    }

    @Test func 範囲外のデスクトップはnil() {
        let hotKeys = ["117": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000)]
        #expect(MissionControlShortcuts.shortcut(forDesktop: 0, in: hotKeys) == nil)
        #expect(MissionControlShortcuts.shortcut(forDesktop: 11, in: hotKeys) == nil)
    }

    @Test func 修飾キーはcontrol_option_shift_commandだけ拾う() {
        // control + option + shift + command + 無関係なビット
        let hotKeys = ["118": Self.entry(enabled: true, keyCode: 18, modifiers: 0x40000 | 0x80000 | 0x20000 | 0x100000 | 0x1)]
        let combo = MissionControlShortcuts.shortcut(forDesktop: 1, in: hotKeys)
        #expect(combo?.modifiers == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }
}
