// Tatami/App/ShortcutRegistrar.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let cycleLeft = Self("cycleLeft", default: .init(.b, modifiers: [.control, .option]))
    static let cycleRight = Self("cycleRight", default: .init(.f, modifiers: [.control, .option]))
    static let topHalf = Self("topHalf", default: .init(.p, modifiers: [.control, .option]))
    static let bottomHalf = Self("bottomHalf", default: .init(.n, modifiers: [.control, .option]))
    static let maximize = Self("maximize", default: .init(.m, modifiers: [.control, .option]))
    static let leftThird = Self("leftThird", default: .init(.z, modifiers: [.control, .option]))
    static let centerThird = Self("centerThird", default: .init(.x, modifiers: [.control, .option]))
    static let rightThird = Self("rightThird", default: .init(.c, modifiers: [.control, .option]))
}

extension SnapCommand {
    /// KeyboardShortcuts に登録する名前。
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .cycleLeft: .cycleLeft
        case .cycleRight: .cycleRight
        case .topHalf: .topHalf
        case .bottomHalf: .bottomHalf
        case .maximize: .maximize
        case .leftThird: .leftThird
        case .centerThird: .centerThird
        case .rightThird: .rightThird
        default: KeyboardShortcuts.Name(rawValue)
        }
    }
}

/// すべてのショートカットを SnapEngine に接続する。
@MainActor
enum ShortcutRegistrar {
    static func register(engine: SnapEngine) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                engine.perform(command)
            }
        }
    }
}
