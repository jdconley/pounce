import PounceKit
import SwiftUI

/// One table on Home: its game on a tab at the top, its name, who you're playing with, the seats as
/// pips, and its code only while it waits for players (a started game can't be joined by code).
/// Your-turn cards glow orange and bounce with the waiting player's cat awake; the rest are
/// dimmed with the current player's cat. Finished games carry a trophy.
struct TableCard: View {
    let item: HomeTableItem
    /// Everyone at the table but you (`AppModel.tablePeople`): your own people on name pills.
    var people = TablePeople.Line(faces: [])
    /// Home's `home.table.<code>`; the Archived sheet uses its own.
    var identifier: String?
    /// Your turn here would keep today for a streak (§10.1): a small paw on the corner.
    var streakPaw = false
    let action: () -> Void

    static let size = CGSize(width: 132, height: 180)

    private var isOver: Bool { item.status == RoomStatus.over.rawValue }
    private var isLobby: Bool { item.status == RoomStatus.lobby.rawValue }
    private var game: GameCatalog.Entry? { GameCatalog.entry(id: item.game) }

    /// Whose cat to show: the player on turn, else this phone's seat, else the first seat with a cat.
    private var shownCat: Int? {
        item.turnCat ?? item.seats.first(where: { $0.yours && $0.cat != nil })?.cat
            ?? item.seats.compactMap(\.cat).first
    }

    private var pose: CatPose {
        if isOver { return .celebrate }
        return item.yourTurn ? .awake : .idle
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            ZStack {
                shape.fill(fill)
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        cat
                        if isOver {
                            Image(ArtName.iconTrophy)
                                .resizable().scaledToFit()
                                .frame(width: 32, height: 32)
                                .offset(x: 6, y: -4)
                        }
                    }
                    .frame(height: 66)
                    OutlinedText(item.title, size: 15, fill: .white, width: 2, lines: 2)
                        .frame(height: 40)
                        .padding(.horizontal, 6)
                    PeopleLine(line: people)
                        .frame(height: 20)
                        .padding(.horizontal, 7)
                    if let idleText {
                        // A game that has waited a day or more says so where its code sits.
                        Text(idleText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 6)
                            .accessibilityIdentifier("home.table.\(item.id).idle")
                    } else if isLobby {
                        // Still gathering players: the code is how they join.
                        Text(verbatim: item.id)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    SeatPips(seats: item.seats)
                }
                .padding(.vertical, 8)
            }
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
            .overlay(alignment: .topTrailing) { gameTab }
            .overlay(alignment: .topLeading) {
                if streakPaw {
                    Image(ArtName.Habit.pawOne)
                        .resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(5)
                        .background(Circle().fill(Palette.violet).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3)))
                        .offset(x: -10, y: -10)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if item.yourTurn {
                    shape.strokeBorder(.white.opacity(0.85), lineWidth: 2).padding(6)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            // One shadow for the whole card, not one under each word on it.
            .compositingGroup()
            .shadow(
                color: item.yourTurn ? Palette.orange.opacity(0.95) : Palette.ink.opacity(0.5),
                radius: item.yourTurn ? 14 : 0, x: 0, y: item.yourTurn ? 0 : 5)
            .saturation(item.yourTurn ? 1 : 0.75)
            .brightness(item.yourTurn || isOver ? 0 : -0.1)
            // Reduce Motion's bounce is a fade: the card fades as one, nothing shows through.
            .compositingGroup()
            .bounceLoop(active: item.yourTurn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier ?? "home.table.\(item.id)")
    }

    /// Which game this table plays, as a tab in the game's color across the card's top edge
    /// (clear of the streak paw on the other corner).
    @ViewBuilder private var gameTab: some View {
        if let game {
            Text(verbatim: game.title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.tint(game.tint)).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2.5)))
                .fixedSize()
                .offset(x: -10, y: -9)
                .accessibilityHidden(true)
        }
    }

    /// "3 days ago", once a game in play has waited a day or more since its last move.
    private var idleText: String? {
        guard let days = item.idleDays, days >= 1 else { return nil }
        return days == 1
            ? String(localized: "1 day ago", comment: "Home table card: the last move was a day ago")
            : String(localized: "\(days) days ago", comment: "Home table card: how long ago the last move was")
    }

    private var accessibilityText: Text {
        let gameName = game?.title ?? ""
        let table =
            item.yourTurn
                ? Text("Your turn, \(item.title), \(gameName)", comment: "VoiceOver: a Home table card on your turn: its name, its game")
                : Text("\(item.title), \(gameName)", comment: "VoiceOver: a Home table card: its name, its game")
        let names = people.faces.map(\.name).joined(separator: ", ")
        let who = names.isEmpty ? table : Text("\(table), with \(names)", comment: "VoiceOver: a Home table card, then who else plays there")
        guard let idleText else { return who }
        return Text("\(who), last move \(idleText)", comment: "VoiceOver: a Home table card, then how long ago its last move was")
    }

    @ViewBuilder private var cat: some View {
        if let shownCat {
            Image(ArtName.cat(shownCat, pose))
                .resizable().scaledToFit()
                .frame(width: 64, height: 64)
                .shadow(color: Palette.ink.opacity(0.35), radius: 0, x: 0, y: 3)
        } else {
            // A table with no cached cats yet: a plain paw mark keeps the card from looking empty.
            Image(ArtName.iconPawMenu)
                .resizable().scaledToFit()
                .frame(width: 50, height: 50)
                .opacity(0.8)
        }
    }

    private var fill: LinearGradient {
        let colors: [Color] =
            item.yourTurn
            ? [Palette.orange.mix(with: .white, by: 0.35), Palette.orange, Palette.orange.mix(with: Palette.magenta, by: 0.3)]
            : [Palette.violet.mix(with: .white, by: 0.15), Palette.violet.mix(with: Palette.ink, by: 0.35)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Who you're playing with, on one line: your own people (connections, and anyone sharing this
/// phone) first on name pills, then everyone else, then bots. Names that don't fit become a count
/// ("+2"), dropped from the end; a single name left over truncates.
private struct PeopleLine: View {
    let line: TablePeople.Line

    var body: some View {
        if !line.isEmpty {
            let variants = line.variants
            ViewThatFits(in: .horizontal) {
                ForEach(Array(variants.enumerated()), id: \.offset) { _, variant in
                    row(variant.faces, more: variant.more)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func row(_ faces: [TablePeople.Face], more: Int) -> some View {
        let close = faces.filter(\.close)
        let others = faces.filter { !$0.close }.map(\.name).joined(separator: ", ")
        return HStack(spacing: 4) {
            ForEach(Array(close.enumerated()), id: \.offset) { _, face in
                NameTag(face.name, maxWidth: more > 0 ? 92 : 118, size: 12)
            }
            if !others.isEmpty {
                Text(verbatim: others)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if more > 0 {
                Text(verbatim: "+\(more)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 1)
                    .fixedSize()
            }
        }
    }
}

/// A row of little seat dots in the seat ring colors: filled for taken seats, hollow for open ones.
private struct SeatPips: View {
    let seats: [CachedSeat]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(seats.enumerated()), id: \.offset) { i, seat in
                if seat.kind != .closed {
                    let taken = seat.kind == .human || seat.kind == .bot
                    Circle()
                        .fill(taken ? Palette.playerRings[i % Palette.playerRings.count] : .clear)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
