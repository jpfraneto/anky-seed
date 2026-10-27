//
//  GeshtuState.swift
//  Anky
//
//  The app is one page with a drawer beside it. The page is always the
//  writing surface — a live writing, or a finished one that a tap reopens.
//  This holds what sits beside that page: the drawer, the settings and stats
//  sheets, and the drawer's request to put a past writing on the page.
//

import SwiftUI

@MainActor
final class GeshtuState: ObservableObject {

    // MARK: - The drawer

    // The drawer is not a destination: whatever was on the page is still
    // there when it closes.

    @Published private(set) var drawerIsOpen = false
    /// Settings and stats rise as sheets over the page.
    @Published var settingsIsOpen = false
    @Published var statsIsOpen = false

    /// A past writing the drawer asked to put on the page. The world takes
    /// it (`consumeEntryRequest`) and loads it into the writing engine.
    @Published private(set) var entryRequest: SavedAnky?

    func openDrawer() {
        guard !drawerIsOpen else { return }
        withAnimation(Self.drawerSpring) { drawerIsOpen = true }
    }

    func closeDrawer() {
        guard drawerIsOpen else { return }
        withAnimation(Self.drawerSpring) { drawerIsOpen = false }
    }

    static let drawerSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)

    func openEntry(_ anky: SavedAnky) {
        entryRequest = anky
    }

    func consumeEntryRequest() -> SavedAnky? {
        defer { entryRequest = nil }
        return entryRequest
    }

    /// A past session the drawer asked to show as a memory.
    @Published private(set) var sessionRequest: ExpressionSession?

    func openSession(_ session: ExpressionSession) {
        sessionRequest = session
    }

    func consumeSessionRequest() -> ExpressionSession? {
        defer { sessionRequest = nil }
        return sessionRequest
    }
}
