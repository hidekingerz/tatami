@testable import Tatami

/// テスト用の DockPreferencesReading。自動並べ替えの設定を固定値で返す。
struct FakeDockPreferences: DockPreferencesReading {
    var rearrangesSpacesAutomatically: Bool

    func disableAutomaticRearrangement() throws {}
}
