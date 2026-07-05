import SwiftUI

enum AnkySequenceName: String, CaseIterable {
    case findingThread
    case idleFront
    case idleBlink
    case waveFront
    case walkRight
    case celebrate
    case seated
    case sleeping
    case softConcern
    case shyListening

    var frames: [String] {
        switch self {
        case .celebrate:
            return numberedFrames(27...31)
        case .findingThread:
            return (1...8).map { String(format: "Ankythread_%03d", $0) }
        case .idleBlink:
            return numberedFrames(40...45)
        case .idleFront:
            return numberedFrames(1...6)
        case .seated:
            return numberedFrames(46...51)
        case .shyListening:
            return numberedFrames(52...57)
        case .sleeping:
            return numberedFrames(36...39)
        case .softConcern:
            return numberedFrames(32...35)
        case .walkRight:
            return numberedFrames(7...22)
        case .waveFront:
            return numberedFrames(23...26)
        }
    }

    var fps: Double {
        switch self {
        case .findingThread:
            return 2.4
        case .celebrate, .waveFront:
            return 5
        case .walkRight:
            return 8
        case .sleeping:
            return 2
        default:
            return 4
        }
    }

    var next: AnkySequenceName {
        let order: [AnkySequenceName] = [
            .idleFront,
            .idleBlink,
            .waveFront,
            .walkRight,
            .celebrate,
            .seated,
            .sleeping,
            .softConcern,
            .shyListening
        ]
        guard let index = order.firstIndex(of: self) else {
            return .idleFront
        }

        return order[(index + 1) % order.count]
    }

    private func numberedFrames(_ range: ClosedRange<Int>) -> [String] {
        range.map { String(format: "Anky%03d", $0) }
    }
}

struct AnkySpriteView: View {
    let sequence: AnkySequenceName
    let size: CGFloat
    var opacity = 1.0
    var loop = true

    @State private var cursor = 0
    @State private var breathes = false

    var body: some View {
        let frames = sequence.frames
        let frameName = frames.isEmpty ? "Anky001" : frames[min(cursor, frames.count - 1)]

        Image(frameName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(opacity)
            .scaleEffect(breathes ? 1.018 : 1)
            .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: breathes)
            .onAppear {
                breathes = true
                cursor = 0
            }
            .onChange(of: sequence) { _ in
                cursor = 0
            }
            .task(id: sequence.rawValue) {
                await animateFrames(frames)
            }
            .accessibilityLabel("Anky")
    }

    private func animateFrames(_ frames: [String]) async {
        guard frames.count > 1 else {
            return
        }

        let interval = UInt64(max(80, Int(1000 / sequence.fps))) * 1_000_000

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: interval)
            if Task.isCancelled {
                return
            }

            await MainActor.run {
                let next = cursor + 1
                if next < frames.count {
                    cursor = next
                } else if loop {
                    cursor = 0
                }
            }
        }
    }
}
