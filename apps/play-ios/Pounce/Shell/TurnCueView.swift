import PounceKit
import SwiftUI

/// The table's turn overlay (`TurnCue`): the big "Your turn" moment. Nobody else's turn gets a
/// label (their cat's glowing ring says it). It never takes a touch, so every tap goes through to the table
/// under it (the first one puts "Your turn" away). Laid out in scene space: the view ignores
/// the safe area, like the table.
struct TurnCueView: View {
    let cue: TurnCue
    /// A first-game tip is up where the lettering would land: the lettering steps aside and the
    /// piles keep pulsing.
    var yield = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            // Scene space (y up from the bottom) to this view's space.
            let local: (CGRect) -> CGRect = { r in
                CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
            }
            switch cue {
            case .mine(let mine):
                YourTurnCue(cue: mine, yield: yield, size: geo.size, local: local)
                    // A new turn, or the same one again after the background: the entrance replays.
                    .id("\(mine.key.epoch).\(mine.key.seat).\(mine.showing)")
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Your cat pounces in from the side, "Your turn!" slams down in bold outlined letters with a
/// bounce, and the piles you can draw from pulse. Then it breathes gently until the first touch
/// on the table. Reduce Motion: no pounce, slam or pulse; it simply appears, still big and bold.
private struct YourTurnCue: View {
    let cue: TurnCue.Mine
    let yield: Bool
    let size: CGSize
    let local: (CGRect) -> CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0: the cat is off the side; 1: at the top of its leap; 2: landed.
    @State private var leap = 0
    @State private var slammed = false
    @State private var pulse = false

    private var title: String {
        cue.multiSeat
            ? String(localized: "Your turn, \(cue.name)!", comment: "The big turn cue on a phone several people share")
            : String(localized: "Your turn!", comment: "The big turn cue when this phone's turn starts")
    }

    private var subtitle: String? {
        cue.draw ? String(localized: "Draw a card", comment: "Under the turn cue: what to do first") : nil
    }

    var body: some View {
        let stage = local(cue.stage)
        // As big as the narrowest phone allows (the SE is 375 pt wide), and no bigger.
        let side = min(size.width * 0.17, 80)
        let letters = min(size.width * 0.125, 56)
        let center = CGPoint(x: size.width / 2, y: stage.height > 0 ? stage.midY : size.height * 0.55)
        ZStack {
            ForEach(Array(cue.piles.enumerated()), id: \.offset) { _, pile in
                PileRing(frame: local(pile), pulse: pulse)
            }
            // A soft pool of night behind the lettering, so it reads over any cards.
            Ellipse()
                .fill(RadialGradient(
                    colors: [Palette.night.opacity(0.85), Palette.night.opacity(0.55), .clear],
                    center: .center, startRadius: 0, endRadius: size.width * 0.5))
                .frame(width: size.width * 1.05, height: letters * 3.6)
                .opacity(slammed && !yield ? 1 : 0)
                .position(center)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 2) {
                cat(side: side)
                VStack(spacing: 6) {
                    OutlinedText(title, size: letters, fill: Palette.orange, width: 5, lines: 2)
                        .scaleEffect(slammed ? (pulse ? 1.06 : 1) : (reduceMotion ? 1 : 2.4))
                        .rotationEffect(.degrees(slammed && !reduceMotion ? -3 : 0))
                        .opacity(slammed ? 1 : 0)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: max(letters * 0.36, 17), weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Palette.lime))
                            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                            .opacity(slammed ? 1 : 0)
                            .offset(y: slammed || reduceMotion ? 0 : 16)
                    }
                }
                // Its own width (a long name wraps), so the cat lands right beside the words.
                .frame(maxWidth: size.width - side - 36)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            // One element the size of the words (never over a pile or a card).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(subtitle.map { "\(title) \($0)" } ?? title))
            .accessibilityIdentifier("turncue.mine")
            .opacity(yield ? 0 : 1)
            .position(center)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.15).paced, value: yield)
        .onAppear(perform: enter)
    }

    private func cat(side: CGFloat) -> some View {
        let away = leap == 0 && !reduceMotion
        return Image(ArtName.cat(cue.cat, leap == 2 || reduceMotion ? .celebrate : .leap))
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
            .offset(
                x: away ? -size.width * 0.6 : (leap == 1 ? -side * 0.6 : 0),
                y: away ? -side * 0.2 : (leap == 1 ? -side * 0.9 : 0))
            .rotationEffect(.degrees(leap == 1 ? -14 : 0))
            .accessibilityHidden(true)
    }

    private func enter() {
        let said = subtitle.map { "\(title) \($0)" } ?? title
        UIAccessibility.post(notification: .announcement, argument: said)
        Haptics.shared.turn()
        if reduceMotion {
            Sound.shared.play(ArtName.Sound.sfxPop)
            withAnimation(.easeOut(duration: 0.2).paced) {
                leap = 2
                slammed = true
            }
            return
        }
        Sound.shared.play(ArtName.Sound.sfxLeap)
        withAnimation(.easeOut(duration: 0.2).paced) {
            leap = 1
        } completion: {
            withAnimation(.easeIn(duration: 0.14).paced) {
                leap = 2
            } completion: {
                Sound.shared.play(ArtName.Sound.sfxPop)
                withAnimation(.spring(duration: 0.4, bounce: 0.5).paced) {
                    slammed = true
                } completion: {
                    // Then it breathes until the first touch. Not under a UI test: XCUITest waits
                    // for the app to idle before every query, and an endless animation never does.
                    guard !Pace.underTest else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).paced) { pulse = true }
                }
            }
        }
    }
}

/// "Start here": a thick ring around a pile you can draw from, breathing with the lettering.
private struct PileRing: View {
    let frame: CGRect
    let pulse: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Palette.ink, lineWidth: 9)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.orange, lineWidth: 5).padding(2))
            .frame(width: frame.width + 16, height: frame.height + 16)
            .shadow(color: Palette.orange.opacity(pulse ? 0.9 : 0.5), radius: pulse ? 16 : 8)
            .scaleEffect(pulse ? 1.08 : 1)
            .position(x: frame.midX, y: frame.midY)
            .accessibilityHidden(true)
    }
}
