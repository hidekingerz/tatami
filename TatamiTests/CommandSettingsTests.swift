import Foundation
import Testing
@testable import Tatami

/// テストごとに別の suite 名の UserDefaults を使い、終了時に消す。
@MainActor
final class CommandSettingsTests {
    let suiteName = "dev.hidekingerz.tatamiTests.CommandSettings.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func 設定がなければ既定値を返す() {
        let settings = CommandSettings(defaults: defaults)
        #expect(settings.isEnabled(.cycleLeft))
        #expect(settings.isEnabled(.maximize))
        #expect(!settings.isEnabled(.topLeftQuarter))
        #expect(!settings.isEnabled(.center))
        #expect(settings.enabledCommands == [
            .cycleLeft, .cycleRight, .topHalf, .bottomHalf, .leftThird, .centerThird, .rightThird, .maximize,
        ])
    }

    @Test func 保存キーはcommand_rawValue_enabled() {
        #expect(CommandSettings.key(for: .topLeftQuarter) == "command.topLeftQuarter.enabled")
    }

    @Test func 変更は読み戻せる() {
        let settings = CommandSettings(defaults: defaults)
        settings.setEnabled(true, for: .topLeftQuarter)
        settings.setEnabled(false, for: .maximize)
        #expect(settings.isEnabled(.topLeftQuarter))
        #expect(!settings.isEnabled(.maximize))
        #expect(defaults.bool(forKey: "command.topLeftQuarter.enabled"))
        #expect(defaults.object(forKey: "command.maximize.enabled") as? Bool == false)
    }

    @Test func 別インスタンスでも同じUserDefaultsなら同じ値() {
        CommandSettings(defaults: defaults).setEnabled(true, for: .center)
        let reloaded = CommandSettings(defaults: defaults)
        #expect(reloaded.isEnabled(.center))
        #expect(reloaded.enabledCommands.contains(.center))
    }

    /// キーが未設定でも有効/無効は独立して保存される（キーは KeyboardShortcuts が別に持つ）。
    @Test func キーの有無に関係なく保存される() {
        let settings = CommandSettings(defaults: defaults)
        settings.setEnabled(true, for: .bottomCenterSixth)
        #expect(settings.isEnabled(.bottomCenterSixth))
    }

    @Test func 変更するとonChangeが呼ばれる() {
        let settings = CommandSettings(defaults: defaults)
        var received: [(SnapCommand, Bool)] = []
        settings.onChange = { received.append(($0, $1)) }
        settings.setEnabled(true, for: .firstFourth)
        settings.setEnabled(false, for: .firstFourth)
        #expect(received.map(\.0) == [.firstFourth, .firstFourth])
        #expect(received.map(\.1) == [true, false])
    }
}
