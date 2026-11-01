// Tatami/App/LayoutSetStore.swift
import Foundation
import Observation
import OSLog
import SwiftUI

/// レイアウトセットの保存先。`[LayoutSet]` を JSON にして UserDefaults に置く。
///
/// 読み込めない JSON は `corruptKey` にそのまま退避し、空で起動する。
/// 退避したデータは後続の保存では上書きしない。
@MainActor
@Observable
final class LayoutSetStore {
    static let key = "layoutSets.v1"
    static let corruptKey = "layoutSets.v1.corrupt"

    private static let logger = Logger(subsystem: "dev.hidekingerz.tatami", category: "LayoutSetStore")

    @ObservationIgnored private let defaults: UserDefaults

    /// 変更のたびに保存したあとで呼ばれる。ShortcutRegistrar がホットキーの再登録に使う。
    @ObservationIgnored var onChange: (([LayoutSet]) -> Void)?

    private(set) var sets: [LayoutSet]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                sets = try JSONDecoder().decode([LayoutSet].self, from: data)
            } catch {
                // 壊れたデータは消さずに退避する。corruptKey は上書きしない。
                if defaults.data(forKey: Self.corruptKey) == nil {
                    defaults.set(data, forKey: Self.corruptKey)
                }
                Self.logger.error("レイアウトセットの読み込みに失敗: \(error.localizedDescription, privacy: .public)")
                sets = []
            }
        } else {
            sets = []
        }
    }

    func set(id: UUID) -> LayoutSet? {
        sets.first { $0.id == id }
    }

    func add(_ set: LayoutSet) {
        sets.append(set)
        commit()
    }

    /// id が一致する要素を置き換える。なければ何もしない。
    func update(_ set: LayoutSet) {
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        sets[index] = set
        commit()
    }

    func remove(id: UUID) {
        sets.removeAll { $0.id == id }
        commit()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        sets.move(fromOffsets: fromOffsets, toOffset: toOffset)
        commit()
    }

    private func commit() {
        save()
        onChange?(sets)
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(sets), forKey: Self.key)
        } catch {
            Self.logger.error("レイアウトセットの保存に失敗: \(error.localizedDescription, privacy: .public)")
        }
    }
}
