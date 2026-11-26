import PounceKit
import SwiftUI

/// A side's cats, overlapping, with its ribbon under them.
struct BirdSideCats: View {
    let side: BirdTableModel.Side
    let room: RoomView
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(side.seats, id: \.self) { seat in
                Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: seat]), .idle))
                    .resizable().scaledToFit().frame(width: size, height: size)
            }
        }
        .overlay(alignment: .bottom) {
            if let ribbon = side.ribbon {
                Capsule().fill(BirdArt.ribbonColor(ribbon)).frame(height: 5).offset(y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Between hands (design §5.4): the bid, made or missed, each side's points this hand and the
/// running totals. The next hand deals itself; a tap puts the card away sooner.
struct BirdSummary: View {
    let result: BirdHandResult
    let model: BirdTableModel
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let room = model.room
        let bidder = SeatInfo.name(room, result.bidder)
        ViewThatFits(in: .vertical) {
            card(cat: 40)
            ScrollView { card(cat: 32) }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 460)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
        .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.35).paced) { appeared = true } }
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double tap to close", comment: "Birdwatch VoiceOver hint: the hand summary"))
        .accessibilityIdentifier("bird.summary")
        .accessibilityLabel(Text(verbatim: summaryWords(bidder: bidder)))
    }

    private func summaryWords(bidder: String) -> String {
        let made = result.made
            ? String(localized: "\(bidder) made \(result.bid)", comment: "Birdwatch VoiceOver: the hand's bid was made")
            : String(localized: "\(bidder) missed \(result.bid)", comment: "Birdwatch VoiceOver: the hand's bid was missed")
        let sides = model.sides.map { side in
            "\(BirdWords.side(side, room: model.room)) \(BirdWords.signed(result.change[safe: side.index] ?? 0)), \(result.totals[safe: side.index] ?? 0)"
        }
        return ([made] + sides).joined(separator: ". ")
    }

    private func card(cat: CGFloat) -> some View {
        let room = model.room
        return VStack(spacing: 10) {
            OutlinedText(String(localized: "Hand \(result.hand)", comment: "Birdwatch: the summary's title, the hand's number"), size: 20, width: 3)
            HStack(spacing: 8) {
                Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: result.bidder]), result.made ? .celebrate : .asleep))
                    .resizable().scaledToFit().frame(width: cat * 1.3, height: cat * 1.3)
                VStack(alignment: .leading, spacing: 2) {
                    OutlinedText(String(localized: "\(SeatInfo.name(room, result.bidder)) bid \(result.bid)", comment: "Birdwatch summary: who bid what"),
                                 size: 20, width: 3, alignment: .leading)
                    OutlinedText(result.made
                                 ? String(localized: "Made it!", comment: "Birdwatch summary: the bid was made")
                                 : String(localized: "Missed", comment: "Birdwatch summary: the bid was missed"),
                                 size: 26, fill: result.made ? Palette.lime : Palette.refuse, width: 4, alignment: .leading)
                }
                Image(ArtName.Tiles.glyph(result.trump)).resizable().scaledToFit().frame(width: 32, height: 32)
                    .padding(6).background(Circle().fill(Color(TilePieceFactory.color(result.trump))).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3)))
            }
            VStack(spacing: 6) {
                ForEach(model.sides, id: \.index) { side in
                    HStack(spacing: 8) {
                        BirdSideCats(side: side, room: room, size: cat)
                        OutlinedText(BirdWords.side(side, room: room), size: 17, width: 2.5, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let change = result.change[safe: side.index] ?? 0
                        OutlinedText(BirdWords.signed(change), size: 20, fill: change < 0 ? Palette.refuse : Palette.lime, width: 3)
                        OutlinedText("\(result.totals[safe: side.index] ?? 0)", size: 22, width: 3)
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.ink.opacity(0.5)))
        }
        .padding(18)
        .background(BirdBoard(fill: Palette.night, corner: 26))
    }
}

/// The score sheet: every hand so far, a row each, under the sides' totals.
struct BirdScoreSheet: View {
    let model: BirdTableModel
    let onClose: () -> Void

