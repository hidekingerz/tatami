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

extension LayoutSet {
    /// KeyboardShortcuts に登録する名前。既定キーはなく、ユーザーが記録したときだけ効く。
    @MainActor
    var shortcutName: KeyboardShortcuts.Name {
        LayoutSetShortcutNames.name(for: id)
    }
}

/// `KeyboardShortcuts.Name` をレイアウトセットごとに 1 度だけ作るためのキャッシュ。
@MainActor
private enum LayoutSetShortcutNames {
    private static var cache: [UUID: KeyboardShortcuts.Name] = [:]

    static func name(for id: UUID) -> KeyboardShortcuts.Name {
        if let cached = cache[id] {
            return cached
        }
        let name = KeyboardShortcuts.Name("layoutSet.\(id.uuidString)")
        cache[id] = name
        return name
    }

    static func forget(_ id: UUID) {
        cache[id] = nil
    }
}

/// すべてのショートカットを SnapEngine とレイアウトセットに接続し、有効/無効をホットキーの登録に反映する。
@MainActor
enum ShortcutRegistrar {
    /// レイアウトセットのピッカーを開くショートカット。既定キーなし。
    static let pickerName = KeyboardShortcuts.Name("layoutSets.picker")

    /// ハンドラを登録済みのレイアウトセット。store の変更時に追加・削除の差分を取るのに使う。
    private static var registeredSetIDs: Set<UUID> = []

    /// 全コマンドのハンドラを登録し、有効/無効をホットキーに反映する。
    /// Carbon のホットキーは名前ではなくキーの組み合わせ単位で登録され、同じキーを持つ名前のハンドラは全部呼ばれる。
    /// そのため無効コマンドのキーが有効コマンドと同じ場合に備え、ハンドラ側で無効を弾く。
    /// レイアウトセットの適用中（isBusy）と tatami 自身が前面にあるとき（設定画面やピッカーの操作中）は beep して何もしない。
    static func register(engine: SnapEngine, settings: CommandSettings, isBusy: @escaping @MainActor () -> Bool) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                guard settings.isEnabled(command) else { return }
                guard !isBusy(), !NSApp.isActive else {
                    NSSound.beep()
                    return
                }
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

extension ShortcutRegistrar {
    /// ピッカーと各セットのハンドラを登録し、store.onChange で追加・削除に追従する。
    /// 削除されたセットはハンドラを外し、記録されたキーも消す（同じ id が戻ることはないので残しても使われない）。
    /// isBusy のときはどのハンドラも beep して何もしない（適用中にピッカーで tatami が前面に来ると合成マウス操作を邪魔する）。
    static func registerLayoutSets(
        store: LayoutSetStore, isBusy: @escaping @MainActor () -> Bool,
        onPicker: @escaping @MainActor () -> Void,
        onApply: @escaping @MainActor (LayoutSet) -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: pickerName) {
            guard !isBusy() else {
                NSSound.beep()
                return
            }
            onPicker()
        }

        let sync: @MainActor ([LayoutSet]) -> Void = { sets in
            let current = Set(sets.map(\.id))
            for id in registeredSetIDs.subtracting(current) {
                let name = LayoutSetShortcutNames.name(for: id)
                KeyboardShortcuts.removeHandler(for: name)
                KeyboardShortcuts.reset(name)
                LayoutSetShortcutNames.forget(id)
            }
            for id in current.subtracting(registeredSetIDs) {
                KeyboardShortcuts.onKeyDown(for: LayoutSetShortcutNames.name(for: id)) {
                    guard !isBusy() else {
                        NSSound.beep()
                        return
                    }
                    // 名前や行の変更に追従するため、押された時点のセットを引き直す。
                    guard let set = store.set(id: id) else { return }
                    onApply(set)
                }
            }
            registeredSetIDs = current
        }
        sync(store.sets)
        store.onChange = { sets in sync(sets) }
    }
}
