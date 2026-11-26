import PounceKit
import SwiftUI

/// Bidding (design §5.3): one big number on the cat's sign, "+5" (hold it to raise faster), Bid and
/// Pass. The number starts at the least bid the server allows and never passes the most; a tap on
/// it goes back to the least.
struct BirdBidPanel: View {
    let range: BirdBidRange
    let onBid: (Int) -> Void
    let onPass: () -> Void

    @State private var amount: Int?
    @State private var repeating: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var type

    private var shown: Int { min(max(amount ?? range.min, range.min), range.max) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Haptics.shared.tick()
                    amount = range.min
                } label: {
                    OutlinedText(String(shown), size: 54, fill: .white, width: 5)
                        .contentTransition(.numericText(value: Double(shown)))
                        .frame(width: 128, height: 76)
                        .background(BirdBoard(fill: Palette.orange))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Bid \(shown)", comment: "Birdwatch VoiceOver: the bid to send"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: raise()
                    case .decrement: amount = max(shown - range.step, range.min)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("bird.bid.amount")
                PillButton(icon: nil, color: Palette.teal, size: .medium, width: 76, title: "+\(range.step)",
                           accessibilityLabel: "Raise 5") { raise() }
                    .disabled(shown >= range.max)
                    .groupOpacity(shown >= range.max ? 0.6 : 1)
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in startRepeating() })
                    .accessibilityIdentifier("bird.bid.raise")
            }
            HStack(spacing: 8) {
                PillButton(icon: nil, color: Palette.orange, size: .medium, width: 102,
                           title: String(localized: "Bid", comment: "Birdwatch: send the bid"), accessibilityLabel: "Bid") {
                    stopRepeating()
                    onBid(shown)
                }
                .accessibilityIdentifier("bird.bid.send")
                PillButton(icon: nil, color: Palette.violet, size: .medium, width: 102,
                           title: String(localized: "Pass", comment: "Birdwatch: pass in the bidding"), accessibilityLabel: "Pass") {
                    stopRepeating()
                    onPass()
                }
                .accessibilityIdentifier("bird.bid.pass")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onChange(of: range) { _, _ in amount = nil }
        .onDisappear(perform: stopRepeating)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.panel.bid")
    }

    private func raise() {
        guard shown < range.max else { return }
        withAnimation(.snappy(duration: 0.15).paced) { amount = min(shown + range.step, range.max) }
    }

    private func startRepeating() {
        stopRepeating()
        repeating = Task {
            while !Task.isCancelled, shown < range.max {
                raise()
                Haptics.shared.tick()
                try? await Task.sleep(for: Pace.duration(.milliseconds(150)))
            }
        }
    }

    private func stopRepeating() {
        repeating?.cancel()
        repeating = nil
    }
}

/// The nest's put-back (design §5.3): the feeder's cards glow in the hand; the bar says how many
/// are marked, and Done lights at the right count.
struct BirdNestBar: View {
    let count: Int
    let marked: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(ArtName.Bird.feeder).resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                OutlinedText(String(localized: "Put back \(count)", comment: "Birdwatch: the bid winner puts this many cards back"),
                             size: 22, width: 3)
                OutlinedText("\(marked)/\(count)", size: 22, fill: marked == count ? Palette.lime : Palette.yellow, width: 3)
                    .contentTransition(.numericText(value: Double(marked)))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Put back \(count). \(marked) marked.", comment: "Birdwatch VoiceOver: the put-back bar"))
            PillButton(icon: ArtName.iconCheck, color: marked == count ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.4),
                       size: .medium, width: 150, title: String(localized: "Done", comment: "Birdwatch: finish putting cards back"),
                       accessibilityLabel: "Done") {
                if marked == count { onDone() }
            }
            .groupOpacity(marked == count ? 1 : 0.75)
            .accessibilityIdentifier("bird.nest.done")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.panel.nest")
    }
}

/// Naming trump (design §5.3): four big toy buttons, the one this hand holds most of ringed.
struct BirdTrumpPanel: View {
    let hint: BirdSuit?
    let onPick: (BirdSuit) -> Void
    /// The room the panel has (the sill): four in a row when wide enough, else two by two.
    var room = CGSize(width: 360, height: 260)

