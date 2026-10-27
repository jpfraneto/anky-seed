//
//  ExpressionController.swift
//  Anky
//
//  One session, many ways to express. This owns the open session, the
//  recorders, and the moves between mediums. It never decides access on its
//  own: every start asks AccessController, and nothing in progress is ever
//  stopped by a policy answer.
//
//  Writing keeps its own engine (WriteViewModel): this controller only
//  learns when a passage is sealed and adds it to the session by hash. The
//  writing engine's eight-second rule ends a *passage*, never the session —
//  only the person ends the session.
//

import Foundation
import SwiftUI

@MainActor
final class ExpressionController: ObservableObject {
    enum Medium: Equatable {
        /// In the session, capturing nothing (between mediums, or recovered).
        case rest
        case write
        case voice
        case video
        /// Chosen silence: recorded as a segment of its own.
        case silence
    }

    @Published private(set) var session: ExpressionSession?
    @Published private(set) var medium: Medium = .rest
    /// The session was found open at launch (the app had stopped).
    @Published private(set) var recoveredOnLaunch = false
    /// A finished session to show as a memory.
    @Published var memoryToShow: ExpressionSession?
    /// Why the last attempt to start something was refused, for the surface
    /// that explains it.
    @Published var refusal: AccessDenial?
    @Published private(set) var saveError: String?

    let voice = VoiceRecorder()
    let camera = CameraRecorder()
    let store = ExpressionSessionStore()
    let access = AccessController.shared

    /// The world view connects these to the writing engine.
    var enterWriting: () -> Void = {}
    var leaveWriting: () -> Void = {}

    init() {
        camera.onRecordingEndedUnexpectedly = { [weak self] fileName, durationMs in
            self?.closeOpenSegment(kind: .video, durationMs: durationMs, mediaFile: "\(ExpressionSessionStore.mediaFolder)/\(fileName)")
        }
    }

    var isActive: Bool { session?.isActive == true }

    var isCapturing: Bool { voice.isCapturing || camera.isRecording }

    // MARK: Launch

    func restoreOnLaunch(writingInProgress: Bool) {
        guard session == nil, var open = store.activeSession() else { return }
        let sessionID = open.id
        let had = open.openSegment != nil
        ExpressionSessionLifecycle.recover(&open, now: access.now) { [store] segment in
            store.lastWriteDate(of: segment, sessionID: sessionID)
        }
        if had { persist(open) }
        session = open
        recoveredOnLaunch = true
        medium = writingInProgress ? .write : .rest
    }

    // MARK: Beginning

    /// Starts a session and opens the chosen medium. Returns false (and sets
    /// `refusal`) when access does not allow a new session.
    @discardableResult
    func begin(setting: SessionSetting?, medium first: Medium) async -> Bool {
        guard !isActive else {
            await switchTo(first)
            return true
        }
        let decision = access.decide(.startSession)
        guard decision.isAllowed else {
            if case .denied(let reason) = decision { refusal = reason }
            return false
        }
        access.beginFreeAccessIfNeeded()
        refusal = nil
        let new = ExpressionSession(startedAt: access.now, setting: setting)
        session = new
        recoveredOnLaunch = false
        persist(new)
        await switchTo(first)
        return true
    }

    // MARK: Switching

    /// Moves to another medium. Whatever was being captured is stopped and
    /// saved first; nothing is discarded.
    func switchTo(_ next: Medium) async {
        guard let current = session, current.isActive else { return }
        if next == medium, next != .rest { return }
        if next != .rest {
            let decision = access.decide(.newSegment(sessionStartedAt: current.startedAt))
            guard decision.isAllowed else {
                if case .denied(let reason) = decision { refusal = reason }
                return
            }
        }
        await leaveCurrentMedium()
        refusal = nil
        medium = next
        switch next {
        case .write:
            enterWriting()
        case .silence:
            openSegment(ExpressionSegment(kind: .silence, startedAt: access.now))
        case .video:
            await camera.startPreview()
        case .voice, .rest:
            break
        }
    }

    private func leaveCurrentMedium() async {
        switch medium {
        case .write:
            leaveWriting()
        case .voice:
            await stopVoice()
        case .video:
            await stopVideo()
            camera.stopPreview()
        case .silence:
            closeOpenSegment(kind: .silence)
        case .rest:
            break
        }
    }

    // MARK: Voice

    func startVoice() async {
        guard let current = session, current.isActive, !voice.isCapturing else { return }
        let decision = access.decide(.newSegment(sessionStartedAt: current.startedAt))
        guard decision.isAllowed else {
            if case .denied(let reason) = decision { refusal = reason }
            return
        }
        guard let folder = try? store.mediaFolderURL(for: current.id) else { return }
        let startedAt = access.now
        guard let fileName = await voice.start(in: folder, freeBytes: store.availableCapacityBytes()) else { return }
        openSegment(ExpressionSegment(
            kind: .voice,
            startedAt: startedAt,
            mediaFile: "\(ExpressionSessionStore.mediaFolder)/\(fileName)"
        ))
    }

