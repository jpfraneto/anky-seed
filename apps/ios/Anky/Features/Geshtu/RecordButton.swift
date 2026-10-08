//
//  RecordButton.swift
//  Anky
//
//  The one control at the base of the page, and only while the selfie camera
//  is up: the universal record button — red circle to start the take, red
//  square to stop it. (The Geshtu button that used to stand here was retired
//  2026-10-08: asking Anky is a labelled button on the page, and the rail
//  goes to the reply.)
//

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            AnkyHaptics.light()
            onToggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.ankyPaper.opacity(0.92))
                Circle()
                    .strokeBorder(Color.ankyInk.opacity(0.30), lineWidth: 3)
                RoundedRectangle(cornerRadius: isRecording ? 5 : 20, style: .continuous)
                    .fill(Color.ankyMadder)
                    .frame(
                        width: isRecording ? 22 : 40,
                        height: isRecording ? 22 : 40
                    )
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
            .frame(width: 56, height: 56)
            .shadow(color: Color.ankyMadder.opacity(0.32), radius: 9, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .accessibilityLabel(Text(AnkyLocalization.ui(isRecording ? "Stop recording" : "Start recording")))
    }
}
