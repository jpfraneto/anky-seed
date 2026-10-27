//
//  ExpressionSession.swift
//  Anky
//
//  One session is one stretch of time someone spent with Anky — walking, or
//  staying where they are — and everything they chose to express during it:
//  passages written, things said, video recorded, a livestream, silence.
//
//  The session is a manifest (`session.json`) that *composes* existing
//  artifacts; it never replaces them. A written passage is still a plain
//  `.anky` file in the writing archive, byte-for-byte the protocol it always
//  was, and the manifest only points at it by hash. Audio and video live in
//  the session's own `media/` folder.
//
//  Writings made before sessions existed stay exactly as they are: they are
//  not wrapped, not relabeled as walks, and no movement data is invented
//  for them.
//
//  Format: `anky.session`, version 1. Readers ignore fields they do not
//  know; a manifest with a newer version is read but never rewritten.
//

import Foundation

enum ExpressionKind: String, Codable, CaseIterable {
    case writing
    case voice
    case video
    case live
    case silence
    /// A kind written by a newer Anky. Kept so the manifest still reads.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpressionKind(rawValue: raw) ?? .unknown
    }
}

/// Optional, chosen by the person, never inferred.
enum SessionSetting: String, Codable {
    case walking
    case still
}

struct LiveSegmentInfo: Codable, Equatable {
    var liveId: String
    var audience: String
    var viewerURL: String?
    /// How the broadcast ended: "stopped", "network_lost", "ended_by_moderation".
    var endReason: String?
}

struct ExpressionSegment: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        /// Being captured right now (or was, when the app stopped).
        case open
        case complete
        /// Closed during recovery after the app stopped mid-capture. The media
        /// is kept as far as it was written.
        case recovered
        /// Capture failed; kept so the timeline stays truthful.
        case failed
    }

    var id: UUID
    var kind: ExpressionKind
    var startedAt: Date
    var endedAt: Date?
    var status: Status
    /// Writing: the sealed `.anky` artifact's SHA-256, in the writing archive.
    var ankyHash: String?
    /// Voice/video: path relative to the session folder, e.g. "media/….m4a".
    var mediaFile: String?
    var durationMs: Int64?
    var live: LiveSegmentInfo?

    init(
        id: UUID = UUID(),
        kind: ExpressionKind,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .open,
        ankyHash: String? = nil,
        mediaFile: String? = nil,
        durationMs: Int64? = nil,
        live: LiveSegmentInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.ankyHash = ankyHash
        self.mediaFile = mediaFile
        self.durationMs = durationMs
        self.live = live
    }

    var isOpen: Bool { status == .open }
}

struct ExpressionSession: Codable, Equatable, Identifiable {
    static let format = "anky.session"
    static let currentVersion = 1

    var format: String
    var version: Int
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var setting: SessionSetting?
    /// True when the session was closed by recovery rather than by the
    /// person (the app stopped while it was open).
    var endedByRecovery: Bool?
    var segments: [ExpressionSegment]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        setting: SessionSetting? = nil,
        segments: [ExpressionSegment] = []
    ) {
        self.format = Self.format
        self.version = Self.currentVersion
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.setting = setting
        self.endedByRecovery = nil
        self.segments = segments
    }

    var isActive: Bool { endedAt == nil }

    /// Written by a newer Anky: read it, never rewrite it.
    var isFromNewerVersion: Bool { version > Self.currentVersion }

    var openSegment: ExpressionSegment? { segments.last(where: \.isOpen) }

    /// The kinds expressed, in first-appearance order, for a quiet summary.
    var expressedKinds: [ExpressionKind] {
        var seen: [ExpressionKind] = []
        for segment in segments where segment.status != .failed && !seen.contains(segment.kind) {
            seen.append(segment.kind)
        }
        return seen
    }

    var writingHashes: [String] { segments.compactMap(\.ankyHash) }

    func duration(until now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

// MARK: - Lifecycle rules (pure)

enum ExpressionSessionLifecycle {
    /// Opens a new segment. Any segment still open is closed at `now` first:
    /// one medium at a time, and switching never loses what came before.
    static func open(_ segment: ExpressionSegment, in session: inout ExpressionSession, now: Date) {
        closeOpenSegments(in: &session, now: now, status: .complete)
        session.segments.append(segment)
    }

    static func closeSegment(
        id: UUID,
        in session: inout ExpressionSession,
        now: Date,
        status: ExpressionSegment.Status = .complete,
        durationMs: Int64? = nil,
        mediaFile: String? = nil
    ) {
        guard let index = session.segments.firstIndex(where: { $0.id == id }) else { return }
        var segment = session.segments[index]
        if segment.endedAt == nil { segment.endedAt = now }
        segment.status = status
        if let durationMs { segment.durationMs = durationMs }
        if let mediaFile { segment.mediaFile = mediaFile }
        if segment.durationMs == nil, let end = segment.endedAt {
            segment.durationMs = Int64(max(0, end.timeIntervalSince(segment.startedAt)) * 1000)
        }
        session.segments[index] = segment
    }

    static func closeOpenSegments(in session: inout ExpressionSession, now: Date, status: ExpressionSegment.Status) {
        for segment in session.segments where segment.isOpen {
            closeSegment(id: segment.id, in: &session, now: now, status: status)
        }
    }

    /// A sealed writing joins the session. A writing reopened and resealed
    /// replaces its earlier artifact, so its segment follows the new hash
    /// instead of appearing twice.
    static func recordWriting(
        hash: String,
        replacing replacedHash: String?,
        startedAt: Date,
        durationMs: Int64,
        in session: inout ExpressionSession,
        now: Date
    ) {
        if let replacedHash,
           let index = session.segments.firstIndex(where: { $0.ankyHash == replacedHash }) {
            session.segments[index].ankyHash = hash
            session.segments[index].endedAt = now
            session.segments[index].durationMs = durationMs
            session.segments[index].status = .complete
            return
        }
        guard !session.segments.contains(where: { $0.ankyHash == hash }) else { return }
        closeOpenSegments(in: &session, now: now, status: .complete)
        session.segments.append(ExpressionSegment(
            kind: .writing,
            startedAt: startedAt,
            endedAt: now,
            status: .complete,
            ankyHash: hash,
            durationMs: durationMs
        ))
    }

    static func end(_ session: inout ExpressionSession, now: Date) {
        closeOpenSegments(in: &session, now: now, status: .complete)
        if session.endedAt == nil { session.endedAt = now }
    }

    /// The app stopped while a session was open. Close whatever was being
    /// captured at the last moment its file was written to (never later than
    /// now), keep the session itself open so the person can continue or end
    /// it, and say that recovery happened.
    static func recover(
        _ session: inout ExpressionSession,
        now: Date,
        lastWrite: (ExpressionSegment) -> Date?
    ) {
        for segment in session.segments where segment.isOpen {
            let end = min(now, max(segment.startedAt, lastWrite(segment) ?? segment.startedAt))
            closeSegment(id: segment.id, in: &session, now: end, status: .recovered)
            if let index = session.segments.firstIndex(where: { $0.id == segment.id }) {
                session.segments[index].durationMs = Int64(end.timeIntervalSince(segment.startedAt) * 1000)
            }
        }
    }
}
