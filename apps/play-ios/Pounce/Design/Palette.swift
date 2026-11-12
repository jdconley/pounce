import SwiftUI

/// The "Loud Toy" candy palette. Saturated only: no beige, cream or pastel.
enum Palette {
    static let violet = Color(hex: 0x7B2FFF)
    static let magenta = Color(hex: 0xFF2E9A)
    static let teal = Color(hex: 0x00D1C1)
    static let orange = Color(hex: 0xFF8A00)
    static let sky = Color(hex: 0x2EB8FF)
    static let lime = Color(hex: 0x9BE22E)
    /// The tip bubble and its ring.
    static let yellow = Color(hex: 0xFFD21F)
    /// A drop the table refuses (the ring around a laid group that can't take the card).
    static let refuse = Color(hex: 0xFF3B4E)
    /// Outline color for everything chunky.
    static let ink = Color(hex: 0x1B0B3A)
    /// App background.
    static let night = Color(hex: 0x2A0F5C)

    /// Card numerals by coat: tabby orange and tuxedo pink like their glyphs (stripes, bow),
    /// calico teal (ink would melt into the outline), gray violet like its paw. Each is at least
    /// 4.5:1 on the white card face before its ink outline: tabby 5.1, tuxedo 5.4, calico 5.2,
    /// gray 5.7.
    static let numeralTabby = Color(hex: 0xC24400)
    static let numeralTuxedo = Color(hex: 0xD1006B)
    static let numeralCalico = Color(hex: 0x00788A)
    static let numeralGray = violet

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
