// Tatami/App/CommandSettings.swift
import Foundation
import Observation

/// コマンドごとの有効/無効。UserDefaults に `command.<rawValue>.enabled` で保存する。
///
/// キー割当そのものは KeyboardShortcuts が別に保存しているので、ここでは触らない。
/// 無効にしてもキー割当は残り、再び有効にすれば同じキーで動く。
@MainActor
@Observable
final class CommandSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// 有効/無効が変わったときに呼ばれる。ShortcutRegistrar がホットキーの登録・解除に使う。
    @ObservationIgnored var onChange: ((SnapCommand, Bool) -> Void)?

    /// 観測用の写し。setEnabled のたびに更新し、設定画面の再描画を起こす。
    private var enabled: [SnapCommand: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Dictionary(uniqueKeysWithValues: SnapCommand.allCases.map { command in
            (command, Self.read(command, from: defaults))
        })
    }

    func isEnabled(_ command: SnapCommand) -> Bool {
        enabled[command] ?? command.isEnabledByDefault
    }

    func setEnabled(_ value: Bool, for command: SnapCommand) {
        defaults.set(value, forKey: Self.key(for: command))
        enabled[command] = value
        onChange?(command, value)
    }

    /// 有効なコマンド。`SnapCommand.allCases` の順。
    var enabledCommands: [SnapCommand] {
        SnapCommand.allCases.filter(isEnabled)
    }

    static func key(for command: SnapCommand) -> String {
        "command.\(command.rawValue).enabled"
    }

    /// 保存がなければ `isEnabledByDefault`。これで初回起動は MVP の 8 コマンドだけが有効になる。
    private static func read(_ command: SnapCommand, from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(for: command)) as? Bool ?? command.isEnabledByDefault
    }
}
