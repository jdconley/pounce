import PounceKit
import SwiftUI

/// The table menu's look tray (§9.4): rug tiles and card back tiles, from the defaults and what
/// this person unlocked with anyone. A tap changes the table for everyone; the server's refusal
/// (a change within 10 s, or an item not unlocked) shakes the tile and leaves the table as it was.
struct LookTraySheet: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession
    let onBack: () -> Void

    @State private var shaking: [String: Int] = [:]
    @State private var lastTapped: String?

    private var look: Look { session.store.room?.look ?? .standard }

    /// The server checks the unlocks of this phone's people seated here, so those are offered.
    private var unlocked: StreakView.Unlocks {
        let seated = session.model.map { table in table.mySeats.compactMap { table.room.seats[$0].person?.id } } ?? []
        return model.streaks.unlocked(for: seated)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                SheetBackButton(action: onBack)
                    .accessibilityIdentifier("look.back")
                Spacer()
                Image(ArtName.Habit.iconRug).resizable().scaledToFit().frame(width: 44)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, 18)
            row(LookTray.rugs(unlocked: unlocked, current: look), prefix: "look.rug.",
                send: { .setLook(rug: $0, back: nil) }) { item in
                Image(ArtName.Habit.rug(item.id)).resizable().scaledToFit().frame(width: 84, height: 84)
            }
            row(LookTray.backs(unlocked: unlocked, current: look), prefix: "look.back.",
                send: { .setLook(rug: nil, back: $0) }) { item in
                Image(uiImage: CardFaceFactory.backImage(ArtName.Habit.back(item.id))).resizable().scaledToFit().frame(width: 60, height: 84)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .onChange(of: session.lobbyNope) {
            guard let lastTapped else { return }
            shaking[lastTapped, default: 0] += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-look")
    }

    private func row<Art: View>(
        _ items: [LookTray.Item], prefix: String, send: @escaping (String) -> ClientMessage,
        @ViewBuilder art: @escaping (LookTray.Item) -> Art
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    Button {
                        guard !item.selected else { return }
                        Haptics.shared.tick()
                        Sound.shared.play(ArtName.Sound.sfxPop)
                        lastTapped = item.id
                        session.send(send(item.id))
                    } label: {
                        art(item)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(item.selected ? Palette.teal : Palette.violet)
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(item.selected ? .white : Palette.ink, lineWidth: item.selected ? 5 : 4)))
                            .overlay(alignment: .topTrailing) {
                                if item.selected {
                                    Image(ArtName.iconCheck).resizable().scaledToFit().frame(width: 26).offset(x: 6, y: -6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .shake(trigger: shaking[item.id] ?? 0)
                    .accessibilityAddTraits(item.selected ? .isSelected : [])
                    .accessibilityIdentifier(prefix + item.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
