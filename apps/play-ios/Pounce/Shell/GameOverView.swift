import PounceKit
import SwiftUI

/// The finished game (spec §5.10), over the table once its win moment has played: the table's
/// name up top, the winners' cats in the celebrate pose on a sunburst, a crown dropping onto each
/// (shared wins show every winner), everyone's final standing (cat, name, score) under it, a
/// one-shot confetti fall, and two pills: Home and New game. No words but the table's and the
/// players' names, and one short line when the server ended the game early because the rest of
/// the hand couldn't change the result. Every motion here runs once and stops, so nothing loops.
struct GameOverView: View {
    let tableName: String
    let winners: [Person]
    /// Every seat, best first: phase reached, then lowest score.
    var standings: [Standing] = []
    /// Why the game ended early, if it did: shown as one line under the standings.
    var endReason: GameEndReason? = nil
    let onHome: () -> Void
    let onNewGame: () -> Void
    /// Play again (§10.4): nil on a server without it.
    var again: Again? = nil
    var onPlayAgain: () -> Void = {}

    enum Again: Equatable {
        /// Deal the same people a new game.
        case ask
        /// Asked; the deal is on its way.
        case waiting
        /// Someone dealt it: jump to that table.
        case go
    }

    struct Standing: Identifiable {
        let seat: Seat
        let name: String
        let cat: Int
        let phase: Int
        let score: Int
        var id: Seat { seat }
    }

    /// The person id a House Cat bot wins under (the gray cat with the bot badge).
    static let botID = "bot"

    /// The House Cat bot at `seat` as a winner, under its table name.
    static func botWinner(name: String) -> Person {
        Person(id: botID, name: name, cat: SeatInfo.botCat)
    }

