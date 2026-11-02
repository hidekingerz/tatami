// Tatami/Model/PickerItem.swift
import Foundation

/// ピッカーの 1 行。レイアウトセットか、区画 1 つ。
enum PickerItem: Hashable, Identifiable, Sendable {
    case set(LayoutSet)
    case region(SnapAction)

    var id: String {
        switch self {
        case .set(let set): "set:\(set.id.uuidString)"
        case .region(let action): "region:\(action.rawValue)"
        }
    }

    var setValue: LayoutSet? {
        if case .set(let set) = self { set } else { nil }
    }

    var region: SnapAction? {
        if case .region(let action) = self { action } else { nil }
    }
}

/// 見出し付きの行のまとまり。
struct PickerSection: Hashable, Sendable {
    let title: String
    let items: [PickerItem]
}
