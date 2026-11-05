import PounceKit
import SwiftUI

/// The table's paw menu (`table.menu`): the table's name (tap to rename it), sound, haptics, how
/// to play, names, move my seat, home. Renaming the table grows the sheet into `RenameTableView`,
/// names (this phone's players) into `RenameSheet`, move my seat into `MoveSeatSheet`, how to play
/// into `HowToPlaySheet`.
struct TableMenuSheet: View {
    @Environment(Settings.self) private var settings
    let session: RoomSession
    let onHome: () -> Void
    let onClose: () -> Void

    private enum Page { case menu, moving, rules, renaming, names, look }

    @State private var page = Self.firstPage
    @State private var detent: PresentationDetent = Self.firstPage == .look ? Self.lookDetent : Self.menuDetent

    /// `-show-look` (DEBUG, screenshots) opens on the look tray.
    private static var firstPage: Page {
        #if DEBUG
        if CommandLine.arguments.contains("-show-look") { return .look }
        #endif
        return .menu
    }

    static let menuDetent = PresentationDetent.height(440)
    static let lookDetent = PresentationDetent.height(380)

    /// The look tray is offered on a server with looks (streaks on), to a phone seated here.
    private var canChangeLook: Bool {
        guard let room = session.store.room, room.look != nil else { return false }
        return room.seats.contains { $0.yours && $0.kind == .human }
    }

    /// This phone's players can change their names until the game is over.
    private var canRenamePeople: Bool { canMove }

    private var canMove: Bool {
        guard let table = session.model else { return false }
        return !table.mySeats.isEmpty && table.room.status != .over
    }

    private var tableName: String { session.store.room?.title ?? TableName.fallback(code: session.code) }

    /// The server takes a rename from the host or any seated phone, until the game is over.
    private var canRename: Bool {
        guard let room = session.store.room, room.status != .over else { return false }
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
        .presentationDetents(page == .menu ? [Self.menuDetent] : page == .look ? [Self.lookDetent] : [.large], selection: $detent)
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
            PillButton(
                icon: nil, color: Palette.orange, size: .medium, width: 230,
                title: String(localized: "How to play", comment: "Table menu: open the rules"),
                accessibilityLabel: "How to play"
            ) {
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
                    PillButton(icon: ArtName.iconMove, color: Palette.magenta, size: .medium, accessibilityLabel: "Move my seat to another phone") {
                        show(.moving)
                    }
                    .accessibilityIdentifier("menu.move")
                }
                if canChangeLook {
                    PillButton(icon: ArtName.Habit.iconRug, color: Palette.orange, size: .medium,
                               accessibilityLabel: "Change the rug and card backs") {
                        show(.look)
                    }
                    .accessibilityIdentifier("menu.look")
                }
                PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, accessibilityLabel: "Home") {
                    onHome()
                }
                .accessibilityIdentifier("menu.home")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-table-menu")
    }

    private func show(_ page: Page) {
        detent = page == .menu ? Self.menuDetent : page == .look ? Self.lookDetent : .large
        self.page = page
    }
}
