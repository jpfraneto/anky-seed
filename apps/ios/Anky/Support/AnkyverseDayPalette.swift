import SwiftUI

enum AnkyverseDayPalette {
    static func color(for dayInRegion: Int) -> Color {
        switch normalized(dayInRegion) {
        case 1: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case 2: Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
        case 3: Color(red: 0xFA / 255, green: 0xCC / 255, blue: 0x15 / 255)
        case 4: Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
        case 5: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
        case 6: Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255)
        case 7: Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255)
        default: Color(red: 1, green: 0xF7 / 255, blue: 0xE0 / 255)
        }
    }

    static func symbolColor(for dayInRegion: Int) -> Color {
        switch normalized(dayInRegion) {
        case 3, 8: Color.ankyInk.opacity(0.82) // never pure black — the ink is warm
        default: .ankyPaper
        }
    }

    private static func normalized(_ dayInRegion: Int) -> Int {
        ((max(dayInRegion, 1) - 1) % 8) + 1
    }
}
