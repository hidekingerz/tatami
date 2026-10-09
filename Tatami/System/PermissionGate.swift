// Tatami/System/PermissionGate.swift
import AppKit
import ApplicationServices

/// Accessibility 権限の確認と、システム設定への誘導。
@MainActor
final class PermissionGate: PermissionChecking {
    /// 毎回 OS に問い合わせる。許可直後に再起動なしで動くようにするため。
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// システムのプロンプトを出して許可を求める。
    func requestAccess() {
        // kAXTrustedCheckOptionPrompt is a mutable global (not concurrency-safe in Swift 6); use its literal value.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く。
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
