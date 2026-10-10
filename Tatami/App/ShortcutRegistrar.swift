// Tatami/App/ShortcutRegistrar.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let cycleLeft = Self("cycleLeft", default: .init(.b, modifiers: [.control, .option]))
    static let cycleRight = Self("cycleRight", default: .init(.f, modifiers: [.control, .option]))
    static let topHalf = Self("topHalf", default: .init(.p, modifiers: [.control, .option]))
    static let bottomHalf = Self("bottomHalf", default: .init(.n, modifiers: [.control, .option]))
    static let maximize = Self("maximize", default: .init(.m, modifiers: [.control, .option]))
    static let centerThird = Self("centerThird", default: .init(.c, modifiers: [.control, .option]))
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
        case .centerThird: .centerThird
        }
    }

    /// 設定画面に表示するラベル。
    var title: String {
        switch self {
        case .cycleLeft: "左半分 / 左 1/3 / 左 2/3"
        case .cycleRight: "右半分 / 右 1/3 / 右 2/3"
        case .topHalf: "上半分"
        case .bottomHalf: "下半分"
        case .maximize: "最大化"
        case .centerThird: "中央 1/3"
        }
    }
}

/// 6 つのショートカットを SnapEngine に接続する。
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
