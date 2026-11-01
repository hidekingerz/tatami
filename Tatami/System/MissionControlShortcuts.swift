import CoreGraphics
import Foundation

/// キーコードと修飾キーの組。
struct KeyCombo: Equatable, Sendable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

/// Mission Control の「デスクトップ N へ切り替え」ショートカットを読む。
protocol MissionControlShortcutReading: Sendable {
    /// 「デスクトップ desktop へ切り替え」が有効ならそのキー。無効・未設定・範囲外なら nil。
    func switchToDesktopShortcut(_ desktop: Int) -> KeyCombo?
}

struct MissionControlShortcuts: MissionControlShortcutReading {
    /// com.apple.symbolichotkeys の AppleSymbolicHotKeys を読む。キャッシュしない。
    func switchToDesktopShortcut(_ desktop: Int) -> KeyCombo? {
        let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        )
        guard let hotKeys = raw as? [String: Any] else { return nil }
        return Self.shortcut(forDesktop: desktop, in: hotKeys)
    }

    /// 純粋な解析。hotKeys は AppleSymbolicHotKeys 辞書（キーは "118" のような文字列）。
    static func shortcut(forDesktop desktop: Int, in hotKeys: [String: Any]) -> KeyCombo? {
        guard (1...10).contains(desktop),
              let entry = hotKeys["\(hotKeyID(forDesktop: desktop))"] as? [String: Any],
              let enabled = (entry["enabled"] as? NSNumber)?.boolValue, enabled,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count == 3
        else { return nil }
        let numbers = parameters.compactMap { ($0 as? NSNumber)?.intValue }
        // 65535 は「キー未割り当て」の印。CGKeyCode（UInt16）に収まらない値も捨てる。
        guard numbers.count == 3, numbers[2] >= 0, numbers[1] != 65535,
              let keyCode = CGKeyCode(exactly: numbers[1])
        else { return nil }
        // 修飾キーのビットは CGEventFlags と同じ値（control 0x40000, option 0x80000, shift 0x20000, command 0x100000）。
        let modifiers = CGEventFlags(rawValue: UInt64(numbers[2]))
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        return KeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    /// 「デスクトップ N へ切り替え」のホットキー ID（デスクトップ 1 が 118）。
    static func hotKeyID(forDesktop desktop: Int) -> Int {
        117 + desktop
    }
}
