// Tatami/System/NSScreenProvider.swift
import AppKit

/// NSScreen から ScreenProviding を組み立てる。
struct NSScreenProvider: ScreenProviding {
    /// プライマリ画面は `NSScreen.screens[0]`。`NSScreen.main` はキーウィンドウのある画面なので使わない。
    var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    var screens: [ScreenRegion] {
        NSScreen.screens.map { ScreenRegion(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    var mainScreen: ScreenRegion? {
        NSScreen.main.map { ScreenRegion(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}
