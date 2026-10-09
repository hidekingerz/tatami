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
            let primaryHeight = screens.primaryHeight
            let currentNS = CoordinateConverter.toScreen(currentAX, primaryHeight: primaryHeight)

            guard let region = ScreenLocator.region(containing: currentNS, in: screens.screens)
                    ?? screens.mainScreen
            else {
                fail(.noScreen)
                return
            }

            let action = CycleResolver.resolve(
                command: command, memory: memory, window: window, currentFrame: currentAX
            )
            let targetNS = LayoutCalculator.frame(for: action, in: region.visibleFrame)
            let targetAX = CoordinateConverter.toAccessibility(targetNS, primaryHeight: primaryHeight)

            try windowService.setFrame(targetAX, of: window)
            var appliedAX = try windowService.frame(of: window)

            // 最小サイズ制約で目標より大きくなると、右端・下端に寄せた区画では画面外へはみ出す。
            // そのときは実際の大きさのまま位置だけ visibleFrame の内側へ戻し、もう一度読み直す。
            let visibleAX = CoordinateConverter.toAccessibility(region.visibleFrame, primaryHeight: primaryHeight)
            let correctedOrigin = Self.originKeptInside(appliedAX, visible: visibleAX)
            if correctedOrigin != appliedAX.origin {
                try windowService.setFrame(CGRect(origin: correctedOrigin, size: appliedAX.size), of: window)
                appliedAX = try windowService.frame(of: window)
            }

            memory = CycleMemory(window: window, action: action, appliedFrame: appliedAX)
            logger.debug("\(String(describing: action)) -> \(String(describing: appliedAX))")
        } catch let error as WindowServiceError {
            fail(.window(error))
        } catch {
            fail(.unknown(error))
        }
    }

    /// frame が visible の右端・下端からはみ出していれば内側へ寄せた原点を返す。
    /// 寄せた結果が左端・上端を越える場合は左端・上端を優先する。
    private static func originKeptInside(_ frame: CGRect, visible: CGRect) -> CGPoint {
        var origin = frame.origin
        if frame.maxX > visible.maxX {
            origin.x = visible.maxX - frame.width
        }
        if frame.maxY > visible.maxY {
            origin.y = visible.maxY - frame.height
        }
        origin.x = max(origin.x, visible.minX)
        origin.y = max(origin.y, visible.minY)
        return origin
    }

    private func fail(_ failure: SnapFailure) {
        logger.error("snap failed: \(String(describing: failure))")
        onFailure(failure)
    }
}
