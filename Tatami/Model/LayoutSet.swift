import Foundation

/// レイアウトセットの 1 行。アプリ（とタイトル絞り込み）に対して、区画とデスクトップを指定する。
struct LayoutRow: Identifiable, Codable, Hashable, Sendable {
    /// 指定できるデスクトップ番号。
    static let desktopRange = 1...10

    let id: UUID
    var bundleIdentifier: String
    var appName: String
    /// 空なら絞り込まない。
    var titleFilter: String
    /// nil なら区画を変えない。
    var action: SnapAction?
    /// nil ならデスクトップを動かさない。
    var desktop: Int?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        titleFilter: String = "",
        action: SnapAction? = nil,
        desktop: Int? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.titleFilter = titleFilter
        self.action = action
        self.desktop = desktop
    }

    /// action も desktop もない「何もしない行」。
    var isNoOp: Bool { action == nil && desktop == nil }

    private enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, appName, titleFilter, action, desktop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        appName = try c.decode(String.self, forKey: .appName)
        titleFilter = try c.decode(String.self, forKey: .titleFilter)
        // 未知の区画名（将来の版で追加されたもの）で、セット全体を読めなくしない。
        action = try c.decodeIfPresent(String.self, forKey: .action).flatMap(SnapAction.init(rawValue:))
        // 範囲外のデスクトップ番号は「動かさない」に丸める。
        desktop = try c.decodeIfPresent(Int.self, forKey: .desktop).flatMap {
            Self.desktopRange.contains($0) ? $0 : nil
        }
    }
}

/// 名前を付けたレイアウトの組。
struct LayoutSet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rows: [LayoutRow]

    init(id: UUID = UUID(), name: String, rows: [LayoutRow] = []) {
        self.id = id
        self.name = name
        self.rows = rows
    }
}
