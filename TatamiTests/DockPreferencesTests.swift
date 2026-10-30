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

    @Test func 値がなければアプリのスペースへ切り替える() {
        #expect(DockPreferences.switchesToAppSpace(from: nil))
    }

    @Test func workspacesAutoSwooshが保存されていればその値() {
        #expect(!DockPreferences.switchesToAppSpace(from: false))
        #expect(DockPreferences.switchesToAppSpace(from: true))
    }
}
