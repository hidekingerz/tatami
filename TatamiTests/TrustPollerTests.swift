import Testing
@testable import Tatami

@MainActor
struct TrustPollerTests {
    /// 未許可 → 許可 に変わったら onTrusted が 1 回呼ばれ、ポーリングが止まること。
    @Test func 許可を検知したら一度だけ通知して止まる() async throws {
        let permission = FakePermission()
        permission.isTrusted = false
        var fired = 0
        let poller = TrustPoller(permission: permission, interval: .milliseconds(5)) { fired += 1 }

        poller.start()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fired == 0)
        #expect(poller.isPolling)

        permission.isTrusted = true
        try await Task.sleep(for: .milliseconds(60))
        #expect(fired == 1)
        #expect(!poller.isPolling)

        // 止まった後は値が変わっても呼ばれない。
        permission.isTrusted = false
        permission.isTrusted = true
        try await Task.sleep(for: .milliseconds(30))
        #expect(fired == 1)
    }

    /// 最初から許可済みなら即座に通知して、ポーリングを始めない。
    @Test func 最初から許可済みなら即座に通知する() async throws {
        let permission = FakePermission()
        var fired = 0
        let poller = TrustPoller(permission: permission, interval: .milliseconds(5)) { fired += 1 }

        poller.start()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fired == 1)
        #expect(!poller.isPolling)
    }

    /// stop() で止めたら通知されない。
    @Test func stopで止めたら通知しない() async throws {
        let permission = FakePermission()
        permission.isTrusted = false
        var fired = 0
        let poller = TrustPoller(permission: permission, interval: .milliseconds(5)) { fired += 1 }

        poller.start()
        poller.stop()
        permission.isTrusted = true
        try await Task.sleep(for: .milliseconds(30))
        #expect(fired == 0)
        #expect(!poller.isPolling)
    }
}
