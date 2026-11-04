import PounceKit
import SwiftUI

/// The lobby, one screen for host and guests (spec §5.5, mock m3-lobby): the table's name up top
/// (the host or anyone seated taps it to rename the table), the room code huge with share and QR, the rug with six cushions (the server's six seats), and the big orange
/// start pill for every seated phone.
struct LobbyView: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession
    /// False while the socket is reconnecting: the seats and buttons don't take taps.
    let interactive: Bool

    private enum Control: Hashable {
        case seat(Int), start, share
    }

    /// Who the person picker seats, and how.
    private enum PickerTarget: Identifiable {
        case claim(Int)
        case swap(Int)

        var id: String {
            switch self {
            case .claim(let s): "claim-\(s)"
            case .swap(let s): "swap-\(s)"
            }
        }

        var seat: Int {
            switch self {
            case .claim(let s), .swap(let s): s
            }
        }
    }

    @State private var menuSeat: Int?
    @State private var picker: PickerTarget?
    @State private var sharing = false
    @State private var showQR = false
    @State private var renaming = false
    @State private var wiggles: [Control: Int] = [:]
    @State private var lastTapped: Control?
    @State private var rugFrame: CGRect = .zero

    private var room: RoomView? { session.store.room }
    private var table: TableModel? { session.model }
    private var seated: Bool { !(table?.mySeats.isEmpty ?? true) }
    private var shareURL: URL { DeepLink.shareURL(code: session.code) }
    private var tableName: String { room?.title ?? TableName.fallback(code: session.code) }
    /// The server takes a rename from the host or any seated phone.
    private var canRename: Bool { seated || room?.youAreHost == true }

    var body: some View {
        ZStack {
            RoomBackground()
            VStack(spacing: 6) {
                topBar
                codeRow
                    .allowsHitTesting(interactive)
                rug
                    .allowsHitTesting(interactive)
                startRow
                    .allowsHitTesting(interactive)
            }
            .padding(.bottom, 10)
            if let menuSeat, let room, room.seats.indices.contains(menuSeat) {
                SeatMenu(center: cushionCenter(menuSeat), toward: rugCenter, items: menuItems(menuSeat, room.seats[menuSeat])) {
                    self.menuSeat = nil
                }
                .transition(.opacity)
            }
        }
        .coordinateSpace(.named("lobby"))
        .animation(.easeOut(duration: 0.15).paced, value: menuSeat)
        .background(ShareRoom(
            isPresented: $sharing, url: shareURL, tableName: tableName, inviteCode: session.code,
            catArt: ArtName.cat(hostCat, .idle)))
        .sheet(isPresented: $renaming) {
            RenameTableView(current: tableName, onCancel: { renaming = false }) { name in
                renaming = false
                session.send(.rename(name: name))
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.night)
        }
        .sheet(item: $picker) { target in
            personPicker(target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.night)
        }
        .onChange(of: session.lobbyNope) { nope() }
        .onChange(of: interactive) { _, on in
            if !on {
                menuSeat = nil
                renaming = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-lobby")
    }

    // MARK: header

    private var topBar: some View {
        HStack(spacing: 8) {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("lobby.home")
            Spacer(minLength: 0)
            TableNameTitle(name: tableName, editable: canRename && interactive) {
                renaming = true
            }
            .accessibilityIdentifier("lobby.name")
            Spacer(minLength: 0)
            // Balances the home button so the name sits in the middle.
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var codeRow: some View {
        HStack(spacing: 10) {
            OutlinedText(session.code, size: 44, fill: .white, width: 3.5)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Palette.violet.mix(with: .white, by: 0.25), Palette.violet,
                                     Palette.violet.mix(with: Palette.ink, by: 0.35)],
                            startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 5))
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Room code \(spelled(session.code))"))
                .accessibilityIdentifier("lobby.code")
            PillButton(icon: ArtName.iconShare, color: Palette.magenta, size: .small, width: 54, accessibilityLabel: "Invite") {
                lastTapped = .share
                sharing = true
            }
            .wiggle(trigger: wiggles[.share, default: 0])
            .accessibilityIdentifier("lobby.share")
            PillButton(icon: ArtName.iconQr, color: Palette.teal, size: .small, width: 54, accessibilityLabel: showQR ? "Hide QR code" : "Show QR code") {
                withAnimation(.spring(duration: 0.4, bounce: 0.4).paced) { showQR.toggle() }
            }
            .accessibilityIdentifier("lobby.qr")
        }
        .padding(.horizontal, 12)
    }

    // MARK: rug and cushions

    private var rug: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height / 0.86)
            let cushion = side * 0.25
            ZStack {
                Image(ArtName.rug)
                    .resizable()
                    .frame(width: side * 0.96, height: side * 0.8)
                    .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 8)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .accessibilityHidden(true)
                if let room {
                    ForEach(room.seats.indices, id: \.self) { i in
                        cushionButton(i, room.seats[i], width: cushion)
                            .position(Self.seatPoint(i, count: room.seats.count, in: geo.size, side: side))
                    }
                }
                if showQR {
                    QRTile(text: shareURL.absoluteString, side: min(side * 0.58, 240))
                        .onTapGesture { withAnimation(.spring(duration: 0.3).paced) { showQR = false } }
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .accessibilityLabel("QR code for this table")
                        .accessibilityAddTraits(.isImage)
                        .accessibilityIdentifier("lobby.qrcode")
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("lobby")) } action: { rugFrame = $0 }
        .frame(maxHeight: .infinity)
    }

    /// Six cushions on an ellipse around the rug's middle: 0 top-left, then clockwise.
    private static func seatPoint(_ i: Int, count: Int, in size: CGSize, side: CGFloat) -> CGPoint {
        let n = max(count, 1)
        let angle = (-120.0 + Double(i) * 360.0 / Double(n)) * .pi / 180
        let rx = side * 0.33
        let ry = min(side * 0.36, size.height * 0.34)
        return CGPoint(x: size.width / 2 + cos(angle) * rx, y: size.height / 2 + sin(angle) * ry)
    }

    private var rugCenter: CGPoint { CGPoint(x: rugFrame.midX, y: rugFrame.midY) }

    private func cushionCenter(_ i: Int) -> CGPoint {
        guard let room else { return .zero }
        let side = min(rugFrame.width, rugFrame.height / 0.86)
        let p = Self.seatPoint(i, count: room.seats.count, in: rugFrame.size, side: side)
        return CGPoint(x: rugFrame.minX + p.x, y: rugFrame.minY + p.y)
    }

    private func cushionButton(_ i: Int, _ seat: SeatView, width: CGFloat) -> some View {
        Button {
            tapSeat(i)
        } label: {
            Cushion(seat: seat, index: i, width: width, name: room.map { SeatInfo.name($0, i) } ?? "")
        }
        .buttonStyle(.plain)
        .wiggle(trigger: wiggles[.seat(i), default: 0])
        .pop(trigger: seat.kind)
        .accessibilityLabel(seatLabel(seat))
        .accessibilityHint(seatHint(seat))
        .accessibilityIdentifier("lobby.seat.\(i)")
    }

    private func seatLabel(_ seat: SeatView) -> Text {
        switch seat.kind {
        case .human:
            let name = seat.person?.name ?? ""
            let presence: Text = switch seat.presence {
            case .away: Text("away")
            case .asleep: Text("asleep")
            default: Text("awake")
            }
            return seat.yours
                ? Text("\(name), on this phone, \(presence)")
                : Text("\(name), on another phone, \(presence)")
        case .bot: return Text("House Cat bot")
        case .open: return Text("Open seat")
        case .closed: return Text("Closed seat")
        }
    }

    private func seatHint(_ seat: SeatView) -> Text {
        switch seat.kind {
        case .human where seat.yours: Text("Swap or stand up")
        case .human: Text("")
        case .open where !seated: Text("Sit here")
        default: Text("Invite, sit here, add a bot or remove")
        }
    }

    // MARK: start

    @ViewBuilder private var startRow: some View {
        if let table, seated {
            let ready = table.canStart
            // Waiting: a muted violet pill, never a desaturated orange (that reads beige).
            // Ready: hot orange with a white rim around the gold play icon so it reads.
            PillButton(
                icon: ArtName.iconPlay,
                color: ready ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.45),
                size: .large, width: 300, iconOutline: ready ? .white : nil, accessibilityLabel: "Start"
            ) {
                start()
            }
            .opacity(ready ? 1 : 0.7)
            .shadow(color: ready ? Palette.orange.opacity(0.8) : .clear, radius: 14)
            .wiggle(trigger: wiggles[.start, default: 0])
            .accessibilityValue(ready ? Text("") : Text("Waiting for players"))
            .accessibilityIdentifier("lobby.start")
            .transition(.scale.combined(with: .opacity))
        } else {
            Color.clear.frame(height: PillSize.large.height + 6)
        }
    }

    private func start() {
        guard let table else { return }
        lastTapped = .start
        if table.canStart {
            session.send(.start)
            return
        }
        // The wordless reason: the seats in the way wiggle (open ones, or closed ones when
        // there just aren't enough players).
        var blocking = table.blockingSeats
        if blocking.isEmpty, let room {
            blocking = room.seats.indices.filter { room.seats[$0].kind == .closed }
        }
        for s in blocking { wiggles[.seat(s), default: 0] += 1 }
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }

    // MARK: seat actions

    private func tapSeat(_ i: Int) {
        guard let room, room.seats.indices.contains(i) else { return }
        lastTapped = .seat(i)
        let seat = room.seats[i]
        Haptics.shared.tick()
        switch seat.kind {
        case .human:
            if seat.yours {
                Sound.shared.play(ArtName.Sound.sfxPop)
                menuSeat = i
            } else {
                // Someone else's cat: just a happy wiggle.
                wiggles[.seat(i), default: 0] += 1
                Sound.shared.play(ArtName.Sound.sfxPop)
            }
        case .open where !seated:
            // Not at the table yet: one tap sits the owner here.
            if let owner = model.people.owner {
                Sound.shared.play(ArtName.Sound.sfxPop)
                session.send(.claim(seat: i, person: owner))
            }
        case .open, .closed, .bot:
            if seated {
                menuSeat = i
            } else {
                // Only a seated phone can change seats.
                nope()
            }
        }
    }

    private func menuItems(_ i: Int, _ seat: SeatView) -> [SeatMenuItem] {
        if seat.kind == .human {
            return [
                SeatMenuItem(id: "swap", icon: ArtName.iconSwap, color: Palette.sky, label: "Someone else sits here") {
                    menuSeat = nil
                    picker = .swap(i)
                },
                SeatMenuItem(id: "leave", icon: ArtName.iconLeave, color: Palette.magenta, label: "Stand up") {
                    menuSeat = nil
                    session.send(.leave(seat: i))
                },
            ]
        }
        var items: [SeatMenuItem] = [
            SeatMenuItem(id: "invite", icon: ArtName.iconShare, color: Palette.sky, label: "Invite someone") {
                menuSeat = nil
                if seat.kind != .open { session.send(.configure(seat: i, kind: .open)) }
                lastTapped = .share
                sharing = true
            },
            SeatMenuItem(id: "here", icon: ArtName.badgePhone, color: Palette.teal, label: "Someone on this phone") {
                menuSeat = nil
                picker = .claim(i)
            },
        ]
        if seat.kind != .bot {
            items.append(SeatMenuItem(id: "bot", icon: ArtName.badgeBot, color: Palette.orange, label: "Add a bot") {
                menuSeat = nil
                session.send(.configure(seat: i, kind: .bot))
            })
        }
        if seat.kind != .closed {
            items.append(SeatMenuItem(id: "remove", icon: ArtName.iconRemove, color: Palette.magenta, label: "Remove seat") {
                menuSeat = nil
                session.send(.configure(seat: i, kind: .closed))
            })
        }
        return items
    }

    private func personPicker(_ target: PickerTarget) -> some View {
        let seatedIDs = Set(room?.seats.compactMap(\.person?.id) ?? [])
        let local = ([model.people.owner].compactMap { $0 } + model.people.others).filter { !seatedIDs.contains($0.id) }
        return PersonPicker(
            people: local, ownerID: model.people.owner?.id,
            onPick: { seat($0, target) },
            onCreate: { name, cat in seat(model.addPerson(name: name, cat: cat), target) },
            onClose: { picker = nil })
    }

    /// Seats `person` (a pass-and-play local) for the picker's target.
    private func seat(_ person: Person, _ target: PickerTarget) {
        picker = nil
        lastTapped = .seat(target.seat)
        switch target {
        case .claim(let s):
            if let kind = room?.seats[s].kind, kind != .open {
                session.send(.configure(seat: s, kind: .open))
            }
            session.send(.claim(seat: s, person: person))
        case .swap(let s):
            session.send(.leave(seat: s))
            session.send(.claim(seat: s, person: person))
        }
        Sound.shared.play(ArtName.Sound.sfxPop)
    }

    // MARK: helpers

    /// A lobby message was refused: wiggle whatever was tapped last.
    private func nope() {
        if let lastTapped { wiggles[lastTapped, default: 0] += 1 }
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }

    /// The cat in the share sheet header: mine when I'm the host, else the first seated cat.
    private var hostCat: Int {
        let mine = room?.seats.first { $0.yours && $0.person != nil }?.person?.cat
        let first = room?.seats.first { $0.kind == .human }?.person?.cat
        let fallback = model.people.owner?.cat ?? 0
        return (room?.youAreHost == true ? mine : first) ?? mine ?? fallback
    }

    private func spelled(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}

