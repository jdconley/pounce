import PounceKit
import SwiftUI

/// A Purrtrait table's lobby on a phone (spec §5, §11). The TV does the joining, so there is no
/// code to share, no invite and no House Cat here: the cats at the table, the timer (the host's
/// three pills), a pass-and-play seat for someone on this phone, Remove in the host's tap on
/// another cat, and Start once two are in.
struct PurrLobbyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let session: RoomSession
    let interactive: Bool

    @State private var picker = false
    @State private var removing: Seat?
    @State private var mine: Seat?
    @State private var shakes = 0

    private var store: RoomStore { session.store }
    private var room: RoomView? { store.room }
    private var host: Bool { room?.youAreHost == true }
    private var seated: [Seat] { room.map { r in r.seats.indices.filter { r.seats[$0].kind == .human } } ?? [] }
    private var mySeats: [Seat] { room.map { r in r.seats.indices.filter { r.seats[$0].yours } } ?? [] }
    private var openSeat: Seat? { room?.seats.firstIndex { $0.kind == .open } }
    /// The table's TV is connected: Start needs it (the room answers `no_screen` without).
    private var tvHere: Bool { room?.screen == true }
    private var ready: Bool { seated.count >= GameCatalog.purrtrait.minPlayers && tvHere }
    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        ZStack {
            RoomBackground()
            VStack(spacing: roomy ? 20 : 12) {
                topBar
                timer
                cats
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(interactive)
                footer
                    .allowsHitTesting(interactive)
            }
            .frame(maxWidth: roomy ? 760 : .infinity)
            .padding(.bottom, 12)
        }
        .tipHost(.lobby, paused: picker || removing != nil || !interactive)
        .sheet(isPresented: $picker) {
            personPicker
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.night)
        }
        .alert(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(String(localized: "Remove", comment: "Purrtrait lobby (host): take this player off the table"), role: .destructive) {
                if let seat = removing { session.send(.remove(seat: seat)) }
                removing = nil
            }
            .accessibilityIdentifier("purr.remove.confirm")
            Button(String(localized: "Keep", comment: "Purrtrait lobby: don't remove the player"), role: .cancel) { removing = nil }
        } message: {
            Text("They can't come back to this table.", comment: "Purrtrait lobby: what removing a player does")
        }
        .confirmationDialog(mine.map { SeatInfo.name(room ?? emptyRoom, $0) } ?? "", isPresented: Binding(get: { mine != nil }, set: { if !$0 { mine = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Stand up", comment: "Seat menu: leave this seat"), role: .destructive) {
                if let seat = mine { session.send(.leave(seat: seat)) }
                mine = nil
            }
            .accessibilityIdentifier("purr.standUp")
        }
        .onChange(of: session.lobbyNope) {
            shakes += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-lobby")
    }

    private var emptyRoom: RoomView { RoomView(code: session.code, status: .lobby, youAreHost: false, seats: []) }

    private var removeTitle: Text {
        let name = removing.map { SeatInfo.name(room ?? emptyRoom, $0) } ?? ""
        return Text("Remove \(name)?", comment: "Purrtrait lobby (host): confirm taking a player off the table")
    }

    // MARK: top

    private var topBar: some View {
        HStack(spacing: 10) {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("lobby.home")
            OutlinedText(room?.title ?? TableName.fallback(code: session.code), size: roomy ? 28 : 22, fill: Palette.orange, width: 3, lines: 1)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("lobby.name")
            // The table lives on the TV: where everyone joins.
            HStack(spacing: 6) {
                Image(ArtName.iconTV).resizable().scaledToFit().frame(width: 26, height: 26)
                OutlinedText(GameCatalog.purrtrait.title, size: 16, width: 2.5)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    /// The timer: 45, 60 or 90 seconds a turn. The host's pills; everyone else sees the pick.
    private var timer: some View {
        let current = room?.purrTimer ?? PurrTimer.standard.rawValue
        return HStack(spacing: 8) {
            ForEach(PurrTimer.allCases, id: \.rawValue) { option in
                let on = option.rawValue == current
                Button {
                    guard host, interactive, !on else { return }
                    Haptics.shared.tick()
                    session.send(.setOptions(RoomOptions(timer: option.rawValue)))
                } label: {
                    Text("\(option.rawValue) s", comment: "Purrtrait lobby: seconds a turn, on a timer pill")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: 64)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Capsule().fill(on ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.4)))
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .groupOpacity(host || on ? 1 : 0.6)
                .accessibilityLabel(Text("\(option.rawValue) seconds a turn", comment: "Purrtrait lobby: VoiceOver, a timer pill"))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("purr.timer.\(option.rawValue)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: the cats

    private var cats: some View {
        GeometryReader { geo in
            let columns = roomy ? 5 : (geo.size.width > 600 ? 5 : 3)
            let cat: CGFloat = min((geo.size.width - 24) / CGFloat(columns) - 16, roomy ? 130 : 92)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 14) {
                    ForEach(seated, id: \.self) { seat in
                        catButton(seat, side: cat)
                    }
                    if let seat = openSeat, !mySeats.isEmpty {
                        addButton(seat, side: cat)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: geo.size.height)
                .animation(.spring(duration: 0.45, bounce: 0.35).paced, value: seated)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func catButton(_ seat: Seat, side: CGFloat) -> some View {
        let info = room?.seats[safe: seat]
        let name = room.map { SeatInfo.name($0, seat) } ?? ""
        let yours = info?.yours == true
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            if yours {
                mine = seat
            } else if host {
                removing = seat
            }
        } label: {
            VStack(spacing: 4) {
                Image(ArtName.cat(SeatInfo.catIndex(info), .awake))
                    .resizable().scaledToFit()
                    .frame(width: side, height: side)
                    .background(Ellipse().fill(SeatInfo.ringColor(seat)).overlay(Ellipse().strokeBorder(Palette.ink, lineWidth: 3))
                        .frame(width: side * 1.05, height: side * 0.4).offset(y: side * 0.36))
                NameTag(name, maxWidth: side + 30, active: yours, size: roomy ? 16 : 13)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(yours ? Text("\(name), on this phone", comment: "Purrtrait lobby: VoiceOver, a seat on this phone") : Text(name))
        .accessibilityHint(yours ? Text("Stand up", comment: "Purrtrait lobby: VoiceOver hint, my seat") : host ? Text("Remove", comment: "Purrtrait lobby: VoiceOver hint, the host can remove") : Text(""))
        .accessibilityIdentifier("lobby.seat.\(seat)")
    }

    /// Someone else on this phone sits down too (pass and play).
    private func addButton(_ seat: Seat, side: CGFloat) -> some View {
        Button {
            Haptics.shared.tick()
            picker = true
        } label: {
            VStack(spacing: 4) {
                Image(ArtName.iconPlus).resizable().scaledToFit().frame(width: side * 0.4, height: side * 0.4)
                    .frame(width: side * 0.8, height: side * 0.8)
                    .background(Circle().fill(Palette.ink.opacity(0.35)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, dash: [10, 8])))
                    .frame(width: side, height: side)
                Text("This phone", comment: "Purrtrait lobby: add someone who plays on this same phone")
                    .font(.system(.footnote, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add a player on this phone", comment: "Purrtrait lobby: VoiceOver, pass and play"))
        .accessibilityIdentifier("lobby.add")
    }

    // MARK: bottom

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(ArtName.iconTV).resizable().scaledToFit().frame(width: 28, height: 28)
                Group {
                    if !tvHere {
                        Text(verbatim: PurrWords.waitingForTV)
                    } else if ready {
                        Text("Scan the TV to join", comment: "Purrtrait lobby: how others join (the TV's code)")
                    } else {
                        Text("2 to 10 players. Scan the TV to join", comment: "Purrtrait lobby: how many play, and how others join")
                    }
                }
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.ink.opacity(0.78)))
            .padding(.horizontal, 16)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityIdentifier("lobby.status")
            if mySeats.isEmpty {
                if let seat = openSeat, let owner = model.people.owner {
                    PillButton(icon: ArtName.iconPlay, color: Palette.orange, size: .large, width: 300, iconOutline: .white,
                               title: String(localized: "Sit down", comment: "Purrtrait lobby: take a seat at the table"),
                               accessibilityLabel: "Sit down") {
                        session.send(.claim(seat: seat, person: owner))
                    }
                    .accessibilityIdentifier("lobby.sit")
                }
            } else {
                PillButton(
                    icon: ArtName.iconPlay,
                    color: ready ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.45),
                    size: .large, width: 300, iconOutline: ready ? .white : nil,
                    title: String(localized: "Start", comment: "Lobby: the pill that deals the game"),
                    accessibilityLabel: "Start"
                ) {
                    guard ready else {
                        shakes += 1
                        Haptics.shared.thump()
                        Sound.shared.play(ArtName.Sound.sfxNope)
                        return
                    }
                    model.tips.used("lobby.start")
                    session.send(.start)
                }
                .groupOpacity(ready ? 1 : 0.8)
                .shadow(color: ready ? Palette.orange.opacity(0.8) : .clear, radius: 14)
                .shake(trigger: shakes)
                .accessibilityIdentifier("lobby.start")
            }
        }
    }

    private var personPicker: some View {
        let seatedIDs = Set(room?.seats.compactMap(\.person?.id) ?? [])
        let local = ([model.people.owner].compactMap { $0 } + model.people.others).filter { !seatedIDs.contains($0.id) }
        return PersonPicker(
            people: local, ownerID: model.people.owner?.id,
            onPick: { seat($0) },
            kittenDevice: model.ageBand == .kitten,
            onCreate: { name, cat, band in seat(model.addPerson(name: name, cat: cat, band: band)) },
            onClose: { picker = false })
    }

    private func seat(_ person: Person) {
        picker = false
        guard let seat = openSeat else { return }
        session.send(.claim(seat: seat, person: person))
        Sound.shared.play(ArtName.Sound.sfxPop)
    }
}
