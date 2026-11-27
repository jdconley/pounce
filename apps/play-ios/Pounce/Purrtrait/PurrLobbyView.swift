import PounceKit
import SwiftUI
import UIKit

/// A Purrtrait table's lobby on a phone or an iPad (spec §5, §11). The TV does the joining, so
/// there is no code to share, no invite and no House Cat here: the cats at the table, the timer
/// (the host's three pills), a pass-and-play seat for someone on this device, Remove in the
/// host's tap on another cat, and Start once two are in.
///
/// A phone keeps one column. An iPad (a regular-width window) is laid out for its size: tall, the
/// same column with everything bigger and the cats sized to fill the floor; wide, a panel on the
/// left (the table's name, the timer, how to join, Start) and the cats filling the right.
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
    /// The pass-and-play seat shows once this device has a seat and one is open.
    private var addSeat: Seat? { mySeats.isEmpty ? nil : openSeat }

    var body: some View {
        ZStack {
            RoomBackground()
            if roomy {
                roomyLayout
            } else {
                VStack(spacing: 12) {
                    topBar(.phone)
                    timer(.phone)
                    phoneCats
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(interactive)
                    footer(.phone)
                        .allowsHitTesting(interactive)
                }
                .padding(.bottom, 12)
            }
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

    private var tableName: String { room?.title ?? TableName.fallback(code: session.code) }

    // MARK: iPad

    private var roomyLayout: some View {
        GeometryReader { geo in
            if Roomy.sideBySide(geo.size) {
                let panel = min(geo.size.width * 0.36, 430)
                HStack(spacing: 28) {
                    RoomyPanel {
                        VStack(spacing: 26) {
                            OutlinedText(tableName, size: 34, fill: Palette.orange, width: 4, lines: 2)
                                .accessibilityIdentifier("lobby.name")
                            gameChip(.pad)
                            timer(.pad)
                            Spacer(minLength: 0)
                            footer(.pad, startWidth: panel - 48)
                                .allowsHitTesting(interactive)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 34)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: panel)
                    .padding(.top, 56)
                    fittedCats(.pad)
                        .allowsHitTesting(interactive)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    CornerHomeButton { model.goHome() }
                        .accessibilityIdentifier("lobby.home")
                        .padding(.leading, 16)
                        .padding(.top, 2)
                }
            } else {
                VStack(spacing: 26) {
                    topBar(.pad)
                    timer(.pad)
                    fittedCats(.pad)
                        .allowsHitTesting(interactive)
                    footer(.pad)
                        .allowsHitTesting(interactive)
                }
                .frame(maxWidth: 900)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: top

    private func topBar(_ s: LobbySizes) -> some View {
        HStack(spacing: 10) {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("lobby.home")
            OutlinedText(tableName, size: s.title, fill: Palette.orange, width: s.title / 8, lines: 1)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("lobby.name")
            gameChip(s)
        }
        .padding(.horizontal, 12)
        .frame(height: max(56, s.title * 2.2))
    }

    /// The game's chip: the table lives on the TV, where everyone joins.
    private func gameChip(_ s: LobbySizes) -> some View {
        HStack(spacing: 6) {
            Image(ArtName.iconTV).resizable().scaledToFit().frame(width: s.chipIcon, height: s.chipIcon)
            OutlinedText(GameCatalog.purrtrait.title, size: s.chipText, width: s.chipText / 6.4)
        }
        .padding(.horizontal, s.chipText * 0.65).padding(.vertical, s.chipText * 0.3)
        .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
        .accessibilityElement(children: .combine)
    }

    /// The timer: 45, 60 or 90 seconds a turn. The host's pills; everyone else sees the pick.
    private func timer(_ s: LobbySizes) -> some View {
        let current = room?.purrTimer ?? PurrTimer.standard.rawValue
        return HStack(spacing: s.pillHeight / 5) {
            ForEach(PurrTimer.allCases, id: \.rawValue) { option in
                let on = option.rawValue == current
                Button {
                    guard host, interactive, !on else { return }
                    Haptics.shared.tick()
                    session.send(.setOptions(RoomOptions(timer: option.rawValue)))
                } label: {
                    Text("\(option.rawValue) s", comment: "Purrtrait lobby: seconds a turn, on a timer pill")
                        .font(.system(s.pillFont, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: s.pillMinWidth)
                        .padding(.horizontal, 12)
                        .frame(height: s.pillHeight)
                        .background(Capsule().fill(on ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.4)))
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: s.pillHeight > 50 ? 4 : 3))
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

    /// A phone's cats: three to a row, at most 92 points, scrolling if a crowd outgrows the floor.
    private var phoneCats: some View {
        GeometryReader { geo in
            let columns = geo.size.width > 600 ? 5 : 3
            let cat: CGFloat = min((geo.size.width - 24) / CGFloat(columns) - 16, LobbySizes.phone.catCap)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 14) {
                    catCells(side: cat, s: .phone)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: geo.size.height)
                .animation(.spring(duration: 0.45, bounce: 0.35).paced, value: seated)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// An iPad's cats: as big as the floor lets every one of them be (up to 210 points), in the
    /// rows and columns that make them biggest, centred.
    private func fittedCats(_ s: LobbySizes) -> some View {
        GeometryReader { geo in
            let count = max(seated.count + (addSeat == nil ? 0 : 1), 1)
            let fit = Self.fit(count: count, in: geo.size, cap: s.catCap, label: s.nameSize * 2.2 + 8)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.side + 40), spacing: Self.gap), count: fit.columns), spacing: Self.gap) {
                    catCells(side: fit.side, s: s)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .animation(.spring(duration: 0.45, bounce: 0.35).paced, value: seated)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    static let gap: CGFloat = 22

    /// The columns, and the side of a cat, that make `count` cats biggest in `size` (each with a
    /// name `label` points tall under it), no bigger than `cap`.
    static func fit(count: Int, in size: CGSize, cap: CGFloat, label: CGFloat) -> (columns: Int, side: CGFloat) {
        var best = (columns: 1, side: CGFloat(0))
        for columns in 1...max(1, min(count, 6)) {
            let rows = CGFloat((count + columns - 1) / columns)
            let across = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns) - 40
            let down = (size.height - 16 - (rows - 1) * gap) / rows - label
            let side = min(across, down, cap)
            if side > best.side { best = (columns, side) }
        }
        return (best.columns, max(best.side, 60))
    }

    @ViewBuilder private func catCells(side: CGFloat, s: LobbySizes) -> some View {
        ForEach(seated, id: \.self) { seat in
            catButton(seat, side: side, s: s)
        }
        if let seat = addSeat {
            addButton(seat, side: side, s: s)
        }
    }

    private func catButton(_ seat: Seat, side: CGFloat, s: LobbySizes) -> some View {
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
                    .background(Ellipse().fill(SeatInfo.ringColor(seat)).overlay(Ellipse().strokeBorder(Palette.ink, lineWidth: side > 120 ? 4 : 3))
                        .frame(width: side * 1.05, height: side * 0.4).offset(y: side * 0.36))
                NameTag(name, maxWidth: side + 30, active: yours, size: s.nameSize)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(yours ? Text("\(name), on \(DeviceWord.this)", comment: "Purrtrait lobby: VoiceOver, a seat on this device (this phone, this iPad)") : Text(name))
        .accessibilityHint(yours ? Text("Stand up", comment: "Purrtrait lobby: VoiceOver hint, my seat") : host ? Text("Remove", comment: "Purrtrait lobby: VoiceOver hint, the host can remove") : Text(""))
        .accessibilityIdentifier("lobby.seat.\(seat)")
    }

    /// Someone else on this device sits down too (pass and play).
    private func addButton(_ seat: Seat, side: CGFloat, s: LobbySizes) -> some View {
        Button {
            Haptics.shared.tick()
            picker = true
        } label: {
            VStack(spacing: 4) {
                Image(ArtName.iconPlus).resizable().scaledToFit().frame(width: side * 0.4, height: side * 0.4)
                    .frame(width: side * 0.8, height: side * 0.8)
                    .background(Circle().fill(Palette.ink.opacity(0.35)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: side > 120 ? 6 : 4, dash: [10, 8])))
                    .frame(width: side, height: side)
                Text(verbatim: DeviceWord.thisCapitalized)
                    .font(.system(s.addFont, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    // Two words under a cat: at the largest text they'd be "This…".
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add a player on \(DeviceWord.this)", comment: "Purrtrait lobby: VoiceOver, pass and play on this device (this phone, this iPad)"))
        .accessibilityIdentifier("lobby.add")
    }

    // MARK: bottom

    @ViewBuilder private func footer(_ s: LobbySizes, startWidth: CGFloat? = nil) -> some View {
        VStack(spacing: s.statusGap) {
            HStack(spacing: 8) {
                Image(ArtName.iconTV).resizable().scaledToFit().frame(width: s.tvIcon, height: s.tvIcon)
                Group {
                    if !tvHere {
                        Text(verbatim: PurrWords.waitingForTV)
                    } else if ready {
                        Text("Scan the TV to join", comment: "Purrtrait lobby: how others join (the TV's code)")
                    } else {
                        Text("2 to 10 players. Scan the TV to join", comment: "Purrtrait lobby: how many play, and how others join")
                    }
                }
                    .font(.system(s.statusFont, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, s.tvIcon / 2).padding(.vertical, s.tvIcon / 4)
            .background(RoundedRectangle(cornerRadius: s.tvIcon * 0.57, style: .continuous).fill(Palette.ink.opacity(0.78)))
            .padding(.horizontal, 16)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityIdentifier("lobby.status")
            if mySeats.isEmpty {
                if let seat = openSeat, let owner = model.people.owner {
                    PillButton(icon: ArtName.iconPlay, color: Palette.orange, size: .large, width: startWidth ?? s.startWidth, iconOutline: .white,
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
                    size: .large, width: startWidth ?? s.startWidth, iconOutline: ready ? .white : nil,
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

/// The lobby's sizes: a phone's, and an iPad's, read across a couch.
struct LobbySizes {
    let title: CGFloat
    let chipIcon: CGFloat
    let chipText: CGFloat
    let pillFont: Font.TextStyle
    let pillHeight: CGFloat
    let pillMinWidth: CGFloat
    let catCap: CGFloat
    let nameSize: CGFloat
    let addFont: Font.TextStyle
    let statusFont: Font.TextStyle
    let statusGap: CGFloat
    let tvIcon: CGFloat
    let startWidth: CGFloat

    static let phone = LobbySizes(
        title: 22, chipIcon: 26, chipText: 16, pillFont: .headline, pillHeight: 42, pillMinWidth: 64, catCap: 92, nameSize: 13,
        addFont: .footnote, statusFont: .subheadline, statusGap: 10, tvIcon: 28, startWidth: 300)
    static let pad = LobbySizes(
        title: 34, chipIcon: 40, chipText: 24, pillFont: .title2, pillHeight: 62, pillMinWidth: 92, catCap: 210, nameSize: 22,
        addFont: .title3, statusFont: .title3, statusGap: 18, tvIcon: 44, startWidth: 420)
}

/// "this phone" or "this iPad": the device in the words, so an iPad's never says phone.
@MainActor enum DeviceWord {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var this: String {
        isPad ? String(localized: "this iPad", comment: "This device, on an iPad (as in: a seat on this iPad)")
            : String(localized: "this phone", comment: "This device, on a phone (as in: a seat on this phone)")
    }
    static var thisCapitalized: String {
        isPad ? String(localized: "This iPad", comment: "Purrtrait lobby: add someone who plays on this same iPad")
            : String(localized: "This phone", comment: "Purrtrait lobby: add someone who plays on this same phone")
    }
}
