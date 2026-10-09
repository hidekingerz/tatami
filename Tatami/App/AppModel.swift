// Tatami/App/AppModel.swift
import AppKit
import Observation

/// アプリ全体で 1 つだけ持つ依存の束。起動時に権限を要求し、ショートカットを登録する。
@MainActor
@Observable
final class AppModel {
    let permission = PermissionGate()
    let engine: SnapEngine

    init() {
        let permission = self.permission
        engine = SnapEngine(
            windowService: AccessibilityWindowService(),
            screens: NSScreenProvider(),
            permission: permission,
            onFailure: { _ in NSSound.beep() }
        )
        permission.requestAccess()
        ShortcutRegistrar.register(engine: engine)
    }
}
