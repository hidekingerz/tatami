import Foundation

/// 行を計画から外した理由。
enum SkipReason: Equatable, Sendable {
    case appNotRunning
    case noMatchingWindow
    case fullScreen
}

/// 行と照合できた窓の組。
struct PlannedStep: Equatable, Sendable {
    let row: LayoutRow
    let window: WindowInfo
}

/// 窓に当たらなかった行とその理由。
struct SkippedRow: Equatable, Sendable {
    let row: LayoutRow
    let reason: SkipReason
}

struct LayoutPlan: Equatable, Sendable {
    let steps: [PlannedStep]
    let skipped: [SkippedRow]
}

enum LayoutSetPlanner {
    /// 行の順に照合する。何もしない行は無視。使った窓とフルスクリーンの窓は候補から外す。
    /// windowsByBundle にキーがない = 起動していない、[] = 起動しているが窓がない。
    static func plan(_ set: LayoutSet, windowsByBundle: [String: [WindowInfo]]) -> LayoutPlan {
        var steps: [PlannedStep] = []
        var skipped: [SkippedRow] = []
        var used = Set<WindowHandle>()

        for row in set.rows where !row.isNoOp {
            guard let windows = windowsByBundle[row.bundleIdentifier] else {
                skipped.append(SkippedRow(row: row, reason: .appNotRunning))
                continue
            }
            // 絞り込みに合う未使用の窓。タイトルの絞り込みが空なら全部合う。
            let candidates = windows.filter { window in
                !used.contains(window.handle)
                    && (row.titleFilter.isEmpty || window.title.localizedCaseInsensitiveContains(row.titleFilter))
            }
            if let window = candidates.first(where: { !$0.isFullScreen }) {
                used.insert(window.handle)
                steps.append(PlannedStep(row: row, window: window))
            } else {
                // 合う窓がすべてフルスクリーンなら fullScreen、1 つもなければ noMatchingWindow。
                skipped.append(SkippedRow(row: row, reason: candidates.isEmpty ? .noMatchingWindow : .fullScreen))
            }
        }
        return LayoutPlan(steps: steps, skipped: skipped)
    }
}
