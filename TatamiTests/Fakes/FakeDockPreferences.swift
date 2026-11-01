@testable import Tatami

/// テスト用の DockPreferencesReading。設定を固定値で返す。
struct FakeDockPreferences: DockPreferencesReading {
    var rearrangesSpacesAutomatically: Bool
    var switchesToAppSpace = true

    func disableAutomaticRearrangement() throws {}
}
