import Carbon.HIToolbox
import Foundation
import OSLog

/// 入力ソースのうち、切り替え判断に必要な属性だけを取り出した値。
struct InputSourceInfo: Equatable, Sendable {
    let id: String
    let isASCIICapable: Bool
    let isSelectable: Bool
    let isKeyboardLayout: Bool
}

enum InputSourcePolicy {
    static let preferredID = "com.apple.keylayout.ABC"

    /// 切り替え先。いまが ASCII 入力可能なら nil（切り替え不要）。
    nonisolated static func target(current: InputSourceInfo, candidates: [InputSourceInfo]) -> InputSourceInfo? {
        if current.isASCIICapable { return nil }
        if let preferred = candidates.first(where: { $0.id == preferredID && $0.isSelectable }) {
            return preferred
        }
        return candidates.first { $0.isASCIICapable && $0.isSelectable && $0.isKeyboardLayout }
    }
}

/// ピッカーを開いている間だけ入力ソースを ASCII にし、閉じたら戻す。
@MainActor
protocol InputSourceSwitching: AnyObject {
    func enterASCII()
    func restore()
}

@MainActor
final class CarbonInputSourceSwitcher: InputSourceSwitching {
    private static let logger = Logger(subsystem: "dev.hidekingerz.tatami", category: "InputSource")

    private var previous: TISInputSource?

    func enterASCII() {
        // 二重に呼ばれても最初の入力ソースを保持する。
        guard previous == nil else { return }
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let current = Self.info(of: currentSource) else {
            Self.logger.error("could not read the current input source")
            return
        }
        let candidates = Self.enabledKeyboardSources()
        guard let target = InputSourcePolicy.target(current: current, candidates: candidates.map(\.info)),
              let targetSource = candidates.first(where: { $0.info.id == target.id })?.source else { return }

        let status = TISSelectInputSource(targetSource)
        if status == noErr {
            previous = currentSource
        } else {
            previous = nil
            Self.logger.error("TISSelectInputSource(\(target.id, privacy: .public)) failed: \(status)")
        }
    }

    func restore() {
        guard let source = previous else { return }
        previous = nil
        let status = TISSelectInputSource(source)
        if status != noErr {
            Self.logger.error("restoring the input source failed: \(status)")
        }
    }

    private static func enabledKeyboardSources() -> [(source: TISInputSource, info: InputSourceInfo)] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { source in
            guard bool(source, kTISPropertyInputSourceIsEnabled) == true,
                  string(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  let info = info(of: source) else { return nil }
            return (source, info)
        }
    }

    private static func info(of source: TISInputSource) -> InputSourceInfo? {
        guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
        return InputSourceInfo(
            id: id,
            isASCIICapable: bool(source, kTISPropertyInputSourceIsASCIICapable) ?? false,
            isSelectable: bool(source, kTISPropertyInputSourceIsSelectCapable) ?? false,
            isKeyboardLayout: string(source, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String)
        )
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }
}
