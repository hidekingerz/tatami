import CoreGraphics

/// 直前のスナップの記憶。ループ判定に使う。
struct CycleMemory: Equatable, Sendable {
    /// 操作したウィンドウ。
    let window: WindowHandle
    /// 適用した区画。
    let action: SnapAction
    /// 適用後に読み直した実枠（AX 座標）。
    let appliedFrame: CGRect
}
