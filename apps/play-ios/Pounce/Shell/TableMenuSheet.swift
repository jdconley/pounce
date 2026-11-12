import PounceKit
import SwiftUI

/// The table's paw menu (`table.menu`): the table's name (renamed in the lobby only), sound, haptics, the
/// scores, how to play, names, move my seat, home, and forfeit (§5.13, behind a confirmation). Renaming the table grows the sheet into `RenameTableView`,
/// names (this phone's players) into `RenameSheet`, move my seat into `MoveSeatSheet`, how to play
/// into `HowToPlaySheet`.
struct TableMenuSheet: View {
    @Environment(Settings.self) private var settings
    @Environment(AppModel.self) private var model
    let session: RoomSession
    let onHome: () -> Void
    /// Closes the menu and shows the scoreboard (the open tower's tap does too).
    var onScores: (() -> Void)?
    /// The seat a forfeit applies to (`TableModel.forfeitSeat`: the hand that is up on a shared
    /// phone): nil hides Forfeit.
    var forfeitSeat: Seat?
    /// Confirmed: forfeit `seat`.
    var onForfeit: (Seat) -> Void = { _ in }
    let onClose: () -> Void

    private enum Page { case menu, moving, rules, renaming, names, look }

    @State private var page = Self.firstPage
    @State private var confirmingForfeit = false
    @State private var detent: PresentationDetent = Self.firstPage == .look ? Self.lookDetent : Self.menuForfeitDetent

    /// `-show-look` (DEBUG, screenshots) opens on the look tray.
    private static var firstPage: Page {
        #if DEBUG
        if CommandLine.arguments.contains("-show-look") { return .look }
        #endif
        return .menu
    }

    static let menuDetent = PresentationDetent.height(510)
    /// Room for the Forfeit row.
    static let menuForfeitDetent = PresentationDetent.height(590)
    private var menuDetent: PresentationDetent { forfeitSeat == nil ? Self.menuDetent : Self.menuForfeitDetent }
    static let lookDetent = PresentationDetent.height(380)

    /// The look tray is offered on a server with looks (streaks on), to a phone seated here.
    private var canChangeLook: Bool {
        guard let room = session.store.room, room.look != nil else { return false }
        return room.seats.contains { $0.yours && $0.kind == .human }
    }

    /// This phone's players can change their names in the lobby; once the game has started the
    /// server keeps every name as it is.
    private var canRenamePeople: Bool { canMove && session.store.room?.status == .lobby }

    private var canMove: Bool {
        guard let table = session.model else { return false }
        return !table.mySeats.isEmpty && table.room.status != .over
    }

    private var tableName: String { session.store.room?.title ?? TableName.fallback(code: session.code) }

    /// The server takes a rename from the host or any seated phone, in the lobby only, and never
    /// from a kitten's phone (a kitten types no names, spec §14.1).
    private var canRename: Bool {
        guard let room = session.store.room, room.status == .lobby, model.ageBand != .kitten else { return false }
        return room.youAreHost || room.seats.contains { $0.yours }
    }

