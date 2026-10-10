@testable import Tatami

@MainActor
final class FakePermission: PermissionChecking {
    var isTrusted = true
    private(set) var requestAccessCount = 0

    func requestAccess() {
        requestAccessCount += 1
    }
}
