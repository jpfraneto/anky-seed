//
//  AccessPolicy.swift
//  Anky
//
//  The single answer to "may this person do this right now?".
//
//  The rules, in plain words:
//    • Every new person has seven days of the full core experience, free.
//      The seven days begin the first time they start expressing (a session
//      or a reopened writing), not at install. No payment is asked for and
//      nothing is billed when the days end.
//    • After the seven days, starting or continuing expression needs an
//      active subscription.
//    • A session that began while access was open may be finished: new
//      segments are allowed inside it for a bounded grace period after
//      access ends. A recording in progress is never interrupted by this
//      policy — it is only asked at the moment something starts.
//    • AI is for verified subscribers only.
//    • Reading and exporting what someone made is always allowed, in every
//      state, including every uncertain one.
//
//  This file is pure: no StoreKit, no network, no UIKit. Every input is a
//  value, so every rule is unit-tested.
//

import Foundation

enum FreeAccess {
    static let days = 7
    static let duration: TimeInterval = TimeInterval(days) * 24 * 60 * 60
}

/// Where the free window stands, as known locally (Keychain) and, when the
/// server has answered, confirmed by it.
struct FreeAccessRecord: Codable, Equatable {
    var startedAt: Date
    /// True once the server's ledger has answered with this start (or an
    /// earlier one, which then replaced it).
    var confirmedByServer: Bool

    var endsAt: Date { startedAt.addingTimeInterval(FreeAccess.duration) }
}

/// The subscription as last verified with RevenueCat (`pro` entitlement).
enum SubscriptionStatus: Equatable {
    /// Never verified on this device — not the same as "not subscribed".
    case unknown
    case active(verifiedAt: Date, expiresAt: Date?)
    case inactive(verifiedAt: Date)
}

/// A trustworthy "now": either anchored to the server's clock, or the
/// device clock checked against the highest time this app has ever seen.
struct TrustedNow: Equatable {
    var date: Date
    /// False when the device clock is behind a time Anky already observed
    /// (it was set back) and no server time is available to correct it.
    var isTrusted: Bool
}

struct AccessInputs: Equatable {
    var now: TrustedNow
    var freeAccess: FreeAccessRecord?
    var subscription: SubscriptionStatus
}

/// The access states the brief names. Purchase/restoration in progress is
/// tracked beside this (it changes buttons, not permissions).
enum AccessState: Equatable {
    case subscriber(expiresAt: Date?)
    /// Not started yet: the first expression will open the seven days.
    case freeNotStarted
    case freeActive(endsAt: Date)
    case freeExpired(endedAt: Date)
    /// Cannot be decided safely right now (clock set back while offline, or a
    /// subscription not re-verified for too long). Creation waits; memories
    /// stay readable and exportable.
    case unverified(lastKnownEnd: Date?)
}

enum AccessAction: Equatable {
    case startSession
    /// Reopening a finished writing to keep writing, outside a session.
    case continueWriting
    /// Anything new inside an already-open session: a writing, a voice or
    /// video recording, a silence, a livestream.
    case newSegment(sessionStartedAt: Date)
    case requestAI
    case readMemories
    case exportMemories
}

enum AccessDenial: Equatable {
    /// The seven days are complete and there is no active subscription.
    case freeAccessComplete
    /// AI needs a verified subscription (free days do not include it).
    case subscriptionRequired
    /// Anky cannot verify access right now; try again when online.
    case needsVerification
}

enum AccessDecision: Equatable {
    case allowed
    case denied(AccessDenial)

    var isAllowed: Bool { self == .allowed }
}

enum AccessPolicy {
    /// How long a verified subscription is trusted without re-verifying.
    /// RevenueCat refreshes on every foreground; this bounds a long offline
    /// stretch (a walk in the mountains) without making it fragile.
    static let subscriptionCacheLifetime: TimeInterval = 7 * 24 * 60 * 60

