// Tatami/Model/PickerTab.swift
import Foundation

/// ピッカーのタブ。セットと区画を別々の一覧で扱う。
enum PickerTab: String, CaseIterable, Identifiable, Sendable {
    case sets
    case regions

    /// 最後に開いていたタブを覚えておくキー。
    static let defaultsKey = "picker.tab"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sets: "セット"
        case .regions: "区画"
        }
    }

    /// ⇥ で切り替える先。
    var other: PickerTab {
        switch self {
        case .sets: .regions
        case .regions: .sets
        }
    }

    /// 保存された文字列からタブを決める。未設定や不正な値はセット。
    static func resolve(_ rawValue: String?) -> PickerTab {
        PickerTab(rawValue: rawValue ?? "") ?? .sets
    }
}
