// Tatami/App/ShortcutRegistrar.swift
import AppKit
import KeyboardShortcuts

extension SnapCommand {
    /// 既定キー。MVP の 8 コマンドだけが持ち、新しいコマンドはユーザーが記録するまでキーなし。
    var defaultShortcut: KeyboardShortcuts.Shortcut? {
        switch self {
        case .cycleLeft: .init(.b, modifiers: [.control, .option])
        case .cycleRight: .init(.f, modifiers: [.control, .option])
        case .topHalf: .init(.p, modifiers: [.control, .option])
        case .bottomHalf: .init(.n, modifiers: [.control, .option])
        case .maximize: .init(.m, modifiers: [.control, .option])
        case .leftThird: .init(.z, modifiers: [.control, .option])
        case .centerThird: .init(.x, modifiers: [.control, .option])
        case .rightThird: .init(.c, modifiers: [.control, .option])
        default: nil
        }
    }

    /// KeyboardShortcuts に登録する名前。rawValue をそのまま使うので、MVP からのキー割当を引き継ぐ。
    @MainActor
    var shortcutName: KeyboardShortcuts.Name {
        ShortcutNames.name(for: self)
    }
}

/// `KeyboardShortcuts.Name` をコマンドごとに 1 度だけ作るためのキャッシュ。
@MainActor
private enum ShortcutNames {
    private static var cache: [SnapCommand: KeyboardShortcuts.Name] = [:]

    static func name(for command: SnapCommand) -> KeyboardShortcuts.Name {
        if let cached = cache[command] {
            return cached
        }
        let name = KeyboardShortcuts.Name(command.rawValue, default: command.defaultShortcut)
        cache[command] = name
        return name
    }
}

/// すべてのショートカットを SnapEngine に接続し、有効/無効をホットキーの登録に反映する。
@MainActor
enum ShortcutRegistrar {
    /// 全コマンドのハンドラを登録し、無効なものはホットキーを解除する。
    /// `onKeyDown` はキーが割り当て済みならその場で登録するので、解除はその直後に行う。
    static func register(engine: SnapEngine, settings: CommandSettings) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                engine.perform(command)
            }
        }
        let disabled = SnapCommand.allCases.filter { !settings.isEnabled($0) }
        KeyboardShortcuts.disable(disabled.map(\.shortcutName))
        settings.onChange = { command, enabled in
            setEnabled(enabled, for: command)
        }
    }

    /// 有効ならホットキーを登録し、無効なら解除する。キーが未割当なら KeyboardShortcuts 側で何もしない。
    static func setEnabled(_ enabled: Bool, for command: SnapCommand) {
        if enabled {
            KeyboardShortcuts.enable(command.shortcutName)
        } else {
            KeyboardShortcuts.disable(command.shortcutName)
        }
    }
}
