import XCTest
@testable import Anky

/// The privacy reorder (outwards pivot §4.1): nothing leaves the device at
/// the sentinel. `prepare(for:)` stands the reflection view model up in
/// memory; the upload fires only in `beginUpload()`, which the Anchor calls
/// after the three-second vigil completes.
@MainActor
final class GeshtuPrivacySeamTests: XCTestCase {
    private func sealedFixtureSession() throws -> SavedAnky {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-seam-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = LocalAnkyArchive(directoryURL: directory)
        var writer = AnkyWriter()
        var cursor: Int64 = 1_784_000_000_000
        for character in "the words stay home until the hold" {
            _ = writer.accept(character, at: cursor)
            cursor += 120
        }
        writer.closeWithTerminalSilence()
        return try archive.save(writer.text)
    }

    func testPrepareStartsNoRequest() throws {
        let session = try sealedFixtureSession()
        let coordinator = GeshtuReflectionCoordinator()

        coordinator.prepare(for: session)

        let vm = try XCTUnwrap(coordinator.viewModel)
        // No network work may have started: the view model is idle, nothing
        // is in flight, and no progress stage has been entered.
        XCTAssertFalse(vm.isAskingAnky, "prepare(for:) must not begin the upload")
        XCTAssertNil(vm.reflection)
        XCTAssertEqual(vm.streamingReflectionMarkdown, "")
        XCTAssertNil(vm.reflectionSurface, "full sessions must use the Markdown reflection prompt")
        XCTAssertEqual(coordinator.channelState, .incomplete)
    }

    func testPrepareIsIdempotentPerHash() throws {
        let session = try sealedFixtureSession()
        let coordinator = GeshtuReflectionCoordinator()

        coordinator.prepare(for: session)
        let first = coordinator.viewModel
        coordinator.prepare(for: session)

        XCTAssertTrue(first === coordinator.viewModel, "same hash must keep the same view model")
    }

    func testDiscardDropsThePreparedModel() throws {
        let session = try sealedFixtureSession()
        let coordinator = GeshtuReflectionCoordinator()

        coordinator.prepare(for: session)
        coordinator.discard()

        XCTAssertNil(coordinator.viewModel)
        XCTAssertEqual(coordinator.channelState, .none)
    }

    func testBeginUploadWithoutPreparationIsANoOp() {
        let coordinator = GeshtuReflectionCoordinator()
        // Must not crash and must not create a view model from nothing.
        coordinator.beginUpload()
        XCTAssertNil(coordinator.viewModel)
    }

    func testDiscardDoesNotCancelAnExplicitlySentReflection() throws {
        let session = try sealedFixtureSession()
        var requestTask: Task<Void, Never>?
        let coordinator = GeshtuReflectionCoordinator { _ in
            let task = Task {
                _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            requestTask = task
            return task
        }

        coordinator.prepare(for: session)
        let vm = try XCTUnwrap(coordinator.viewModel)
        XCTAssertFalse(vm.persistsReflection)

        coordinator.beginUpload()
        XCTAssertTrue(vm.persistsReflection, "the explicit ask commits the eventual result")
        XCTAssertEqual(coordinator.channelState, .listening)
        coordinator.discard()

        XCTAssertNil(coordinator.viewModel)
        XCTAssertFalse(try XCTUnwrap(requestTask).isCancelled)
        requestTask?.cancel()
    }

    /// The state machine alone never sends: the request begins only where
    /// the world pairs the phase change with an explicit `beginUpload`.
    func testOpeningReflectionDocumentDoesNotSendTheOffering() throws {
        let session = try sealedFixtureSession()
        let axis = GeshtuState()

        axis.channelDidClose(session: session)
        axis.openReflectionChannel()

        XCTAssertEqual(axis.phase, .reflection)
        XCTAssertEqual(axis.pendingSession?.hash, session.hash)
    }
}
