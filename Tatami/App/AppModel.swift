// Tatami/App/AppModel.swift
import AppKit
import Observation

/// アプリ全体で 1 つだけ持つ依存の束。
///
/// 初期化ではエンジンを組み立てて権限変化の通知を購読するだけにし、
/// 権限要求、ショートカット登録、権限のポーリングといった外部への副作用は `start()` で行う。
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let permission = PermissionGate()
    @ObservationIgnored let engine: SnapEngine
    @ObservationIgnored let settings = CommandSettings()
    @ObservationIgnored private var poller: TrustPoller?

    /// メニュー表示用の権限状態。通知やポーリングのたびに `refreshTrust()` で読み直す。
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

        // アクセシビリティ権限が変わると TCC がこの分散通知を投げる。ただし通知が届いた時点では
        // TCC がまだ古い判定を返すことがあるため、未許可の間は start() のポーリングが本命。
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshTrust() }
        }
    }

    /// 権限要求とショートカット登録を行う。テストホストとして起動されたときは何もしない
    /// （`xcodebuild test` のたびに権限プロンプトが出たり、グローバルなホットキーを奪ったりしないように）。
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
        permission.requestAccess()
        ShortcutRegistrar.register(engine: engine, settings: settings)
        watchTrustUntilGranted()
    }

    /// 許可されるまで 1 秒おきに権限を読み直す。許可を検知したらメニュー表示を更新して止まる。
    private func watchTrustUntilGranted() {
        let poller = TrustPoller(permission: permission) { [weak self] in
            self?.poller = nil
            self?.refreshTrust()
        }
        self.poller = poller
        poller.start()
    }

    /// 権限状態を OS から読み直す。取り消されていたら、再び許可されるまでのポーリングを始める。
    func refreshTrust() {
        let trusted = permission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
        if !trusted, poller == nil {
            watchTrustUntilGranted()
        }
    }
}