    var body: some View {
        Group {
            switch page {
            case .moving:
                MoveSeatSheet(
                    session: session,
                    onBack: { show(.menu) },
                    onMovedAll: onHome,
                    onClose: onClose)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .rules:
                HowToPlaySheet { show(.menu) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .renaming:
                RenameTableView(current: tableName, onCancel: { show(.menu) }) { name in
                    session.send(.rename(name: name))
                    show(.menu)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .names:
                RenameSheet(session: session) { show(.menu) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .look:
                LookTraySheet(session: session) { show(.menu) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .menu:
                menu
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25).paced, value: page)
        .tipHost(.tableMenu, paused: page != .menu || confirmingForfeit)
        .presentationDetents(page == .menu ? [menuDetent] : page == .look ? [Self.lookDetent] : [.large], selection: $detent)
        .onAppear { if page == .menu { detent = menuDetent } }
        .onChange(of: forfeitSeat == nil) { if page == .menu { detent = menuDetent } }
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.night)
    }

    private var menu: some View {
        VStack(spacing: 22) {
            TableNameTitle(name: tableName, editable: canRename) { show(.renaming) }
                .padding(.horizontal, 20)
                .accessibilityIdentifier("menu.name")
            HStack(spacing: 18) {
                PillButton(
                    icon: settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                    color: settings.soundOn ? Palette.teal : Palette.violet, size: .medium,
                    accessibilityLabel: settings.soundOn ? "Sound on" : "Sound off"
                ) {
                    settings.soundOn.toggle()
                }
                .accessibilityIdentifier("menu.sound")
                PillButton(
                    icon: settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff,
                    color: settings.hapticsOn ? Palette.orange : Palette.violet, size: .medium,
                    accessibilityLabel: settings.hapticsOn ? "Haptics on" : "Haptics off"
                ) {
                    settings.hapticsOn.toggle()
                }
                .accessibilityIdentifier("menu.haptics")
            }
            if let onScores {
                PillButton(
                    icon: nil, color: Palette.violet, size: .medium, width: 230,
                    title: String(localized: "Scores", comment: "Table menu: open the scoreboard"),
                    accessibilityLabel: "Scores"
                ) {
                    onScores()
                }
                .accessibilityIdentifier("menu.scores")
            }
            PillButton(
                icon: nil, color: Palette.orange, size: .medium, width: 230,
                title: String(localized: "How to play", comment: "Table menu: open the rules"),
                accessibilityLabel: "How to play"
            ) {
                model.tips.used("menu.rules")
                show(.rules)
            }
            .accessibilityIdentifier("menu.rules")
            if canRenamePeople {
                PillButton(
                    icon: nil, color: Palette.teal, size: .medium, width: 230,
                    title: String(localized: "Names", comment: "Table menu: rename this phone's players"),
                    accessibilityLabel: "Change names"
                ) {
                    show(.names)
                }
                .accessibilityIdentifier("menu.names")
            }
            HStack(spacing: 18) {
                if canMove {
                    PillButton(icon: ArtName.iconMove, color: Palette.magenta, size: .medium, accessibilityLabel: "Move my seat") {
                        model.tips.used("menu.move")
                        show(.moving)
                    }
                    .accessibilityIdentifier("menu.move")
                    .tipTarget("menu.move")
                }
                if canChangeLook {
                    PillButton(icon: ArtName.Habit.iconRug, color: Palette.orange, size: .medium,
                               accessibilityLabel: "Change the look") {
                        model.tips.used("menu.look")
                        show(.look)
                    }
                    .accessibilityIdentifier("menu.look")
                    .tipTarget("menu.look")
                }
                PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, accessibilityLabel: "Home") {
                    onHome()
                }
                .accessibilityIdentifier("menu.home")
            }
            if let seat = forfeitSeat {
                PillButton(
                    icon: nil, color: Palette.refuse, size: .medium, width: 230,
                    title: String(localized: "Forfeit", comment: "Table menu: give up this game (asks first)"),
                    accessibilityLabel: "Forfeit this game"
                ) {
                    confirmingForfeit = true
                }
                .accessibilityIdentifier("menu.forfeit")
                .alert(forfeitTitle(seat), isPresented: $confirmingForfeit) {
                    Button(String(localized: "Forfeit", comment: "Forfeit confirmation: the destructive button"), role: .destructive) {
                        onForfeit(seat)
                    }
                    .accessibilityIdentifier("forfeit.confirm")
                    Button(String(localized: "Keep playing", comment: "Forfeit confirmation: back to the game"), role: .cancel) {}
                        .accessibilityIdentifier("forfeit.cancel")
                } message: {
                    Text(forfeitMessage(seat))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-table-menu")
    }

    /// "Forfeit this game?", or on a shared phone, whose seat: "Forfeit for Mia?".
    private func forfeitTitle(_ seat: Seat) -> String {
        guard let table = session.model, table.isMultiSeat else {
            return String(localized: "Forfeit this game?", comment: "Forfeit confirmation title")
        }
        let name = SeatInfo.name(table.room, seat)
        return String(localized: "Forfeit for \(name)?", comment: "Forfeit confirmation title on a shared phone: whose seat")
    }

    /// What will happen (§5.13): the game ends and the other player wins, or you are out and the
    /// rest play on.
    private func forfeitMessage(_ seat: Seat) -> String {
        guard let table = session.model else { return "" }
        let shared = table.isMultiSeat
        let name = SeatInfo.name(table.room, seat)
        switch table.forfeitOutcome(seat) {
        case .ends(let winner):
            let other = SeatInfo.name(table.room, winner)
            return String(
                localized: "\(other) wins.",
                comment: "Forfeit confirmation: with one other player left, the game ends and they win")
        case .out:
            return shared
                ? String(
                    localized: "\(name) finishes last. The rest play on.",
                    comment: "Forfeit confirmation on a shared phone: that seat is out, the rest play on")
                : String(
                    localized: "You finish last. The rest play on.",
                    comment: "Forfeit confirmation: you are out, the rest play on")
        }
    }

    private func show(_ page: Page) {
        detent = page == .menu ? menuDetent : page == .look ? Self.lookDetent : .large
        self.page = page
    }
}
