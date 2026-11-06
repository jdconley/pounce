import PounceKit
import SwiftUI

/// Home's streak strip (trophy room design §1): your own streak (opens the trophy room), one chip
/// per connection in top-pair order (opens Us on that pair), and the plus, always last (opens the
/// invite sheet). With no connections the plus is the big, bouncing "add someone". The gift box
/// sits before the first chip, the sign-in cloud on the top pair's chip and a waiting pounce's bell
/// on its pair's chip, where PR 4 put them. No words.
struct StreakStripView: View {
    @Environment(AppModel.self) private var model
    var scale: CGFloat = 1
    let onCloud: () -> Void

    private var store: StreakStore { model.streaks }
    private var chips: [StreakStrip.Chip] { StreakStrip.chips(own: store.own, pairs: store.pairs) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12 * scale) {
                if let waiting = store.waitingGift { giftBox(waiting.gift) }
                ForEach(chips) { chip in
                    switch chip {
                    case .own(let own): ownChip(own)
                    case .pair(let view): pairChip(view)
                    case .plus(let big): plus(big: big)
                    }
                }
            }
            .padding(.horizontal, 20 * scale)
            .padding(.top, 16 * scale)
            .padding(.bottom, 8 * scale)
        }
        .scrollClipDisabled()
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .defaultScrollAnchor(.center, for: .alignment)
        .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: chips.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.strip")
    }

    // MARK: chips

    private func ownChip(_ own: OwnStreak) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.showTrophies()
        } label: {
            OwnChip(own: own, cat: model.people.owner?.cat ?? 0, scale: scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your streak, \(own.count)", comment: "VoiceOver: Home's own-streak chip; opens the trophy room"))
        .accessibilityValue("\(own.count)|\(own.kept ? 1 : 0)|\(PawBadge.modeName(StreakStrip.mode(own)))")
        .accessibilityIdentifier("home.own")
        .transition(.scale.combined(with: .opacity))
    }

    private func pairChip(_ view: StreakView) -> some View {
        let index = store.pairs.firstIndex { $0.pair == view.pair } ?? 0
        let badge = StreakBadge.make(view, all: store.pairs, signedIn: model.account.isSignedIn, offersSignIn: model.account.offersSignIn)
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.showUs(pair: view.pair)
        } label: {
            PairChip(view: view, scale: scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(view.partner.name), \(view.count)", comment: "VoiceOver: a connection's chip on Home; opens the Us screen"))
        .accessibilityValue(badge.map(PawBadge.value) ?? "")
        // The top pair keeps PR 4's badge id; the rest by position.
        .accessibilityIdentifier(index == 0 ? "home.streak" : "home.pair.\(index)")
        .overlay(alignment: .topTrailing) {
            if index == 0, badge?.offerSignIn == true {
                CloudPlusBubble(size: 34 * scale, action: onCloud)
                    .offset(x: 14 * scale, y: -16 * scale)
                    .accessibilityIdentifier("home.streak.cloud")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // A pounce waiting on you (§12.4): their bell rings on their chip; it opens their pair on Us.
            if view.pounce.waiting != nil {
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    model.showUs(pair: view.pair)
                } label: {
                    Image(ArtName.Habit.pounceBell).resizable().scaledToFit()
                        .frame(width: 34 * scale, height: 34 * scale)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .bounceLoop(active: true)
                .offset(x: 10 * scale, y: 10 * scale)
                .accessibilityLabel(Text("\(view.partner.name) wants to play", comment: "VoiceOver: a pounce waiting on Home"))
                .accessibilityIdentifier("home.pounce")
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func plus(big: Bool) -> some View {
        let side = (big ? 76 : 54) * scale
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.showInvite()
        } label: {
            Image(ArtName.Habit.chipPlus)
                .resizable().scaledToFit()
                .frame(width: side, height: side)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4 * scale)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .bounceLoop(active: StreakStrip.bounces(big: big, band: model.ageBand))
        .accessibilityLabel(Text("Add someone", comment: "VoiceOver: Home's plus; opens the invite sheet"))
        .accessibilityValue(big ? "big" : "small")
        .accessibilityIdentifier("home.add")
        .transition(.scale.combined(with: .opacity))
    }

    private func giftBox(_ gift: StreakView.Gift) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.showUs(openingGift: gift.id)
        } label: {
            Image(ArtName.Habit.giftBox)
                .resizable().scaledToFit()
                .frame(width: 50 * scale, height: 50 * scale)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .bounceLoop(active: true)
        .accessibilityLabel(Text("Open the gift", comment: "VoiceOver: a milestone gift waiting on Home"))
        .accessibilityIdentifier("home.gift")
    }
}

/// Your own streak's chip: your cat on an orange paw with the numeral and its mark (bandage, nap
/// blanket, a fresh sparkle). It glows once today is kept.
struct OwnChip: View {
    let own: OwnStreak
    let cat: Int
    var scale: CGFloat = 1

    var body: some View {
        let mode = StreakStrip.mode(own)
        HStack(spacing: 4 * scale) {
            ZStack(alignment: .bottomTrailing) {
                Image(ArtName.cat(cat, own.count == 0 && own.best > 0 ? .asleep : .idle))
                    .resizable().scaledToFit()
                    .frame(width: 46 * scale, height: 46 * scale)
                Image(own.kept ? ArtName.Habit.pawOne : ArtName.Habit.pawGrey)
                    .resizable().scaledToFit()
                    .frame(width: 20 * scale, height: 20 * scale)
                    .offset(x: 4 * scale, y: 2 * scale)
            }
            OutlinedText(String(own.count), size: 28 * scale, fill: mode == .fresh ? Palette.sky.mix(with: .white, by: 0.5) : .white,
                         width: 3 * scale)
                .contentTransition(.numericText(value: Double(own.count)))
                .fixedSize()
                .overlay(alignment: .topTrailing) { ModeMark(mode: mode, scale: scale).offset(x: 14 * scale, y: -10 * scale) }
                .padding(.trailing, 6 * scale)
        }
        .padding(.leading, 6 * scale)
        .padding(.trailing, 12 * scale)
        .padding(.vertical, 3 * scale)
        .background {
            Capsule()
                .fill(LinearGradient(colors: [Palette.orange.mix(with: .white, by: 0.2), Palette.magenta],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4 * scale))
                .shadow(color: own.kept ? Palette.lime.opacity(0.9) : .clear, radius: 10 * scale)
        }
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4 * scale)
    }
}

/// A connection's chip: their cat leaning on the pair's paw badge, with the same marks.
struct PairChip: View {
    let view: StreakView
    var scale: CGFloat = 1

    var body: some View {
        let badge = StreakBadge(
            count: view.count, me: view.me, them: view.them, kept: view.kept, mode: StreakBadge.mode(view), offerSignIn: false)
        HStack(spacing: -10 * scale) {
            Image(ArtName.cat(view.partner.cat, view.count == 0 && view.best > 0 ? .asleep : .idle))
                .resizable().scaledToFit()
                .frame(width: 46 * scale, height: 46 * scale)
                .background(Circle().fill(Palette.teal).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3 * scale)))
                .zIndex(1)
            PawBadge(badge: badge, scale: 0.86 * scale)
        }
    }
}

/// The mark on a streak numeral: bandage and two dots, suitcase, nap blanket, or a fresh sparkle.
struct ModeMark: View {
    let mode: StreakBadge.Mode
    var scale: CGFloat = 1

    var body: some View {
        switch mode {
        case .normal:
            EmptyView()
        case .winback(let kept):
            VStack(spacing: 2 * scale) {
                Image(ArtName.Habit.pawBandage).resizable().scaledToFit().frame(width: 22 * scale)
                HStack(spacing: 3 * scale) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle().fill(i < kept ? Palette.lime : Palette.night)
                            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5 * scale))
                            .frame(width: 7 * scale, height: 7 * scale)
                    }
                }
            }
        case .paused:
            Image(ArtName.Habit.pawSuitcase).resizable().scaledToFit().frame(width: 22 * scale)
        case .napped:
            Image(ArtName.Habit.pawNap).resizable().scaledToFit().frame(width: 22 * scale)
        case .fresh:
            Image(ArtName.fxSparkle).resizable().scaledToFit().frame(width: 20 * scale)
        }
    }
}
