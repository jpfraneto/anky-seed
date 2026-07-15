//
//  AxisVoices.swift
//  Anky — the Axis Redesign (spec §10 addition, addendum A4).
//
//  Two voices within the lazure register. The user's writing and Anky's
//  reflection must read as two substances in one world — never labelled,
//  never "You wrote" / "Anky said". Typography alone carries the distinction.
//
//  These are named tokens (view modifiers over the .fraunces type system and
//  the ore/glaze ink pair), not inline modifiers scattered at each call site:
//
//    Ore   — the writing at rest. Sediment: Fraunces regular, a smaller optical
//            size, tighter leading, grayer/rawer ink. The sealed writing on the
//            channel-closed screen and the writing inside opened strata entries.
//    Glaze — Anky's reflection at rest. Fraunces italic (the one treatment,
//            applied identically everywhere), more luminous ink, looser leading,
//            more breathing room. The §6 descent and the opened-entry reflection.
//
//  Ore/glaze applies only within lazure, at rest. The live writing session keeps
//  its own styling (it is the act, not the record); the vigil's traveling words
//  keep the electric register's serif italic.
//

import SwiftUI

extension View {
    /// Ore — the user's writing at rest (addendum A4).
    func oreVoice() -> some View { modifier(OreVoice()) }

    /// Glaze — Anky's reflection at rest (addendum A4).
    func glazeVoice() -> some View { modifier(GlazeVoice()) }
}

private struct OreVoice: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.fraunces(18, weight: .regular))
            .foregroundStyle(Color.ankyOre)
            .lineSpacing(5)
    }
}

private struct GlazeVoice: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.fraunces(20, weight: .regular, italic: true))
            .foregroundStyle(Color.ankyGlaze)
            .lineSpacing(11)
    }
}
