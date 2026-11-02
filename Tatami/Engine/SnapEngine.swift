import CoreGraphics
import os

/// スナップが成立しなかった理由。UI 側は beep とログに使う。
enum SnapFailure: Sendable, Equatable {
    case notTrusted
    case noScreen
    case window(WindowServiceError)
    case noTargetWindow
    case unknown(any Error)

    /// `unknown` は比べようがないので常に false。
    static func == (lhs: SnapFailure, rhs: SnapFailure) -> Bool {
        switch (lhs, rhs) {
        case (.notTrusted, .notTrusted), (.noScreen, .noScreen), (.noTargetWindow, .noTargetWindow):
            true
        case let (.window(a), .window(b)):
            a == b
        default:
            false
        }
    }
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

    /// ピッカーを開く前の最前面ウィンドウ。区画適用の対象になる。
    private(set) var rememberedWindow: WindowHandle?

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

    /// 現在のフォーカスウィンドウを対象として記憶する。取れなければ nil。
    func rememberFocusedWindow() {
        do {
            rememberedWindow = try windowService.focusedWindow()
        } catch {
            rememberedWindow = nil
            logger.error("remember failed: \(String(describing: error), privacy: .public)")
        }
    }

    func forgetRememberedWindow() {
        rememberedWindow = nil
    }

    /// 記憶したウィンドウに区画を適用する。成功は nil。結果にかかわらず記憶は消える。
    @discardableResult
    func applyToRememberedWindow(_ action: SnapAction) -> SnapFailure? {
        guard permission.isTrusted else {
            permission.requestAccess()
            fail(.notTrusted)
            rememberedWindow = nil
            return .notTrusted
        }
        guard let window = rememberedWindow else {
            fail(.noTargetWindow)
            return .noTargetWindow
        }
        defer { rememberedWindow = nil }

        do {
            let applied = try placer.place(window, action: action)
            memory = CycleMemory(window: window, action: action, appliedFrame: applied)
            return nil
        } catch PlacementError.noScreen {
            fail(.noScreen)
            return .noScreen
        } catch let error as WindowServiceError {
            fail(.window(error))
            return .window(error)
        } catch {
            fail(.unknown(error))
            return .unknown(error)
        }
    }

    private func fail(_ failure: SnapFailure) {
        logger.error("snap failed: \(String(describing: failure), privacy: .public)")
        onFailure(failure)
    }
}
