import PounceKit
import SwiftUI

/// Game over on the TV, over the table: the winners celebrating, everyone's place, and how to
/// play again. A phone's Play again takes the TV to the new table by itself. The web TV's `TvOver`.
struct GameOverView: View {
    let room: RoomView
    @State private var shown = false
    @State private var turn = 0.0

    var body: some View {
        let rows = TVStandings.rows(room)
        let winners = rows.filter(\.won)
        let title = TVStandings.title(room)
        ZStack {
            // The sunburst is bigger than the screen: an overlay, so it never sizes the screen.
            Palette.ink.opacity(0.6)
                .overlay {
                    Image(ArtName.sunburst)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 1500, height: 1500)
                        .rotationEffect(.degrees(turn))
                        .opacity(0.55)
                        .offset(y: -200)
                        .accessibilityHidden(true)
                }
                .clipped()
                .ignoresSafeArea()
            VStack(spacing: 30) {
                VStack(spacing: 18) {
                    HStack(spacing: -24) {
                        ForEach(Array(winners.enumerated()), id: \.element.id) { i, w in
                            Image(ArtName.cat(SeatInfo.catIndex(room.seats[w.seat]), .celebrate))
                                .resizable()
                                .scaledToFit()
                                .frame(width: winners.count > 2 ? 150 : 190, height: winners.count > 2 ? 150 : 190)
                                .scaleEffect(shown ? 1 : 0.01)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(i) * 0.12), value: shown)
                        }
                    }
                    .frame(height: winners.isEmpty ? 0 : (winners.count > 2 ? 150 : 190))
                    OutlinedText(title, size: title.count > 22 ? 64 : 80, fill: Palette.yellow, width: 5)
                        .frame(maxWidth: 1140)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("tv.over.title")
                }
                VStack(spacing: rows.count > 4 ? 10 : 14) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        RankRow(room: room, row: row, place: i + 1, tight: rows.count > 4)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 30)
                            .animation(.easeOut(duration: 0.35).delay(0.24 + Double(i) * 0.09), value: shown)
                    }
                }
                .padding(28)
                .frame(width: 1140)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Palette.night.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(Palette.ink, lineWidth: 6))
                .compositingGroup()
                TVHint(icon: ArtName.Habit.iconPhone, words: String(localized: "Play again on any phone", comment: "TV game over: a phone deals the next game"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            shown = true
            // One slow turn of the sunburst, then still: a still screen draws nothing.
            withAnimation(.easeOut(duration: 4)) { turn = 120 }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One player's place: their number, cat, name and what they finished on.
private struct RankRow: View {
    let room: RoomView
    let row: TVStandings.Row
    let place: Int
    let tight: Bool

    var body: some View {
        let ring = tvRing(row.seat)
        let avatar: CGFloat = tight ? 72 : 86
        let name = SeatInfo.name(room, row.seat)
        HStack(spacing: 24) {
            Text(verbatim: "\(place)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(Palette.ink)
                .frame(width: 62, height: 62)
                .background(Circle().fill(row.won ? Palette.yellow : .white))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
            Image(ArtName.cat(SeatInfo.catIndex(room.seats[row.seat]), row.won ? .celebrate : .idle))
                .resizable()
                .scaledToFit()
                .padding(4)
                .frame(width: avatar, height: avatar)
                .background(Circle().fill(Palette.ink))
                .overlay(Circle().strokeBorder(ring, lineWidth: 6))
            Text(verbatim: name)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: row.detail)
                .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(row.out ? .white.opacity(0.6) : .white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, tight ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(row.won ? ring.opacity(0.55) : Palette.ink.opacity(0.55)))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(row.won ? Palette.yellow : .clear, lineWidth: 4))
        .compositingGroup()
        .opacity(row.out ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place). \(name), \(row.detail)")
    }
}