    var body: some View {
        let row = min((room.width - 30) / 4, 96)
        let grid = min((room.height - 56) / 2 - 8, 96)
        let wide = row >= 62 && (room.height < 2 * grid + 64 || row >= grid)
        let side = max(wide ? row : grid, 56)
        VStack(spacing: 8) {
            OutlinedText(String(localized: "Name trump", comment: "Birdwatch: the bid winner picks the trump suit"), size: 22, width: 3)
            if wide {
                HStack(spacing: 8) { buttons(side) }
            } else {
                LazyVGrid(columns: [GridItem(.fixed(side + 6)), GridItem(.fixed(side + 6))], spacing: 8) { buttons(side) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.panel.trump")
    }

    @ViewBuilder private func buttons(_ side: CGFloat) -> some View {
        ForEach(BirdSuit.allCases, id: \.self) { suit in
            Button {
                Haptics.shared.success()
                onPick(suit)
            } label: {
                VStack(spacing: 0) {
                    Image(ArtName.Tiles.glyph(suit)).resizable().scaledToFit().frame(width: side * 0.52, height: side * 0.52)
                    OutlinedText(BirdTableModel.suitName(suit).capitalized, size: max(13, side * 0.18), width: 2.5)
                }
                .frame(width: side, height: side * 0.92)
                .background(BirdBoard(fill: Color(TilePieceFactory.color(suit)), corner: 18))
                .overlay {
                    if suit == hint {
                        RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.yellow, lineWidth: 5)
                            .padding(-5)
                            .shadow(color: Palette.yellow.opacity(0.9), radius: 8)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(BirdTableModel.suitName(suit)))
            .accessibilityHint(suit == hint ? Text("You hold the most", comment: "Birdwatch VoiceOver: the trump hint") : Text(""))
            .accessibilityIdentifier("bird.trump.\(suit.rawValue)")
        }
    }
}

/// Calling a partner (five players, design §5.3): every card the bid winner doesn't hold, a row
/// per suit with trump's row first. One tap calls it.
struct BirdPartnerPicker: View {
    let choices: [BirdCardID]
    let trump: BirdSuit?
    let onCall: (BirdCardID) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let width: CGFloat = sizeClass == .regular ? 70 : 52
        VStack(spacing: 12) {
            OutlinedText(String(localized: "Call a partner", comment: "Birdwatch: the bid winner calls a card; its holder is their partner"),
                         size: 26, fill: Palette.orange, width: 4)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            OutlinedText(String(localized: "Who holds it plays with you.", comment: "Birdwatch: under the partner picker's title"), size: 16, lines: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(BirdTableModel.partnerRows(choices, trump: trump).enumerated()), id: \.offset) { _, row in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(row.cards, id: \.self) { card in
                                    Button {
                                        Haptics.shared.success()
                                        onCall(card)
                                    } label: {
                                        Image(uiImage: BirdCardFactory.shared.image(card))
                                            .resizable()
                                            .frame(width: width, height: width * BirdLayout.cardAspect)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(BirdTableModel.label(card)))
                                    .accessibilityIdentifier("bird.partner.\(card)")
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.night.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.panel.partner")
    }
}

/// Someone else is choosing: one short line on the sill ("Mia is bidding").
struct BirdWaitingLine: View {
    let phase: BirdPhase
    let name: String

    var text: String {
        switch phase {
        case .bidding: String(localized: "\(name) is bidding", comment: "Birdwatch: another seat's bid is up")
        case .nest: String(localized: "\(name) takes the feeder", comment: "Birdwatch: the bid winner is putting cards back")
        case .trump: String(localized: "\(name) names trump", comment: "Birdwatch: the bid winner is picking trump")
        case .partner: String(localized: "\(name) calls a partner", comment: "Birdwatch: the bid winner is calling a partner (five players)")
        default: ""
        }
    }

    var body: some View {
        OutlinedText(text, size: 18, width: 3, lines: 2)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.ink.opacity(0.7)))
            .accessibilityIdentifier("bird.waiting")
    }
}

/// A chunky board in the table's style: an ink rim, the fill lit from the top, a hard shadow.
struct BirdBoard: View {
    let fill: Color
    var corner: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [fill.mix(with: .white, by: 0.25), fill], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
    }
}
