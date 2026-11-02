import PounceKit
import SwiftUI

/// The table's paw menu (`table.menu`): sound, haptics, move my seat, home. Move my seat grows
/// the sheet into `MoveSeatSheet`.
struct TableMenuSheet: View {
    @Environment(Settings.self) private var settings
    let session: RoomSession
    let onHome: () -> Void
    let onClose: () -> Void

    @State private var moving = false
    @State private var detent: PresentationDetent = Self.menuDetent

    static let menuDetent = PresentationDetent.height(220)

    private var canMove: Bool {
        guard let table = session.model else { return false }
        return !table.mySeats.isEmpty && table.room.status != .over
    }

    var body: some View {
        Group {
            if moving {
                MoveSeatSheet(
                    session: session,
                    onBack: { show(moving: false) },
                    onMovedAll: onHome,
                    onClose: onClose)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                menu
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25).paced, value: moving)
        .presentationDetents(moving ? [.large] : [Self.menuDetent], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.night)
    }

    private var menu: some View {
        VStack(spacing: 22) {
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
            HStack(spacing: 18) {
                if canMove {
                    PillButton(icon: ArtName.iconMove, color: Palette.magenta, size: .medium, accessibilityLabel: "Move my seat to another phone") {
                        show(moving: true)
                    }
                    .accessibilityIdentifier("menu.move")
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

    private func show(moving: Bool) {
        detent = moving ? .large : Self.menuDetent
        self.moving = moving
    }
}
