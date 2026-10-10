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
    /// 全コマンドのハンドラを登録し、有効/無効をホットキーに反映する。
    /// Carbon のホットキーは名前ではなくキーの組み合わせ単位で登録され、同じキーを持つ名前のハンドラは全部呼ばれる。
    /// そのため無効コマンドのキーが有効コマンドと同じ場合に備え、ハンドラ側で無効を弾く。
    static func register(engine: SnapEngine, settings: CommandSettings) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                guard settings.isEnabled(command) else { return }
                engine.perform(command)
            }
        }
        apply(settings: settings)
        settings.onChange = { _, _ in
            apply(settings: settings)
        }
    }

    /// 有効状態をホットキーの登録に合わせ直す。
    /// 先に無効コマンドの名前を解除し、そのあと有効コマンドの名前を登録し直す。
    /// 解除はキー自体を外してしまうので、有効コマンドが同じキーを持っていても再登録で復活させる。
    /// `enable` は登録済みなら何もせず、キー未割当の名前も無視される。
    static func apply(settings: CommandSettings) {
        let disabled = SnapCommand.allCases.filter { !settings.isEnabled($0) }
        KeyboardShortcuts.disable(disabled.map(\.shortcutName))
        KeyboardShortcuts.enable(settings.enabledCommands.map(\.shortcutName))
    }
}
