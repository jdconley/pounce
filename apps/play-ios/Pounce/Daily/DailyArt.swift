import PounceKit
import SwiftUI

/// Each daily game's look on the Dish: its color and a glyph, until the game's own art lands
/// (a game may add its art here in its one-line change).
enum DailyArt {
    static func tint(_ game: DailyGameInfo) -> Color { Color(hex: game.tint) }

    static func glyph(_ game: String) -> String {
        switch game {
        case "sniff": "nose.fill"
        case "nine-lives": "pawprint.fill"
        case "cat-nap": "moon.zzz.fill"
        case "box-fort": "shippingbox.fill"
        default: "number"
        }
    }
}

/// A game's treat: its color disc, ink ring and glyph, with a lip of shadow. Done (solved, or Box
/// Fort's ending): a check badge. Ended without finishing: a neutral moon, as on the board's rows,
/// so it never reads as solved.
struct DailyTreat: View {
    let game: DailyGameInfo
    var side: CGFloat = 64
    var done = false
    var ended = false

    var body: some View {
        let tint = DailyArt.tint(game)
        Circle()
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.3), tint], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(3, side * 0.06)))
            .overlay {
                Image(systemName: DailyArt.glyph(game.id))
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .shadow(color: Palette.ink, radius: 0, x: 0, y: side * 0.03)
                    .padding(side * 0.24)
            }
            .overlay(alignment: .bottomTrailing) {
                if done || ended {
                    Image(systemName: done ? "checkmark" : "moon.fill")
                        .font(.system(size: side * 0.2, weight: .black))
                        .foregroundStyle(done ? Palette.ink : .white)
                        .frame(width: side * 0.38, height: side * 0.38)
                        .background(
                            Circle().fill(done ? Palette.lime : Palette.night.mix(with: .white, by: 0.3))
                                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(2, side * 0.04))))
                        .compositingGroup()
                        .offset(x: side * 0.06, y: side * 0.04)
                }
            }
            .frame(width: side, height: side)
            .compositingGroup()
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: side * 0.06)
            .accessibilityHidden(true)
    }
}