    var body: some View {
        let room = model.room
        VStack(spacing: 12) {
            HStack {
                Color.clear.frame(width: SheetBar.side, height: 1)
                Spacer(minLength: 0)
                OutlinedText(String(localized: "Scores", comment: "Birdwatch: the score sheet's title"), size: 26, fill: Palette.orange, width: 4)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                SheetCloseButton(action: onClose).accessibilityIdentifier("bird.scores.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            OutlinedText(String(localized: "\(BirdWords.rules(model.view.rules)), to \(model.view.target)", comment: "Birdwatch score sheet: the rule set and the target score"),
                         size: 16, width: 2.5)
            // The sides, their totals.
            HStack(spacing: 8) {
                ForEach(model.sides, id: \.index) { side in
                    VStack(spacing: 4) {
                        BirdSideCats(side: side, room: room, size: 30)
                        OutlinedText("\(side.score)", size: 22, width: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(BirdWords.side(side, room: room)), \(side.score)"))
                }
            }
            .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 6) {
                    if model.view.history.isEmpty {
                        OutlinedText(String(localized: "No hands yet.", comment: "Birdwatch score sheet: before the first hand ends"), size: 17, width: 2.5)
                            .padding(.top, 20)
                    }
                    ForEach(model.view.history.reversed(), id: \.hand) { hand in
                        row(hand)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Palette.night.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.scores")
    }

    private func row(_ hand: BirdHandResult) -> some View {
        let room = model.room
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                OutlinedText("\(hand.hand)", size: 16, fill: Palette.yellow, width: 2.5).frame(width: 26)
                Image(ArtName.Tiles.glyph(hand.trump)).resizable().scaledToFit().frame(width: 20, height: 20)
                    .padding(3).background(Circle().fill(Color(TilePieceFactory.color(hand.trump))))
                OutlinedText(String(localized: "\(SeatInfo.name(room, hand.bidder)) \(hand.bid)", comment: "Birdwatch score sheet: who bid what"),
                             size: 16, width: 2.5, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OutlinedText(hand.made ? String(localized: "Made", comment: "Birdwatch score sheet: bid made") : String(localized: "Missed", comment: "Birdwatch score sheet: bid missed"),
                             size: 16, fill: hand.made ? Palette.lime : Palette.refuse, width: 2.5)
            }
            HStack(spacing: 8) {
                ForEach(model.sides, id: \.index) { side in
                    let change = hand.change[safe: side.index] ?? 0
                    VStack(spacing: 0) {
                        OutlinedText(BirdWords.signed(change), size: 15, fill: change < 0 ? Palette.refuse : .white, width: 2)
                        OutlinedText("\(hand.totals[safe: side.index] ?? 0)", size: 17, width: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rowWords(hand)))
    }

    private func rowWords(_ hand: BirdHandResult) -> String {
        let room = model.room
        let head = hand.made
            ? String(localized: "Hand \(hand.hand), \(SeatInfo.name(room, hand.bidder)) made \(hand.bid)", comment: "Birdwatch VoiceOver: a score sheet row")
            : String(localized: "Hand \(hand.hand), \(SeatInfo.name(room, hand.bidder)) missed \(hand.bid)", comment: "Birdwatch VoiceOver: a score sheet row")
        let sides = model.sides.map { "\(BirdWords.side($0, room: room)) \(hand.totals[safe: $0.index] ?? 0)" }
        return ([head] + sides).joined(separator: ", ")
    }
}

/// The finished game: the winning side's cats, every side's total, Play again and Home.
struct BirdOverView: View {
    enum Again: Equatable { case ask, waiting, go, off }

    let model: BirdTableModel
    let winners: [Seat]
    var again: Again?
    var onPlayAgain: () -> Void = {}
    let onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    static var offWords: String {
        String(localized: "This game is off for now.", comment: "Birdwatch game over: Play again was refused because the server stopped dealing this game")
    }

    private var title: String {
        if winners.isEmpty { return String(localized: "Game over", comment: "Birdwatch game over: nobody won (everyone left)") }
        let names = winners.map { SeatInfo.name(model.room, $0) }.formatted(.list(type: .and))
        return winners.count > 1
            ? String(localized: "\(names) win!", comment: "Game over title: a shared win")
            : String(localized: "\(names) wins!", comment: "Game over title")
    }

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.72).ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                column(cat: 130, vertical: 28)
                column(cat: 84, vertical: 14)
                ScrollView { column(cat: 84, vertical: 14) }
            }
        }
        .onAppear {
            Sound.shared.play(ArtName.Sound.sfxFanfare, kind: .game)
            Haptics.shared.celebrate()
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-bird-over")
    }

    private func column(cat: CGFloat, vertical: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: -18) {
                ForEach(winners, id: \.self) { seat in
                    Image(ArtName.cat(SeatInfo.catIndex(model.room.seats[safe: seat]), .celebrate))
                        .resizable().scaledToFit().frame(width: cat, height: cat)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .accessibilityHidden(true)
            OutlinedText(title, size: 36, fill: Palette.orange, width: 5, lines: 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("bird.over.title")
            if model.view.endReason == .left {
                OutlinedText(String(localized: "Everyone left.", comment: "Birdwatch game over: every person left"), size: 18, lines: 2)
            }
            VStack(spacing: 8) {
                ForEach(Array(model.standings.enumerated()), id: \.element.index) { place, side in
                    HStack(spacing: 10) {
                        OutlinedText("\(place + 1)", size: 24, fill: place == 0 ? Palette.orange : .white).frame(width: 30)
                        BirdSideCats(side: side, room: model.room, size: 40)
                        OutlinedText(BirdWords.side(side, room: model.room), size: 18, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        OutlinedText("\(side.score)", size: 24, fill: side.score < 0 ? Palette.refuse : .white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(place + 1). \(BirdWords.side(side, room: model.room)), \(side.score)"))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.night).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.ink, lineWidth: 4)))
            if again == .off {
                OutlinedText(Self.offWords, size: 17, fill: Palette.orange, lines: 3)
            }
            HStack(spacing: 14) {
                if let again, again != .off {
                    PillButton(
                        icon: ArtName.iconPlay, color: again == .waiting ? Palette.violet : Palette.orange, size: .medium, width: 210,
                        title: again == .go
                            ? String(localized: "Join", comment: "Game over: someone dealt the next table; join it")
                            : again == .waiting
                                ? String(localized: "Dealing…", comment: "Game over: Play again was asked and the server hasn't answered")
                                : String(localized: "Play again", comment: "Game over: deal a new table with the same players"),
                        accessibilityLabel: again == .go ? "Join the new game" : "Play again", action: onPlayAgain)
                        .accessibilityIdentifier("bird.over.again")
                    PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: 84, accessibilityLabel: "Home", action: onHome)
                        .accessibilityIdentifier("bird.over.home")
                } else {
                    PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: 200,
                               title: String(localized: "Home", comment: "Game over: go home"), accessibilityLabel: "Home", action: onHome)
                        .accessibilityIdentifier("bird.over.home")
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, vertical)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}
