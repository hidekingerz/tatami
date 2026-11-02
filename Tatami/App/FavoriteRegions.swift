// Tatami/App/FavoriteRegions.swift
import Foundation
import Observation

/// ピッカーでお気に入り（★）にした領域。UserDefaults に `picker.favoriteRegions` で保存する。
///
/// 保存は `SnapAction.rawValue` の文字列配列（ソート済み）。読み込み時に未知の値は捨てる。
@MainActor
@Observable
final class FavoriteRegions {
    static let key = "picker.favoriteRegions"

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var regions: Set<SnapAction>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: Self.key) ?? []
        regions = Set(raw.compactMap(SnapAction.init(rawValue:)))
    }

    func contains(_ action: SnapAction) -> Bool {
        regions.contains(action)
    }

    func toggle(_ action: SnapAction) {
        if regions.contains(action) {
            regions.remove(action)
        } else {
            regions.insert(action)
        }
        defaults.set(regions.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
