import Foundation
import Testing
@testable import Tatami

@MainActor
final class LayoutSetStoreTests {
    let suiteName = "dev.hidekingerz.tatamiTests.LayoutSetStore.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    func row(_ app: String) -> LayoutRow {
        LayoutRow(bundleIdentifier: "com.example.\(app)", appName: app, action: .maximize)
    }

    @Test func 何もなければ空() {
        #expect(LayoutSetStore(defaults: defaults).sets.isEmpty)
    }

    @Test func 追加と更新と削除が保存され別インスタンスで読める() {
        let store = LayoutSetStore(defaults: defaults)
        var set = LayoutSet(name: "作業", rows: [row("a")])
        store.add(set)
        set.name = "作業2"
        set.rows.append(row("b"))
        store.update(set)
        store.add(LayoutSet(name: "連絡"))
        #expect(LayoutSetStore(defaults: defaults).sets == store.sets)
        #expect(store.sets.map(\.name) == ["作業2", "連絡"])
        #expect(store.set(id: set.id)?.rows.count == 2)

        store.remove(id: set.id)
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["連絡"])
    }

    @Test func 並び替えが保存される() {
        let store = LayoutSetStore(defaults: defaults)
        store.add(LayoutSet(name: "a"))
        store.add(LayoutSet(name: "b"))
        store.add(LayoutSet(name: "c"))
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["c", "a", "b"])
    }

    @Test func 壊れたJSONは退避して空で起動する() {
        defaults.set(Data("not json".utf8), forKey: LayoutSetStore.key)
        let store = LayoutSetStore(defaults: defaults)
        #expect(store.sets.isEmpty)
        #expect(defaults.data(forKey: LayoutSetStore.corruptKey) == Data("not json".utf8))
        store.add(LayoutSet(name: "new"))
        #expect(defaults.data(forKey: LayoutSetStore.corruptKey) == Data("not json".utf8))
        #expect(LayoutSetStore(defaults: defaults).sets.map(\.name) == ["new"])
    }

    @Test func 変更のたびにonChangeが呼ばれる() {
        let store = LayoutSetStore(defaults: defaults)
        var counts: [Int] = []
        store.onChange = { counts.append($0.count) }
        let set = LayoutSet(name: "a")
        store.add(set)
        store.update(set)
        store.remove(id: set.id)
        #expect(counts == [1, 1, 0])
    }
}