    func stopVoice() async {
        guard voice.isCapturing else { return }
        let result = await voice.stop()
        closeOpenSegment(
            kind: .voice,
            durationMs: result?.durationMs,
            mediaFile: result.map { "\(ExpressionSessionStore.mediaFolder)/\($0.fileName)" }
        )
    }

    // MARK: Video

    func startVideo() {
        guard let current = session, current.isActive, !camera.isRecording else { return }
        let decision = access.decide(.newSegment(sessionStartedAt: current.startedAt))
        guard decision.isAllowed else {
            if case .denied(let reason) = decision { refusal = reason }
            return
        }
        guard let folder = try? store.mediaFolderURL(for: current.id) else { return }
        let startedAt = access.now
        guard let fileName = camera.startRecording(in: folder, freeBytes: store.availableCapacityBytes()) else { return }
        openSegment(ExpressionSegment(
            kind: .video,
            startedAt: startedAt,
            mediaFile: "\(ExpressionSessionStore.mediaFolder)/\(fileName)"
        ))
    }

    func stopVideo() async {
        guard camera.isRecording else { return }
        let result = await camera.stopRecording()
        closeOpenSegment(
            kind: .video,
            status: result == nil ? .failed : .complete,
            durationMs: result?.durationMs,
            mediaFile: result.map { "\(ExpressionSessionStore.mediaFolder)/\($0.fileName)" }
        )
    }

    // MARK: Writing

    /// A passage was sealed by the writing engine.
    func recordWriting(_ artifact: SavedAnky, replacing replacedHash: String?) {
        guard var current = session, current.isActive else { return }
        ExpressionSessionLifecycle.recordWriting(
            hash: artifact.hash,
            replacing: replacedHash,
            startedAt: artifact.createdAt,
            durationMs: artifact.durationMs,
            in: &current,
            now: access.now
        )
        persist(current)
        session = current
    }

    /// May a finished passage on the page be reopened to keep writing?
    func canContinueWriting() -> Bool {
        let action: AccessAction = session.map { .newSegment(sessionStartedAt: $0.startedAt) } ?? .continueWriting
        let decision = access.decide(action)
        if case .denied(let reason) = decision {
            refusal = reason
            return false
        }
        if session == nil { access.beginFreeAccessIfNeeded() }
        return true
    }

    /// A writing in the open session was deleted from the page.
    func forgetWriting(hash: String) {
        guard var current = session else { return }
        current.segments.removeAll { $0.ankyHash == hash }
        persist(current)
        session = current
    }

    // MARK: Ending

    /// Ends the session: stops and saves anything in progress, closes the
    /// manifest, and offers the memory. Always allowed, in every access state.
    func end() async {
        guard var current = session, current.isActive else { return }
        await leaveCurrentMedium()
        // Re-read: sealing a writing may have just added a segment.
        current = session ?? current
        ExpressionSessionLifecycle.end(&current, now: access.now)
        persist(current)
        session = nil
        medium = .rest
        recoveredOnLaunch = false
        refusal = nil
        memoryToShow = current.segments.isEmpty ? nil : current
        if current.segments.isEmpty {
            // Nothing was expressed: keep no empty folder.
            try? store.delete(id: current.id)
        }
    }

    /// The background is not a reason to stop a walk: voice keeps recording
    /// (audio background mode). Video cannot record in the background; the
    /// system interrupts it and the segment closes on its own.
    func persistOnBackground() {
        if let session { persist(session) }
    }

    // MARK: Deleting a past session

    func delete(_ past: ExpressionSession, archive: LocalAnkyArchive = LocalAnkyArchive()) {
        for hash in past.writingHashes {
            if let artifact = try? archive.load(hash: hash) {
                try? archive.delete(artifact)
            }
            try? ReflectionStore().delete(hash: hash)
            try? SessionIndexStore().delete(hash: hash)
        }
        try? store.delete(id: past.id)
        if memoryToShow?.id == past.id { memoryToShow = nil }
    }

    // MARK: Internals

    private func openSegment(_ segment: ExpressionSegment) {
        guard var current = session else { return }
        ExpressionSessionLifecycle.open(segment, in: &current, now: segment.startedAt)
        persist(current)
        session = current
    }

    private func closeOpenSegment(
        kind: ExpressionKind,
        status: ExpressionSegment.Status = .complete,
        durationMs: Int64? = nil,
        mediaFile: String? = nil
    ) {
        guard var current = session,
              let open = current.segments.last(where: { $0.isOpen && $0.kind == kind }) else { return }
        ExpressionSessionLifecycle.closeSegment(
            id: open.id,
            in: &current,
            now: access.now,
            status: status,
            durationMs: durationMs,
            mediaFile: mediaFile
        )
        persist(current)
        session = current
    }

    private func persist(_ value: ExpressionSession) {
        do {
            try store.save(value)
            saveError = nil
        } catch {
            saveError = AnkyLocalization.ui("Anky could not save this session. Your recordings are still on this iPhone.")
        }
    }
}
