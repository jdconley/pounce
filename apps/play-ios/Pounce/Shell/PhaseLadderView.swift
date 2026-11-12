import PounceKit
import SwiftUI

/// All ten phases under the scoreboard: each in plain words, every seat's cat and name on the
/// phase it is working on (a laid badge once it laid it this round), the focus seat's phase lit orange
/// and the phases it has climbed past checked off. Shows what everyone is collecting, for
/// choosing what to discard.
struct PhaseLadderView: View {
    let ladder: PhaseLadder
    let model: TableModel

    var body: some View {
        VStack(spacing: 8) {
            OutlinedText(
                String(localized: "Levels", comment: "Scoreboard: the heading over all ten levels"),
                size: 28, fill: Palette.orange, width: 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(ladder.rungs, id: \.index) { rung in
                row(rung)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("phases")
    }

    private func row(_ rung: PhaseLadder.Rung) -> some View {
        let color = rung.isFocus ? Palette.orange : Palette.violet
        let fill = rung.isDone ? color.mix(with: Palette.ink, by: 0.45) : color
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                badge(rung)
                OutlinedText(rung.text, size: 18, fill: .white, width: 3)
                    .fixedSize()
                Spacer(minLength: 4)
                cats(rung.seats)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    badge(rung)
                    OutlinedText(rung.text, size: 18, fill: .white, width: 3)
                    Spacer(minLength: 0)
                }
                if !rung.seats.isEmpty {
                    cats(rung.seats)
                        .padding(.leading, 48)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [fill.mix(with: .white, by: 0.2), fill, fill.mix(with: Palette.ink, by: 0.25)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Palette.ink, lineWidth: rung.isFocus ? 5 : 4))
        )
        .scaleEffect(rung.isFocus ? 1.03 : 1)
        .zIndex(rung.isFocus ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label(rung)))
        .accessibilityIdentifier("phase.\(rung.index + 1)")
    }

    /// The shelf number on a gold badge; a check on it once the focus seat is past it.
    private func badge(_ rung: PhaseLadder.Rung) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Image(ArtName.shelfBadge)
                    .resizable()
                    .frame(width: 40, height: 40)
                OutlinedText(String(rung.index + 1), size: 18, fill: Palette.orange, width: 3)
                    .offset(y: 2)
            }
            if rung.isDone {
                Image(ArtName.iconCheck)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .offset(x: 8, y: -6)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// The cats on a phase with their names, in seat order, wrapping when they don't fit a line.
    private func cats(_ seats: [Seat]) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 4) {
            ForEach(seats, id: \.self) { seat in
                cat(seat)
            }
        }
    }

    private func cat(_ seat: Seat) -> some View {
        VStack(spacing: -4) {
            catFace(seat)
            NameTag(SeatInfo.name(model.room, seat), maxWidth: 110, active: seat == ladder.focus && model.isMultiSeat)
        }
    }

    private func catFace(_ seat: Seat) -> some View {
        let view = model.room.seats[safe: seat]
        let ring = SeatInfo.ringColor(seat)
        return ZStack(alignment: .bottomTrailing) {
            Image(ArtName.cat(SeatInfo.catIndex(view), .idle))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .background(Circle().fill(ring.mix(with: .white, by: 0.25)))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: seat == ladder.focus ? 4 : 3))
            if ladder.laid.contains(seat) {
                Image(ArtName.badgeLaid).resizable().frame(width: 18, height: 18).offset(x: 4, y: 2)
            } else if view?.kind == .bot {
                Image(ArtName.badgeBot).resizable().frame(width: 18, height: 18).offset(x: 4, y: 2)
            }
        }
    }

    /// "Phase 4: 1 run of 7. Mia and House Cat are here." plus who laid it down this round and
    /// whether it is done or the focus seat's phase.
    private func label(_ rung: PhaseLadder.Rung) -> String {
        let number = rung.index + 1
        var parts = [String(localized: "Level \(number): \(rung.text).", comment: "VoiceOver: a level and what it needs")]
        let names = rung.seats.map { SeatInfo.name(model.room, $0) }
        switch names.count {
        case 0: break
        case 1: parts.append(String(localized: "\(names[0]) is here.", comment: "VoiceOver: one player on this level"))
        default:
            let list = names.formatted(.list(type: .and))
            parts.append(String(localized: "\(list) are here.", comment: "VoiceOver: players on this level"))
        }
        let laid = rung.seats.filter(ladder.laid.contains).map { SeatInfo.name(model.room, $0) }
        if !laid.isEmpty {
            let list = laid.formatted(.list(type: .and))
            parts.append(String(localized: "\(list) laid it down.", comment: "VoiceOver: players who laid this level this round"))
        }
        if rung.isFocus {
            if model.isMultiSeat, let focus = ladder.focus {
                let name = SeatInfo.name(model.room, focus)
                parts.append(String(localized: "\(name)'s level.", comment: "VoiceOver: the shown player's level on a shared phone"))
            } else {
                parts.append(String(localized: "Your level.", comment: "VoiceOver: my current level"))
            }
        } else if rung.isDone {
            parts.append(String(localized: "Done.", comment: "VoiceOver: a level already climbed past"))
        }
        return parts.joined(separator: " ")
    }
}
