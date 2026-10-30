// Tatami/App/DebugMenu.swift
import AppKit
import SwiftUI
import os

/// スパイク用のデバッグメニュー。`defaults write dev.hidekingerz.tatami debugMenu -bool YES` のときだけ出す。
struct DebugMenu: View {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugMenu")
    }

    private var actions: DebugActions { DebugActions.shared }

    var body: some View {
        Menu("デバッグ") {
            Menu("最前面の窓をデスクトップ N へ（3 秒後）") {
                ForEach(1...5, id: \.self) { desktop in
                    Button("デスクトップ \(desktop)") { actions.moveFrontmostWindow(toDesktop: desktop, dragged: false) }
                }
            }
            Menu("同上（leftMouseDragged あり）") {
                ForEach(1...5, id: \.self) { desktop in
                    Button("デスクトップ \(desktop)") { actions.moveFrontmostWindow(toDesktop: desktop, dragged: true) }
                }
            }
            Menu("デスクトップ N へ切り替えるだけ") {
                ForEach(1...5, id: \.self) { desktop in
                    Button("デスクトップ \(desktop)") { actions.switchTo(desktop: desktop) }
                }
            }
            Divider()
            Button("最前面アプリの窓一覧をログ（3 秒後）") { actions.logFrontmostAppWindows() }
            Button("記憶した窓の 2 枚目を activate + raise（3 秒後）") { actions.activateAndRaiseRememberedSecond() }
            Button("画面に見えている窓をログ") { actions.logOnScreenWindows() }
            Button("Mission Control / Dock の設定をログ") { actions.logSettings() }
        }
    }
}

/// デバッグメニューの各操作。spaceChangeCount を操作をまたいで数えるため、mover は使い回す。
@MainActor
final class DebugActions {
    static let shared = DebugActions()

    private let logger = Logger(subsystem: "dev.hidekingerz.tatami", category: "Debug")
    private let windowService = AccessibilityWindowService()
    private let enumerator = AccessibilityWindowEnumerator()
    private let shortcuts = MissionControlShortcuts()
    private lazy var mover = makeMover(timing: SpaceMoverTiming())
    private lazy var draggingMover = makeMover(timing: SpaceMoverTiming(dragOffset: 2))
    /// 「最前面アプリの窓一覧をログ」で記憶した一覧。
    private var rememberedWindows: [WindowInfo] = []

    private func makeMover(timing: SpaceMoverTiming) -> CGEventSpaceMover {
        CGEventSpaceMover(shortcuts: shortcuts, enumerator: enumerator, windowService: windowService, timing: timing)
    }

    /// 3 秒待ってから（利用者が対象アプリへ切り替える時間）、最前面の窓を desktop へ運ぶ。
    func moveFrontmostWindow(toDesktop desktop: Int, dragged: Bool) {
        Task {
            try await Task.sleep(for: .seconds(3))
            let mover = dragged ? draggingMover : mover
            let label = dragged ? "move(drag)" : "move"
            let window: WindowHandle
            do {
                window = try windowService.focusedWindow()
            } catch {
                logger.error("\(label, privacy: .public) → desktop \(desktop): focusedWindow 失敗 \(String(describing: error), privacy: .public)")
                return
            }
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            logger.info("\(label, privacy: .public) → desktop \(desktop): 開始 app=\(app, privacy: .public) count=\(mover.spaceChangeCount)")
            do {
                try await mover.move(window, toDesktop: desktop)
                logger.info("\(label, privacy: .public) → desktop \(desktop): 成功 候補点=\(Self.describe(mover.lastGrabCandidateIndex), privacy: .public) count=\(mover.spaceChangeCount)")
            } catch {
                logger.error("\(label, privacy: .public) → desktop \(desktop): 失敗 \(String(describing: error), privacy: .public) 候補点=\(Self.describe(mover.lastGrabCandidateIndex), privacy: .public) count=\(mover.spaceChangeCount)")
            }
        }
    }

