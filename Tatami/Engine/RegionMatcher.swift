import CoreGraphics

/// 窓の枠を、いちばん近い区画（SnapAction）に丸める純粋関数。
enum RegionMatcher {
    /// サイズ系 3 つ（maximizeHeight / maximizeWidth / center）を除いた 24 区画。
    static let candidates: [SnapAction] = SnapAction.allCases.filter {
        ![.maximizeHeight, .maximizeWidth, .center].contains($0)
    }

    /// 2 つの矩形の IoU（共通部分の面積 / 和集合の面積）。重ならなければ 0。
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    /// frameNS（NS 座標）に最も近い区画。IoU が threshold 未満なら nil。
    static func closestAction(to frameNS: CGRect, in visible: CGRect, threshold: CGFloat = 0.9) -> SnapAction? {
        var best: (action: SnapAction, iou: CGFloat)?
        for action in candidates {
            let region = LayoutCalculator.frame(for: action, in: visible, current: frameNS)
            let iou = intersectionOverUnion(frameNS, region)
            if iou > (best?.iou ?? -1) { best = (action, iou) }
        }
        guard let best, best.iou >= threshold else { return nil }
        return best.action
    }
}
