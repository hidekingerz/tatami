import CoreGraphics
import os

/// スナップが成立しなかった理由。UI 側は beep とログに使う。
enum SnapFailure: Sendable {
    case notTrusted
    case noScreen
    case window(WindowServiceError)
    case unknown(any Error)
}

/// ショートカット 1 回分のスナップを実行する司令塔。
///
/// 権限確認 → ウィンドウ取得 → 画面特定 → 区画決定 → 枠計算 → 適用 → 記憶更新 の順に進む。
/// 座標は WindowService との境界で AX 座標、レイアウト計算は NS 座標。
@MainActor
final class SnapEngine {
    private let windowService: any WindowService
    private let screens: any ScreenProviding
    private let permission: any PermissionChecking
    private let placer: WindowPlacer
    private let onFailure: @MainActor (SnapFailure) -> Void
    private let logger = Logger(subsystem: "dev.hidekingerz.tatami", category: "SnapEngine")

    /// 直前のスナップの記憶。ループ判定に使う。
    private(set) var memory: CycleMemory?

    init(
        windowService: any WindowService,
        screens: any ScreenProviding,
        permission: any PermissionChecking,
        onFailure: @escaping @MainActor (SnapFailure) -> Void
    ) {
        self.windowService = windowService
        self.screens = screens
        self.permission = permission
        self.placer = WindowPlacer(windowService: windowService, screens: screens)
        self.onFailure = onFailure
    }

    func perform(_ command: SnapCommand) {
        guard permission.isTrusted else {
            permission.requestAccess()
            fail(.notTrusted)
            return
        }

        do {
            let window = try windowService.focusedWindow()
            let currentAX = try windowService.frame(of: window)
            let action = CycleResolver.resolve(
                command: command, memory: memory, window: window, currentFrame: currentAX
            )
            let appliedAX = try placer.place(window, action: action)

            memory = CycleMemory(window: window, action: action, appliedFrame: appliedAX)
            logger.debug(
                "\(String(describing: command), privacy: .public) -> \(String(describing: action), privacy: .public) applied=\(String(describing: appliedAX), privacy: .public)"
            )
        } catch PlacementError.noScreen {
            fail(.noScreen)
        } catch let error as WindowServiceError {
            fail(.window(error))
        } catch {
            fail(.unknown(error))
        }
    }

    /// 直前のスナップの記憶を捨てる。レイアウトセット適用後など、ループ判定を初期化したいときに使う。
    func clearMemory() {
        memory = nil
    }

    private func fail(_ failure: SnapFailure) {
        logger.error("snap failed: \(String(describing: failure), privacy: .public)")
        onFailure(failure)
    }
}