    /// Every seat of a finished table, best first.
    static func standings(_ model: TableModel) -> [Standing] {
        guard let game = model.game else { return [] }
        let names = SeatInfo.names(model.room)
        return game.phase.indices.map { seat in
            Standing(
                seat: seat, name: names[safe: seat] ?? "", cat: SeatInfo.catIndex(model.room.seats[safe: seat]),
                phase: game.phase[seat], score: game.scores[safe: seat] ?? 0)
        }
        .sorted { ($0.phase, -$0.score, -$0.seat) > ($1.phase, -$1.score, -$1.seat) }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var appeared = false
    @State private var crowned = false
    @State private var turned = false

    /// Bigger winners and sunburst on a roomy (regular-width) screen.
    private var scale: CGFloat { sizeClass == .regular ? 1.35 : 1 }

    private var catSize: CGFloat {
        let base: CGFloat = switch winners.count {
        case 0, 1: 170
        case 2: 130
        default: 96
        }
        return base * scale
    }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.78)
                .ignoresSafeArea()
            ConfettiFall(count: reduceMotion ? 10 : 36)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if sizeClass == .regular {
                roomy
            } else {
                phone
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.4).paced) { appeared = true }
            withAnimation(reduceMotion ? .easeIn(duration: 0.2).paced : .spring(duration: 0.5, bounce: 0.5).delay(0.35).paced) {
                crowned = true
            }
            if !reduceMotion {
                withAnimation(.easeOut(duration: CelebrationTiming.sunburstLoop).paced) { turned = true }
            }
            Sound.shared.play(ArtName.Sound.sfxPop)
            Haptics.shared.success()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-gameover")
    }

    private var phone: some View {
        VStack(spacing: 30) {
            title
            Spacer(minLength: 0)
            ZStack {
                Image(ArtName.sunburst)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 420, height: 420)
                    .rotationEffect(.degrees(turned ? -90 : 0))
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    ForEach(Array(winners.enumerated()), id: \.offset) { _, winner in
                        WinnerCat(person: winner, size: catSize, crowned: crowned, reduceMotion: reduceMotion)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
            }
            .frame(height: standings.isEmpty ? 360 : 300)
            if !standings.isEmpty {
                standingsFlow
                    // The sunburst is wider than a small phone: wrap to the screen, not to it.
                    .containerRelativeFrame(.horizontal) { width, _ in width - 32 }
            }
            endNote
            Spacer()
            pills
                .padding(.bottom, 36)
        }
    }

    /// A regular-width window. Wide: the winners on a bigger sunburst on the left; the table's
    /// name, everyone's standing (one per line, best first) and the pills on the right. Tall:
    /// the phone's column with everything bigger and the standings capped to a readable width.
    private var roomy: some View {
        GeometryReader { geo in
            if Roomy.sideBySide(geo.size) {
                HStack(spacing: 40) {
                    winnersStage(height: min(geo.size.height * 0.7, 560))
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 28) {
                        title
                        if !standings.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(standings) { standing($0) }
                            }
                            .opacity(appeared ? 1 : 0)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("gameover.standings")
                        }
                        endNote
                        pills
                    }
                    .frame(width: min(geo.size.width * 0.4, 480))
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 34) {
                    title
                    Spacer(minLength: 0)
                    winnersStage(height: standings.isEmpty ? 520 : 440)
                    if !standings.isEmpty {
                        standingsFlow
                            .frame(maxWidth: 640)
                    }
                    endNote
                    Spacer()
                    pills
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var title: some View {
        OutlinedText(tableName, size: 30 * (sizeClass == .regular ? 1.25 : 1), fill: .white, width: 3, lines: 2)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .accessibilityIdentifier("gameover.name")
    }

    /// The sunburst with the winners on it (roomy).
    private func winnersStage(height: CGFloat) -> some View {
        ZStack {
            Image(ArtName.sunburst)
                .resizable()
                .scaledToFit()
                .frame(width: 420 * scale, height: 420 * scale)
                .rotationEffect(.degrees(turned ? -90 : 0))
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(Array(winners.enumerated()), id: \.offset) { _, winner in
                    WinnerCat(person: winner, size: catSize, crowned: crowned, reduceMotion: reduceMotion)
                }
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
        }
        .frame(height: height)
    }

    /// The early-end line: why the game stopped before the hand was played out.
    @ViewBuilder private var endNote: some View {
        if let text = Self.endNote(endReason) {
            OutlinedText(text, size: 22 * (sizeClass == .regular ? 1.2 : 1), fill: Palette.lime, width: 3, lines: 2)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .accessibilityIdentifier("gameover.reason")
        }
    }

    /// The line for an early end, or nil for a game that ended the usual way.
    static func endNote(_ reason: GameEndReason?) -> String? {
        switch reason {
        case .decided:
            String(
                localized: "The rest of the hand couldn't change the result.",
                comment: "Game over: the game ended early because no one could still change a finishing place")
        case nil:
            nil
        }
    }

    private var standingsFlow: some View {
        FlowLayout(spacing: 8 * scale, lineSpacing: 8 * scale) {
            ForEach(standings) { standing($0) }
        }
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gameover.standings")
    }

    private var pills: some View {
        VStack(spacing: 16) {
            if let again {
                PillButton(
                    icon: ArtName.Habit.iconReplay, color: Palette.lime, size: .large, width: 230,
                    accessibilityLabel: "Play again"
                ) {
                    onPlayAgain()
                }
                .opacity(again == .waiting ? 0.7 : 1)
                .overlay { if again == .waiting { YarnIndicator() } }
                .bounceLoop(active: again == .go)
                .accessibilityIdentifier("gameover.again")
            }
            homeAndNew
        }
        .offset(y: appeared ? 0 : 160)
    }

    private var homeAndNew: some View {
        HStack(spacing: 18) {
            PillButton(
                icon: ArtName.iconHome, color: Palette.orange, size: .large, width: 176,
                title: String(localized: "Home", comment: "Game over: the pill back to Home"),
                accessibilityLabel: "Home"
            ) {
                onHome()
            }
            .accessibilityIdentifier("gameover.home")
            PillButton(
                icon: ArtName.iconPlus, color: Palette.magenta, size: .large, width: 176,
                title: String(localized: "Create", comment: "Game over: the pill that starts a new game"),
                accessibilityLabel: "Create a game"
            ) {
                onNewGame()
            }
            .accessibilityIdentifier("gameover.new")
        }
    }

    /// One seat's final line: cat, name, score.
    private func standing(_ s: Standing) -> some View {
        HStack(spacing: 6 * scale) {
            Image(ArtName.cat(s.cat, .idle))
                .resizable()
                .scaledToFit()
                .frame(width: 34 * scale, height: 34 * scale)
                .background(Circle().fill(SeatInfo.ringColor(s.seat).mix(with: .white, by: 0.25)))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
            NameTag(s.name, maxWidth: 110 * scale, size: sizeClass == .regular ? 20 : 16)
            OutlinedText(String(s.score), size: 20 * scale, fill: .white, width: 3)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(s.name), phase \(min(s.phase + 1, 10)), \(s.score) points",
            comment: "VoiceOver: a player's final standing on the game over screen"))
        .accessibilityIdentifier("gameover.standing.\(s.seat)")
    }
}

