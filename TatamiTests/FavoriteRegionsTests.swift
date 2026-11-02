import Foundation
import Testing
@testable import Tatami

@MainActor
final class FavoriteRegionsTests {
    let suiteName = "dev.hidekingerz.tatamiTests.FavoriteRegions.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    @Test func 何もなければ空() {
        #expect(FavoriteRegions(defaults: defaults).regions.isEmpty)
    }

    @Test func toggleで追加と削除が保存され別インスタンスで読める() {
        let favorites = FavoriteRegions(defaults: defaults)
        favorites.toggle(.rightThird)
        favorites.toggle(.center)
        favorites.toggle(.rightThird)
        #expect(favorites.regions == [.center])
        #expect(favorites.contains(.center))
        #expect(!favorites.contains(.rightThird))
        #expect(FavoriteRegions(defaults: defaults).regions == [.center])
        #expect(defaults.stringArray(forKey: FavoriteRegions.key) == ["center"])
    }

    @Test func 未知の値は捨てる() {
        defaults.set(["center", "noSuchRegion", "leftHalf"], forKey: FavoriteRegions.key)
        #expect(FavoriteRegions(defaults: defaults).regions == [.center, .leftHalf])
    }
}
