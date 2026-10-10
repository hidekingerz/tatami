import CoreGraphics

/// ループ系コマンドで次に適用する区画を決める純粋ロジック。
///
/// 「同じウィンドウに、同じ系列の区画を、直前に適用し、その枠がまだ保たれている」
/// ときだけ系列の次へ進む。それ以外は系列の先頭から始める。
enum CycleResolver {
    static func resolve(
        command: SnapCommand,
        memory: CycleMemory?,
        window: WindowHandle,
        currentFrame: CGRect,
        tolerance: CGFloat = 2
    ) -> SnapAction {
        let sequence = command.sequence
        guard sequence.count > 1 else {
            return sequence[0]
        }

        guard let memory,
              memory.window == window,
              let index = sequence.firstIndex(of: memory.action),
              isClose(memory.appliedFrame, currentFrame, tolerance: tolerance)
        else {
            return sequence[0]
        }

        return sequence[(index + 1) % sequence.count]
    }

    /// 各辺の差がすべて tolerance 以内なら一致とみなす。
    private static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
