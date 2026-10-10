// Tatami/System/TrustPoller.swift
import Foundation

/// 未許可の間だけ一定間隔で Accessibility 権限を読み直し、許可を検知したら 1 回だけ通知して止まる。
///
/// TCC の分散通知やアクティブ化通知は Dock 非表示のメニューバーアプリでは当てにならないため、
/// 許可待ちの間はポーリングで追いかける（Rectangle など既存ツールと同じ方式）。
@MainActor
final class TrustPoller {
    private let permission: any PermissionChecking
    private let interval: Duration
    private let onTrusted: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(permission: any PermissionChecking, interval: Duration = .seconds(1), onTrusted: @escaping @MainActor () -> Void) {
        self.permission = permission
        self.interval = interval
        self.onTrusted = onTrusted
    }

    var isPolling: Bool { task != nil }

    /// 既に許可済みなら即座に通知して終わる。未許可なら許可されるまで読み直し続ける。
    func start() {
        guard task == nil else { return }
        if permission.isTrusted {
            onTrusted()
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if permission.isTrusted {
                    task = nil
                    onTrusted()
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
