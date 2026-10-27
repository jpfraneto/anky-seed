//
//  TrustedClock.swift
//  Anky
//
//  The free window is measured in real days. A device clock can be set
//  back; this keeps "now" honest without punishing anyone for travel or
//  small drift:
//
//    • The highest time Anky has ever observed (device or server) is kept
//      as a high-water mark. A device clock more than `rewindTolerance`
//      behind it means the clock was set back.
//    • When the server answers, its time anchors "now" for the rest of the
//      process via the monotonic system uptime, which no clock setting can
//      move.
//
//  Moving the clock forward only ends the free window sooner — harmless to
//  the person's memories, and corrected by the next server answer.
//

import Foundation

struct ServerTimeAnchor: Equatable {
    var serverNow: Date
    var uptimeAtSync: TimeInterval
}

struct TrustedClockState: Codable, Equatable {
    var highWaterMark: Date
}

enum TrustedClock {
    /// Ordinary drift, NTP corrections and time-zone travel stay well inside
    /// this. (Time zones do not move `Date` at all; this is for real drift.)
    static let rewindTolerance: TimeInterval = 10 * 60

    /// Evaluates "now" and returns the state to persist afterwards.
    static func evaluate(
        deviceNow: Date,
        uptime: TimeInterval,
        anchor: ServerTimeAnchor?,
        state: TrustedClockState?
    ) -> (now: TrustedNow, state: TrustedClockState) {
        let highWater = state?.highWaterMark ?? deviceNow

        if let anchor, uptime >= anchor.uptimeAtSync {
            let anchored = anchor.serverNow.addingTimeInterval(uptime - anchor.uptimeAtSync)
            let next = TrustedClockState(highWaterMark: max(highWater, anchored))
            return (TrustedNow(date: anchored, isTrusted: true), next)
        }

        if deviceNow < highWater.addingTimeInterval(-rewindTolerance) {
            // Set back. Do not let "now" go backwards, and say so.
            return (TrustedNow(date: highWater, isTrusted: false), TrustedClockState(highWaterMark: highWater))
        }
        let now = max(deviceNow, highWater)
        return (TrustedNow(date: now, isTrusted: true), TrustedClockState(highWaterMark: now))
    }
}

/// Persists the clock's high-water mark in the Keychain so that deleting
/// and reinstalling the app does not forget it. Device-only (not synced):
/// another device has its own clock.
struct TrustedClockStore {
    private let keychain: KeychainClient
    private static let account = "anky.access.clock.v1"

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
    }

    func load() -> TrustedClockState? {
        guard let data = try? keychain.data(for: Self.account) else { return nil }
        return try? JSONDecoder.accessDecoder.decode(TrustedClockState.self, from: data)
    }

    func save(_ state: TrustedClockState) {
        guard let data = try? JSONEncoder.accessEncoder.encode(state) else { return }
        try? keychain.save(data, account: Self.account)
    }

    func clear() {
        try? keychain.delete(account: Self.account)
    }
}

/// The free window's start, kept in the Keychain (survives reinstall) and
/// synchronized through iCloud Keychain when available, so a new device on
/// the same Apple ID continues the same seven days instead of opening new
/// ones. The server ledger is the second, authoritative copy.
struct FreeAccessLedgerStore {
    private let keychain: KeychainClient
    private static let account = "anky.access.free.v1"

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
    }

    func load() -> FreeAccessRecord? {
        let candidates = [true, false].compactMap { synced -> FreeAccessRecord? in
            guard let data = try? keychain.data(for: Self.account, synchronizable: synced) else { return nil }
            return try? JSONDecoder.accessDecoder.decode(FreeAccessRecord.self, from: data)
        }
        // Two copies can only disagree after a failed write; the earlier
        // start is the honest one.
        return candidates.min { $0.startedAt < $1.startedAt }
    }

    func save(_ record: FreeAccessRecord) {
        guard let data = try? JSONEncoder.accessEncoder.encode(record) else { return }
        // Synced copy when iCloud Keychain allows it; the device copy always.
        try? keychain.save(data, account: Self.account, synchronizable: true)
        try? keychain.save(data, account: Self.account, synchronizable: false)
    }

    func clear() {
        try? keychain.delete(account: Self.account, synchronizable: true)
        try? keychain.delete(account: Self.account, synchronizable: false)
    }
}

enum FreeAccessLedger {
    /// Opens the free window at `now` if it is not open yet. Never moves an
    /// existing start.
    static func begin(existing: FreeAccessRecord?, now: Date) -> FreeAccessRecord {
        existing ?? FreeAccessRecord(startedAt: now, confirmedByServer: false)
    }

    /// Merges the server's answer. The earliest known start wins, so neither
    /// a reinstall nor a second device opens a new seven days.
    static func merge(local: FreeAccessRecord?, serverStartedAt: Date?) -> FreeAccessRecord? {
        guard let serverStartedAt else { return local }
        guard let local else {
            return FreeAccessRecord(startedAt: serverStartedAt, confirmedByServer: true)
        }
        return FreeAccessRecord(startedAt: min(local.startedAt, serverStartedAt), confirmedByServer: true)
    }
}

extension JSONEncoder {
    static var accessEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var accessDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
