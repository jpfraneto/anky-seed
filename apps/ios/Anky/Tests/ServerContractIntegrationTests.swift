import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

/// Runs only against a local backend:
///   ANKY_LOCAL_BACKEND=http://localhost:8080 swift test --filter ServerContractIntegrationTests
/// Exercises the real signed client against the real routes: the free-access
/// ledger never moves, and AI is refused (402) without a subscription.
final class ServerContractIntegrationTests: XCTestCase {
    private func client() throws -> AnkyServerClient {
        guard let raw = ProcessInfo.processInfo.environment["ANKY_LOCAL_BACKEND"],
              let url = URL(string: raw) else {
            throw XCTSkip("Set ANKY_LOCAL_BACKEND to run against a local backend.")
        }
        return AnkyServerClient(baseURL: url)
    }

    private func freshIdentity() throws -> WriterIdentity {
        try WriterIdentity(recoveryPhrase: RecoveryPhrase.generate())
    }

    func testFreeAccessLedgerStartsOnceAndNeverMoves() async throws {
        let client = try client()
        let identity = try freshIdentity()

        let before = try await client.accessStatus(start: false, identity: identity)
        XCTAssertNil(before.freeAccess.startedAtMs, "asking without start never opens the window")
        XCTAssertFalse(before.entitlement.entitled)

        let started = try await client.accessStatus(start: true, identity: identity)
        let startedAt = try XCTUnwrap(started.freeAccess.startedAtMs)
        XCTAssertEqual(started.freeAccess.endsAtMs, startedAt + 7 * 24 * 60 * 60 * 1000)
        XCTAssertTrue(started.freeAccess.active)

        try await Task.sleep(nanoseconds: 20_000_000)
        let again = try await client.accessStatus(start: true, identity: identity)
        XCTAssertEqual(again.freeAccess.startedAtMs, startedAt, "a second start never moves the first")

        // The app merges it: the earliest start wins.
        let merged = FreeAccessLedger.merge(local: nil, serverStartedAt: again.freeAccessStartedAt)
        XCTAssertEqual(merged?.confirmedByServer, true)
    }

    func testReflectionIsRefusedWithoutSubscription() async throws {
        let client = try client()
        let identity = try freshIdentity()
        let anky = ExpressionSessionTests.sampleAnky(word: "hello")
        do {
            _ = try await client.reflect(ankyBytes: Data(anky.utf8), identity: identity, appVersion: "2.3.0")
            XCTFail("a non-subscriber must not get a reflection")
        } catch let error as AnkyServerError {
            XCTAssertEqual(error, .entitlementRequired)
        }
    }

    func testLiveIsUnavailableWithoutConfiguration() async throws {
        let client = try client()
        let available = await client.liveAvailable()
        XCTAssertFalse(available)
        do {
            _ = try await client.startLive(sessionID: UUID(), audience: "link", identity: try freshIdentity())
            XCTFail("live must not start without configuration")
        } catch let error as AnkyServerError {
            XCTAssertEqual(error, .notConfigured)
        }
    }
}
