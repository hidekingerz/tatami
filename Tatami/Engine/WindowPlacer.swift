import CoreGraphics

/// 区画の適用に失敗した理由。WindowService 由来のエラーはそのまま伝播する。
enum PlacementError: Error, Equatable, Sendable {
    case noScreen
}

/// 窓 1 枚に SnapAction を適用する。SnapEngine と LayoutSetRunner で共有する。
///
/// 現在枠の読み取り → 画面特定 → 枠計算 → 適用 → 読み直し → はみ出し補正、の順に進む。
/// 座標は WindowService との境界で AX 座標、レイアウト計算は NS 座標。
@MainActor
struct WindowPlacer {
    private let windowService: any WindowService
    private let screens: any ScreenProviding

    init(windowService: any WindowService, screens: any ScreenProviding) {
        self.windowService = windowService
        self.screens = screens
    }

    /// 窓がいまある画面（なければ mainScreen）で action の枠を計算して適用し、はみ出しを補正する。適用後の AX 枠を返す。
    @discardableResult
    func place(_ window: WindowHandle, action: SnapAction) throws -> CGRect {
        let currentAX = try windowService.frame(of: window)
        let primaryHeight = screens.primaryHeight
        let currentNS = CoordinateConverter.toScreen(currentAX, primaryHeight: primaryHeight)

        guard let region = ScreenLocator.region(containing: currentNS, in: screens.screens)
                ?? screens.mainScreen
        else {
            throw PlacementError.noScreen
        }

        let targetNS = LayoutCalculator.frame(for: action, in: region.visibleFrame, current: currentNS)
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
        return appliedAX
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
}