    /// 何も掴まずにキーだけ送る。
    func switchTo(desktop: Int) {
        Task {
            let before = mover.spaceChangeCount
            do {
                let switched = try await mover.switchTo(desktop: desktop)
                logger.info("switchTo desktop \(desktop): 戻り値=\(switched, privacy: .public) count=\(before)→\(self.mover.spaceChangeCount)")
            } catch {
                logger.error("switchTo desktop \(desktop): 失敗 \(String(describing: error), privacy: .public) count=\(before)→\(self.mover.spaceChangeCount)")
            }
        }
    }

    /// 3 秒待ってから、最前面アプリの窓一覧をログに出して記憶する。
    func logFrontmostAppWindows() {
        Task {
            try await Task.sleep(for: .seconds(3))
            guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
                logger.error("windows: 最前面アプリの bundle id が取れない")
                return
            }
            guard let windows = enumerator.windows(ofBundleIdentifier: bundleID) else {
                logger.error("windows(\(bundleID, privacy: .public)): nil（起動していない／通常アプリでない）")
                return
            }
            rememberedWindows = windows
            logger.info("windows(\(bundleID, privacy: .public)): \(windows.count) 枚")
            for (index, info) in windows.enumerated() {
                logger.info("  [\(index)] \(Self.describe(info), privacy: .public)")
            }
        }
    }

    /// 3 秒待ってから、記憶した 2 枚目を activate → raise し、1 秒後に isOnScreen をログ。
    func activateAndRaiseRememberedSecond() {
        Task {
            try await Task.sleep(for: .seconds(3))
            guard rememberedWindows.count >= 2 else {
                logger.error("activate+raise: 記憶した窓が 2 枚未満（\(self.rememberedWindows.count) 枚）")
                return
            }
            let info = rememberedWindows[1]
            let before = mover.spaceChangeCount
            do {
                try windowService.activate(info.handle)
                try windowService.raise(info.handle)
            } catch {
                logger.error("activate+raise: 失敗 \(String(describing: error), privacy: .public)")
                return
            }
            try await Task.sleep(for: .seconds(1))
            logger.info("activate+raise \"\(info.title, privacy: .public)\": isOnScreen=\(self.enumerator.isOnScreen(info.handle), privacy: .public) count=\(before)→\(self.mover.spaceChangeCount)")
        }
    }

    /// いまのデスクトップで見えている窓を即時にログ。
    func logOnScreenWindows() {
        let windows = enumerator.onScreenWindows()
        logger.info("onScreenWindows: \(windows.count) 枚")
        for (index, info) in windows.enumerated() {
            logger.info("  [\(index)] \(info.bundleIdentifier, privacy: .public) \(Self.describe(info), privacy: .public)")
        }
    }

    /// デスクトップ 1〜10 の切替キーと mru-spaces をログ。
    func logSettings() {
        for desktop in 1...10 {
            let text = shortcuts.switchToDesktopShortcut(desktop).map {
                "keyCode=\($0.keyCode) modifiers=0x\(String($0.modifiers.rawValue, radix: 16))"
            } ?? "nil"
            logger.info("switchToDesktopShortcut(\(desktop)): \(text, privacy: .public)")
        }
        logger.info("rearrangesSpacesAutomatically (mru-spaces): \(DockPreferences().rearrangesSpacesAutomatically, privacy: .public)")
    }

    private static func describe(_ info: WindowInfo) -> String {
        "title=\"\(info.title)\" frameAX=\(info.frameAX) isMinimized=\(info.isMinimized) isFullScreen=\(info.isFullScreen)"
    }

    /// 候補点の番号（grabCandidates の 0 始まりの添字。幅 200 未満では (b)(d) の 2 点だけになる）。
    private static func describe(_ index: Int?) -> String {
        guard let index else { return "なし" }
        return "\(index)"
    }
}
