// TatamiTests/ShortcutDefaultsTests.swift
import AppKit
import KeyboardShortcuts
import Testing
@testable import Tatami

@Suite("既定ショートカット")
struct ShortcutDefaultsTests {
    @Test("MVP の 8 コマンドは ⌃⌥ + 既定キーを持つ", arguments: [
        (SnapCommand.cycleLeft, KeyboardShortcuts.Key.b),
        (.cycleRight, .f),
        (.topHalf, .p),
        (.bottomHalf, .n),
        (.maximize, .m),
        (.leftThird, .z),
        (.centerThird, .x),
        (.rightThird, .c),
    ])
    func MVPコマンドの既定キー(command: SnapCommand, key: KeyboardShortcuts.Key) {
        let shortcut = command.defaultShortcut
        #expect(shortcut?.key == key)
        #expect(shortcut?.modifiers == [.control, .option])
    }

    @Test("既定で無効のコマンドは既定キーを持たない")
    func 新コマンドは既定キーなし() {
        for command in SnapCommand.allCases where !command.isEnabledByDefault {
            #expect(command.defaultShortcut == nil)
        }
    }
}