/// One winner: cat in the celebrate pose, the crown dropping onto its head, the name.
private struct WinnerCat: View {
    let person: Person
    let size: CGFloat
    let crowned: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                Image(ArtName.cat(person.cat, .celebrate))
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: Palette.ink.opacity(0.45), radius: 0, x: 0, y: 6)
                Image(ArtName.crown)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.5)
                    .rotationEffect(.degrees(-8))
                    .offset(y: crowned ? -size * 0.2 : (reduceMotion ? -size * 0.2 : -size * 1.4))
                    .opacity(crowned ? 1 : 0)
            }
            HStack(spacing: 6) {
                if person.id == GameOverView.botID {
                    Image(ArtName.badgeBot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }
                NameTag(person.name, maxWidth: max(size * 1.3, 120), size: size > 120 ? 30 : 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(person.name) wins",
            comment: "VoiceOver: a game winner"))
        .accessibilityIdentifier("gameover.winner")
    }
}

/// A one-shot shower of confetti, stars and yarn bits from above the screen to below it.
/// Each piece animates once; when they have all fallen there is nothing left to draw.
private struct ConfettiFall: View {
    let count: Int
    @State private var fallen = false

    private struct Piece {
        let art: String
        let x: CGFloat
        let size: CGFloat
        let spin: Double
        let duration: Double
        let delay: Double
        let drift: CGFloat
    }

    @State private var pieces: [Piece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces.indices, id: \.self) { i in
                    let p = pieces[i]
                    Image(p.art)
                        .resizable()
                        .scaledToFit()
                        .frame(width: p.size, height: p.size)
                        .rotationEffect(.degrees(fallen ? p.spin : 0))
                        .position(
                            x: p.x * geo.size.width + (fallen ? p.drift : 0),
                            y: fallen ? geo.size.height + 60 : -40)
                        .animation(.easeIn(duration: p.duration).delay(p.delay).paced, value: fallen)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            let arts = [ArtName.fxConfetti, ArtName.fxConfetti, ArtName.fxStar, ArtName.fxYarn, ArtName.fxSparkle]
            pieces = (0..<count).map { i in
                Piece(
                    art: arts[i % arts.count], x: CGFloat.random(in: 0.04...0.96), size: CGFloat.random(in: 16...30),
                    spin: Double.random(in: -540...540), duration: Double.random(in: 1.8...2.8),
                    delay: Double.random(in: 0...0.7), drift: CGFloat.random(in: -50...50))
            }
            Task { @MainActor in
                try? await Task.sleep(for: Pace.duration(.milliseconds(30)))
                fallen = true
            }
        }
    }
}

