// Tatami/System/PermissionGate.swift
import AppKit
import ApplicationServices

/// Accessibility 権限の確認と、システム設定への誘導。
@MainActor
final class PermissionGate: PermissionChecking {
    /// 許可されているか。
    ///
    /// `AXIsProcessTrusted()` はプロセス内で結果をキャッシュし、権限変更の通知が届いた時点で読み直す。
    /// ところがシステム設定で許可した瞬間は TCC がまだ「拒否」を返すことがあり、その値がキャッシュに
    /// 残ると再起動まで false のままになる（実機で確認済み）。そこで、キャッシュが false のときは
    /// 実際に AX API を呼んでみて、通れば許可済みとみなす。
    var isTrusted: Bool {
        AXIsProcessTrusted() || canReachAccessibilityAPI()
    }

    /// Dock への AX 問い合わせが通るか。権限がなければ `.apiDisabled` で失敗する。
    ///
    /// 対象を Dock にするのは、常に動いていて前面アプリに左右されないため。システム全体要素の
    /// 「フォーカス中アプリ」は Chromium 系アプリが前面だと断続的に `.noValue` を返して使えない。
    /// 自プロセスへの問い合わせは権限がなくても通るので判定に使えない（いずれも実機で確認済み）。
    private func canReachAccessibilityAPI() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(dock.processIdentifier), kAXRoleAttribute as CFString, &value
        )
        return error == .success
    }

    /// システムのプロンプトを出して許可を求める。
    func requestAccess() {
        // kAXTrustedCheckOptionPrompt は可変なグローバル変数で Swift 6 では並行安全でないため、その文字列値を直接使う。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く。
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