/// One cushion and whoever sits on it.
struct Cushion: View {
    let seat: SeatView
    let index: Int
    let width: CGFloat
    /// The person's name, or the bot's; shown on a pill under the cat.
    var name = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var color: Color { Palette.playerRings[index % Palette.playerRings.count] }
    private var height: CGFloat { width * 0.56 }

    var body: some View {
        ZStack {
            pillow
            occupant
        }
        .frame(width: width, height: width * 1.15, alignment: .bottom)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var pillow: some View {
        if seat.kind == .closed {
            Ellipse()
                .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 10]))
                .frame(width: width, height: height)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            ZStack {
                Ellipse()
                    .fill(color.mix(with: Palette.ink, by: 0.45))
                    .offset(y: 6)
                Ellipse()
                    .fill(LinearGradient(
                        colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: Palette.ink, by: 0.2)],
                        startPoint: .top, endPoint: .bottom))
                Ellipse()
                    .fill(color.mix(with: Palette.ink, by: 0.3))
                    .frame(width: width * 0.62, height: height * 0.5)
                    .offset(y: -height * 0.06)
                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: width * 0.3, height: height * 0.1)
                    .offset(x: -width * 0.22, y: -height * 0.3)
            }
            .overlay(Ellipse().strokeBorder(Palette.ink, lineWidth: 4))
            .frame(width: width, height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder private var occupant: some View {
        switch seat.kind {
        case .human:
            cat(seat.person?.cat ?? 0, pose: pose, badge: seat.yours ? ArtName.badgePhone : ArtName.badgeRemote)
                .overlay(alignment: .bottom) { nameTag }
        case .bot:
            cat(3, pose: .idle, badge: ArtName.badgeBot)
                .overlay(alignment: .bottom) { nameTag }
        case .open:
            Circle()
                .fill(LinearGradient(
                    colors: [Palette.violet.mix(with: .white, by: 0.3), Palette.violet],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay { Image(ArtName.iconPlus).resizable().scaledToFit().padding(9) }
                .frame(width: width * 0.42, height: width * 0.42)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.12 : 0.94))
                .opacity(reduceMotion && pulse ? 0.7 : 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, height * 0.3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).paced) { pulse = true }
                }
        case .closed:
            EmptyView()
        }
    }

    private var nameTag: some View {
        NameTag(name, maxWidth: max(width * 1.2, 84))
            .offset(y: 20)
    }

    private var pose: CatPose {
        switch seat.presence {
        case .awake: .awake
        case .away: .away
        case .asleep: .asleep
        case nil: .idle
        }
    }

    private func cat(_ cat: Int, pose: CatPose, badge: String) -> some View {
        Image(ArtName.cat(cat, pose))
            .resizable()
            .scaledToFit()
            .frame(width: width * 0.9, height: width * 0.9)
            .shadow(color: Palette.ink.opacity(0.35), radius: 0, x: 0, y: 4)
            .overlay(alignment: .bottomTrailing) {
                Image(badge)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .offset(x: 6, y: 2)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, height * 0.35)
    }
}