/// The scoreboard (spec §5.7): opened by tapping the tower. Every seat's cat in its ring,
/// its phase on a gold shelf badge and its score, numbers only; under them all ten phases
/// with everyone's cat on theirs (`PhaseLadderView`), lit for `focus`. It scrolls when it
/// doesn't fit. Tap anywhere to close.
struct ScoreboardOverlay: View {
    let model: TableModel
    /// The seat whose phase is lit: the one this phone shows (whoever is up or revealed).
    let focus: Seat?
    let onClose: () -> Void

    @State private var appeared = false

    private var rows: [Seat] { model.game.map { Array($0.phase.indices) } ?? [] }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.85)
                .ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    if sizeClass == .regular && Roomy.sideBySide(geo.size) {
                        // Wide: the scores on the left, the ten phases beside them.
                        HStack(alignment: .top, spacing: 28) {
                            VStack(spacing: 12) { seatRows }
                                .frame(maxWidth: 460)
                                .padding(.top, 52)
                            ladder
                                .frame(maxWidth: 600)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    } else {
                        VStack(spacing: 10) {
                            seatRows
                            ladder
                                .padding(.top, 16)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        // A tall iPad: a readable column, not edge to edge.
                        .frame(maxWidth: sizeClass == .regular ? 680 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .onAppear {
            appeared = true
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("scoreboard")
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder private var seatRows: some View {
        ForEach(Array(rows.enumerated()), id: \.element) { i, seat in
            row(seat)
                .offset(x: appeared ? 0 : (i.isMultiple(of: 2) ? -420 : 420))
                .animation(.spring(duration: 0.4, bounce: 0.3).delay(Double(i) * 0.04).paced, value: appeared)
        }
    }

    private var ladder: some View {
        PhaseLadderView(ladder: PhaseLadder(model: model, focus: focus), model: model)
            .offset(y: appeared ? 0 : 120)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(duration: 0.45, bounce: 0.2).delay(0.12).paced, value: appeared)
    }

    private func isTurn(_ seat: Seat) -> Bool {
        model.game?.status == .playing && model.game?.turn == seat
    }

    private func row(_ seat: Seat) -> some View {
        let view = model.room.seats[safe: seat]
        let phase = model.game?.phase[safe: seat] ?? 0
        let score = model.game?.scores[safe: seat] ?? 0
        let ring = SeatInfo.ringColor(seat)
        return HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(ArtName.cat(SeatInfo.catIndex(view), .idle))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(ring.mix(with: .white, by: 0.25)))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                if view?.kind == .bot {
                    Image(ArtName.badgeBot).resizable().frame(width: 22, height: 22).offset(x: 6, y: -4)
                }
                if model.game?.winners.contains(seat) == true {
                    Image(ArtName.crown).resizable().scaledToFit().frame(width: 30).offset(x: -10, y: -14)
                }
            }
            ZStack {
                Image(ArtName.shelfBadge)
                    .resizable()
                    .frame(width: 44, height: 44)
                if phase >= TableLayout.shelfCount {
                    Image(ArtName.iconTrophy).resizable().scaledToFit().frame(width: 24, height: 24).offset(y: 3)
                } else {
                    OutlinedText(String(phase + 1), size: 20, fill: Palette.orange, width: 3)
                        .offset(y: 3)
                }
            }
            NameTag(SeatInfo.name(model.room, seat), maxWidth: 160, active: isTurn(seat), size: 20)
            Spacer(minLength: 8)
            OutlinedText(String(score), size: 32, fill: .white, width: 4)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(LinearGradient(
                    colors: [ring.mix(with: .white, by: 0.2), ring, ring.mix(with: Palette.ink, by: 0.25)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(SeatInfo.name(model.room, seat)), phase \(min(phase + 1, 10)), \(score) points",
            comment: "VoiceOver: a scoreboard row"))
        .accessibilityIdentifier("scoreboard.\(seat)")
    }
}