    /// After access ends, an already-open session may still take new
    /// segments for this long, so nobody is cut off mid-walk.
    static let openSessionGrace: TimeInterval = 12 * 60 * 60

    static func state(_ inputs: AccessInputs) -> AccessState {
        let now = inputs.now.date

        if let subscriberEnd = verifiedSubscriberEnd(inputs) {
            return .subscriber(expiresAt: subscriberEnd == .distantFuture ? nil : subscriberEnd)
        }
        // A subscription verified active long ago is not proof today; fall
        // through to the free window, and if that does not open the door,
        // say "unverified" rather than "expired".
        let staleActiveSubscription: Bool = {
            if case .active = inputs.subscription { return true }
            return false
        }()

        guard let free = inputs.freeAccess else {
            // Nothing started. A rewound clock does not matter here: the
            // window will begin at a trusted-or-high-water time.
            return .freeNotStarted
        }

        if !inputs.now.isTrusted {
            return .unverified(lastKnownEnd: free.endsAt)
        }
        if now < free.endsAt {
            return .freeActive(endsAt: free.endsAt)
        }
        if staleActiveSubscription {
            return .unverified(lastKnownEnd: free.endsAt)
        }
        return .freeExpired(endedAt: free.endsAt)
    }

    static func decide(_ action: AccessAction, _ inputs: AccessInputs) -> AccessDecision {
        switch action {
        case .readMemories, .exportMemories:
            // Never hold anyone's memories hostage, in any state.
            return .allowed

        case .requestAI:
            return verifiedSubscriberEnd(inputs) != nil ? .allowed : .denied(.subscriptionRequired)

        case .startSession, .continueWriting:
            return creationDecision(state(inputs))

        case .newSegment(let sessionStartedAt):
            let current = state(inputs)
            if creationDecision(current) == .allowed {
                return .allowed
            }
            // The open-session boundary: the session began before access
            // ended, and the grace period after that end has not passed.
            if let end = accessEnd(of: current, inputs),
               sessionStartedAt < end,
               inputs.now.date < end.addingTimeInterval(openSessionGrace) {
                return .allowed
            }
            return creationDecision(current)
        }
    }

    private static func creationDecision(_ state: AccessState) -> AccessDecision {
        switch state {
        case .subscriber, .freeNotStarted, .freeActive:
            return .allowed
        case .freeExpired:
            return .denied(.freeAccessComplete)
        case .unverified:
            return .denied(.needsVerification)
        }
    }

    /// When access (free or paid) last ended, for the open-session grace.
    private static func accessEnd(of state: AccessState, _ inputs: AccessInputs) -> Date? {
        var candidates: [Date] = []
        if let free = inputs.freeAccess { candidates.append(free.endsAt) }
        if case .active(_, let expiresAt?) = inputs.subscription { candidates.append(expiresAt) }
        switch state {
        case .freeExpired(let endedAt): candidates.append(endedAt)
        case .unverified(let lastKnownEnd?): candidates.append(lastKnownEnd)
        default: break
        }
        return candidates.max()
    }

    /// The subscription's end if it is verified and current, otherwise nil.
    /// `Date.distantFuture` stands for "active, no expiry reported".
    private static func verifiedSubscriberEnd(_ inputs: AccessInputs) -> Date? {
        guard case .active(let verifiedAt, let expiresAt) = inputs.subscription else { return nil }
        let now = inputs.now.date
        guard now.timeIntervalSince(verifiedAt) <= subscriptionCacheLifetime else { return nil }
        if let expiresAt {
            return expiresAt > now ? expiresAt : nil
        }
        return Date.distantFuture
    }
}

extension AccessState {
    var isSubscriber: Bool {
        if case .subscriber = self { return true }
        return false
    }

    /// The end of the free window, while it is open.
    var freeAccessEndsAt: Date? {
        if case .freeActive(let endsAt) = self { return endsAt }
        return nil
    }
}
