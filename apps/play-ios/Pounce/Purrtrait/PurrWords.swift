import PounceKit
import SwiftUI

/// Purrtrait's words on the phones and the TV (spec §11). Terse, no emoji, ours.
enum PurrWords {
    /// The word's group, the TV's one hint.
    static func group(_ group: PurrGroup) -> String {
        switch group {
        case .animals: String(localized: "Animal", comment: "Purrtrait: the word's group, shown as a hint")
        case .food: String(localized: "Food", comment: "Purrtrait: the word's group")
        case .home: String(localized: "Home", comment: "Purrtrait: the word's group (things at home)")
        case .outside: String(localized: "Outside", comment: "Purrtrait: the word's group")
        case .things: String(localized: "Thing", comment: "Purrtrait: the word's group")
        case .actions: String(localized: "Action", comment: "Purrtrait: the word's group (something you do)")
        case .jobs: String(localized: "Job", comment: "Purrtrait: the word's group")
        case .places: String(localized: "Place", comment: "Purrtrait: the word's group")
        case .other: String(localized: "Mystery", comment: "Purrtrait: a word group this app doesn't know yet")
        }
    }

    static func level(_ level: PurrLevel) -> String {
        level == .easy
            ? String(localized: "Easy", comment: "Purrtrait: the easier word to draw")
            : String(localized: "Tricky", comment: "Purrtrait: the harder word to draw")
    }

    static func points(_ n: Int) -> String {
        n == 1
            ? String(localized: "1 point", comment: "Purrtrait: a word's points")
            : String(localized: "\(n) points", comment: "Purrtrait: a word's points")
    }

    static var lookAtTV: String { String(localized: "Look at the TV", comment: "Purrtrait guesser's phone: the drawing is on the TV") }
    static var drawNext: String { String(localized: "You draw next", comment: "Purrtrait guesser's phone: this player draws after this turn") }
    static var waitingForTV: String { String(localized: "Waiting for the TV", comment: "Purrtrait: the TV dropped, the clock is stopped") }
    static var easelFull: String { String(localized: "Easel full", comment: "Purrtrait drawer: no more room for lines this turn") }
    static var gotIt: String { String(localized: "Got it", comment: "Purrtrait drawer: someone guessed the word") }
    static var giveUp: String { String(localized: "Give up", comment: "Purrtrait drawer: end this turn with no points") }
    static var undo: String { String(localized: "Undo", comment: "Purrtrait drawer: take back the last line") }
    static var clear: String { String(localized: "Clear", comment: "Purrtrait drawer: wipe the easel") }
    static var startsOnTV: String { String(localized: "Starts on the TV", comment: "Purrtrait shelf card: only a TV can start this game") }
    static var scanToJoin: String { String(localized: "Scan to join", comment: "Purrtrait TV lobby: over the join QR") }
    static var scanTheTV: String { String(localized: "Scan the code on the TV.", comment: "Purrtrait: a phone that came in without the TV's code") }

    static func isDrawing(_ name: String) -> String {
        String(localized: "\(name) is drawing", comment: "Purrtrait: whose turn it is")
    }

    static func isPicking(_ name: String) -> String {
        String(localized: "\(name) is picking", comment: "Purrtrait: the drawer is choosing a word")
    }

    static func gotItBy(_ name: String) -> String {
        String(localized: "\(name) got it", comment: "Purrtrait reveal: who guessed the word")
    }

    static var nobody: String { String(localized: "Nobody got it", comment: "Purrtrait reveal: the turn ended with no guess") }

    static func colorName(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "Black", comment: "Purrtrait palette colour")
        case 1: String(localized: "Red", comment: "Purrtrait palette colour")
        case 2: String(localized: "Orange", comment: "Purrtrait palette colour")
        case 3: String(localized: "Yellow", comment: "Purrtrait palette colour")
        case 4: String(localized: "Green", comment: "Purrtrait palette colour")
        case 5: String(localized: "Blue", comment: "Purrtrait palette colour")
        case 6: String(localized: "Purple", comment: "Purrtrait palette colour")
        case 7: String(localized: "Brown", comment: "Purrtrait palette colour")
        default: String(localized: "Eraser", comment: "Purrtrait: the white pen that rubs out")
        }
    }

    static func widthName(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "Thin", comment: "Purrtrait pen width")
        case 1: String(localized: "Medium", comment: "Purrtrait pen width")
        default: String(localized: "Thick", comment: "Purrtrait pen width")
        }
    }

    /// "0:42", or "42" under a minute when `short`.
    static func clock(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func winners(_ names: [String]) -> String {
        if names.isEmpty { return String(localized: "Game over", comment: "Purrtrait game over: nobody won") }
        let list = names.formatted(.list(type: .and))
        return names.count > 1
            ? String(localized: "\(list) win!", comment: "Game over title: a shared win")
            : String(localized: "\(list) wins!", comment: "Game over title")
    }
}

extension InkGrid {
    /// A palette colour for SwiftUI.
    static func swatch(_ n: Int) -> Color { Color(cgColor: InkRender.color(n)) }
}

/// The easel's frame: chunky magenta wood with a dark outline around white paper, in the app's
/// loud style. `content` fills the paper, 3:4.
struct PurrEaselFrame<Content: View>: View {
    var border: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: border, style: .continuous))
            .padding(border)
            .background(
                RoundedRectangle(cornerRadius: border * 2.2, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.magenta.mix(with: .white, by: 0.2), Palette.magenta,
                                                  Palette.magenta.mix(with: Palette.ink, by: 0.3)],
                                         startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: border * 2.2, style: .continuous).strokeBorder(Palette.ink, lineWidth: max(3, border * 0.5)))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: border * 0.6)
    }
}

/// A countdown pill, counting down locally from the room's `remainingMs` (it stops while paused).
struct PurrClock: View {
    let deadline: Date?
    /// The seconds left when paused (nil deadline).
    let frozen: Int?
    var size: CGFloat = 22

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = seconds(at: context.date)
            OutlinedText(PurrWords.clock(left), size: size, fill: left <= 10 ? Palette.yellow : .white, width: size * 0.12)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, size * 0.6)
                .padding(.vertical, size * 0.22)
                .background(Capsule().fill(left <= 10 ? Palette.refuse : Palette.violet).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                .accessibilityLabel(Text("\(left) seconds left", comment: "Purrtrait: VoiceOver, the turn's clock"))
        }
        .accessibilityIdentifier("purr.clock")
    }

    private func seconds(at now: Date) -> Int {
        if let deadline { return max(Int(deadline.timeIntervalSince(now).rounded(.up)), 0) }
        return frozen ?? 0
    }
}
