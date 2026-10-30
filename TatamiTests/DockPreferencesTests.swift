import Testing
@testable import Tatami

struct DockPreferencesTests {
    @Test func 値がなければ自動並べ替えはオン() {
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: nil))
    }

    @Test func falseが保存されていればオフ() {
        #expect(!DockPreferences.rearrangesSpacesAutomatically(from: false))
        #expect(!DockPreferences.rearrangesSpacesAutomatically(from: 0))
    }

    @Test func trueが保存されていればオン() {
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: true))
        #expect(DockPreferences.rearrangesSpacesAutomatically(from: 1))
    }
}
