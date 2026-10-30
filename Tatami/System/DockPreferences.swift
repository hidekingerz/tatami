import Foundation

enum DockPreferencesError: Error, Equatable {
    /// `killall Dock` が 0 以外で終了した。
    case restartFailed(status: Int32)
}

/// Dock の「最近の使用状況に基づいて操作スペースを自動的に並べ替える」設定。
protocol DockPreferencesReading: Sendable {
    var rearrangesSpacesAutomatically: Bool { get }
    func disableAutomaticRearrangement() throws
}

struct DockPreferences: DockPreferencesReading {
    private static let appID = "com.apple.dock"
    private static let key = "mru-spaces"

    var rearrangesSpacesAutomatically: Bool {
        Self.rearrangesSpacesAutomatically(from: CFPreferencesCopyAppValue(Self.key as CFString, Self.appID as CFString))
    }

    /// 値が未設定（nil）のときは macOS の既定どおりオン。
    static func rearrangesSpacesAutomatically(from value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return true }
        return number.boolValue
    }

    /// mru-spaces を false にして Dock を再起動する。
    func disableAutomaticRearrangement() throws {
        CFPreferencesSetAppValue(Self.key as CFString, kCFBooleanFalse, Self.appID as CFString)
        CFPreferencesAppSynchronize(Self.appID as CFString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DockPreferencesError.restartFailed(status: process.terminationStatus)
        }
    }
}
