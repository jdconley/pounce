import SwiftUI

/// The "Loud Toy" candy palette. Saturated only: no beige, cream or pastel.
enum Palette {
    static let violet = Color(hex: 0x7B2FFF)
    static let magenta = Color(hex: 0xFF2E9A)
    static let teal = Color(hex: 0x00D1C1)
    static let orange = Color(hex: 0xFF8A00)
    static let sky = Color(hex: 0x2EB8FF)
    static let lime = Color(hex: 0x9BE22E)
    /// Outline color for everything chunky.
    static let ink = Color(hex: 0x1B0B3A)
    /// App background.
    static let night = Color(hex: 0x2A0F5C)

    /// Seat avatar rings, in seat order.
    static let playerRings: [Color] = [violet, magenta, teal, orange, sky, lime]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
