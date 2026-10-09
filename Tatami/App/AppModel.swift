// Tatami/App/AppModel.swift
import AppKit
import Observation

/// アプリ全体で 1 つだけ持つ依存の束。
///
/// 初期化ではエンジンを組み立てて権限変化の通知を購読するだけにし、
/// 権限要求やショートカット登録といった外部への副作用は `start()` で行う。
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let permission = PermissionGate()
    @ObservationIgnored let engine: SnapEngine

    /// メニュー表示用の権限状態。通知やメニュー表示のたびに `refreshTrust()` で読み直す。
    /// スナップ時の判定は SnapEngine が毎回 OS に問い合わせるので、この値には依存しない。
    private(set) var isTrusted: Bool

    init() {
        let permission = self.permission
        engine = SnapEngine(
            windowService: AccessibilityWindowService(),
            screens: NSScreenProvider(),
            permission: permission,
            onFailure: { _ in NSSound.beep() }
        )
        isTrusted = permission.isTrusted

        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refreshTrust() }
        }
        // アクセシビリティ権限が変わると TCC がこの分散通知を投げる。
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main, using: refresh
        )
        // システム設定から戻ってきたときなど、取りこぼしても最前面化で追いつく。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: refresh
        )
    }

    /// 権限要求とショートカット登録を行う。テストホストとして起動されたときは何もしない
    /// （`xcodebuild test` のたびに権限プロンプトが出たり、グローバルなホットキーを奪ったりしないように）。
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
        permission.requestAccess()
        ShortcutRegistrar.register(engine: engine)
    }

    /// 権限状態を OS から読み直す。
    func refreshTrust() {
        let trusted = permission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }
}
