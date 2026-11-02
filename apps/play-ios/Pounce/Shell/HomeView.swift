import PounceKit
import SwiftUI

/// Home: the Cat Tower hero, two fat pills (Create, Join), a row of your tables, the owner's cat
/// bottom-left (people on this phone) and a small gear (sound, haptics). After a "not now" to
/// push, a small bell top-left offers it once more (spec §10). Long-press a table to archive it;
/// the sleeping-cat tile at the end of the row opens the archived ones.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPeople = false
    @State private var showSettings = false
    @State private var showArchived = false
    @State private var heroWiggle = 0
    @State private var ownerWiggle = 0
    @State private var newGameShake = 0
    /// Notifications are already allowed (no bell then); nil until checked.
    @State private var pushAllowed: Bool?
    @State private var showPriming = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                hero(width: geo.size.width, height: geo.size.height)
                pills(width: geo.size.width)
                Spacer(minLength: 8)
                tablesRow
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(alignment: .topTrailing) { gear }
            .overlay(alignment: .topLeading) {
                if showBell { bell.transition(.scale.combined(with: .opacity)) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { ownerCorner }
        // Outside the inset: under the owner's corner and the home indicator too (inside it,
        // the art stopped above the inset and left a dark band at the bottom).
        .background { background }
        .sheet(isPresented: $showPeople) {
            PeopleSheet()
                .environment(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.night)
        }
        .sheet(isPresented: $showArchived) {
            ArchivedSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.night)
        }
        .overlay {
            if showPriming, let owner = model.people.owner {
                PushPrimingView(
                    person: owner,
                    onAllow: {
                        showPriming = false
                        Task {
                            await model.acceptPush()
                            await checkPush()
                        }
                    },
                    onNotNow: { showPriming = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: showPriming)
        .animation(.spring(duration: 0.4, bounce: 0.4).paced, value: showBell)
        .task { await model.refreshTables() }
        .task { await checkPush() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshTables() }
                Task { await checkPush() }
            }
        }
        .onChange(of: model.newGameError) { _, error in
            if error != nil {
                newGameShake += 1
                Haptics.shared.thump()
                Sound.shared.play(ArtName.Sound.sfxNope)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-home")
    }

    // MARK: pieces

    private var background: some View {
        ZStack {
            Palette.night
            Image(ArtName.homeBg)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        let side = min(width * 0.74, height * 0.34)
        return Image(ArtName.gameTile)
            .resizable()
            .scaledToFit()
            .frame(width: side * 1.1, height: side)
            .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 8)
            .onTapGesture {
                heroWiggle += 1
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxPop)
            }
            .wiggle(trigger: heroWiggle)
            .accessibilityLabel("Cat Tower")
            .accessibilityAddTraits(.isImage)
    }

    private func pills(width: CGFloat) -> some View {
        let w = min(width - 56, 360)
        return VStack(spacing: 12) {
            PillButton(
                icon: ArtName.iconPlus, color: Palette.violet, size: .large, width: w,
                title: String(localized: "Create", comment: "Home: the pill that starts a new game"),
                accessibilityLabel: "Create a game"
            ) {
                Task { await model.newGame() }
            }
            .disabled(model.isCreatingRoom)
            .opacity(model.isCreatingRoom ? 0.7 : 1)
            .shake(trigger: newGameShake)
            .accessibilityIdentifier("home.newGame")

            PillButton(
                icon: ArtName.iconKeypad, color: Palette.teal, size: .large, width: w,
                title: String(localized: "Join", comment: "Home: the pill that joins a game by code"),
                accessibilityLabel: "Join a game"
            ) {
                model.showJoin()
            }
            .accessibilityIdentifier("home.join")
        }
    }

    @ViewBuilder private var tablesRow: some View {
        let items = model.homeItems
        let archivedCount = model.archivedItems.count
        if !items.isEmpty || archivedCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        TableCard(item: item) {
                            model.open(code: item.id, intent: .rejoin)
                        }
                        .contextMenu {
                            Button {
                                archive(item.id)
                            } label: {
                                Label(
                                    String(localized: "Archive", comment: "Home: a table's long-press menu item that hides it"),
                                    systemImage: "archivebox")
                            }
                            .accessibilityIdentifier("home.table.archive")
                        }
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .accessibilityAction(named: Text("Archive", comment: "VoiceOver: hides a table from Home")) {
                            archive(item.id)
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    if archivedCount > 0 {
                        ArchivedTile(count: archivedCount, cat: model.people.owner?.cat ?? 0) { showArchived = true }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.35), value: items.map(\.id))
                .animation(.spring(duration: 0.4, bounce: 0.35), value: archivedCount)
                // Room for the glow and the bounce so neither is clipped by the scroll view.
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .scrollClipDisabled()
            .frame(height: TableCard.size.height + 44)
            .accessibilityIdentifier("home.tables")
        }
    }

    private func archive(_ code: String) {
        Haptics.shared.drop()
        Sound.shared.play(ArtName.Sound.sfxWhoosh)
        model.archive(code: code)
    }

    private var showBell: Bool {
        settings.pushDeclinedOnce && !settings.pushReoffered && pushAllowed == false && !showPriming
    }

    private func checkPush() async {
        guard let push = model.push else { return }
        pushAllowed = PushCoordinator.isAllowed(await push.authorizationStatus())
    }

    /// Re-offers push once: the priming screen again, then the system prompt (or its settings page).
    private var bell: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            settings.pushReoffered = true
            showPriming = true
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.magenta.mix(with: .white, by: 0.3), Palette.magenta],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay {
                    Image(ArtName.iconBell)
                        .resizable().scaledToFit()
                        .padding(8)
                }
                .frame(width: 48, height: 48)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bounceLoop(active: true)
        .padding(.leading, 14)
        .padding(.top, 4)
        .accessibilityLabel(Text("Turn on turn notifications", comment: "VoiceOver: Home's bell that offers push again"))
        .accessibilityIdentifier("home.bell")
    }

    private var gear: some View {
        Button {
            Haptics.shared.tick()
            showSettings = true
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.sky.mix(with: .white, by: 0.3), Palette.sky],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay {
                    Image(ArtName.iconGear)
                        .resizable().scaledToFit()
                        .padding(9)
                }
                .frame(width: 48, height: 48)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
        .padding(.top, 4)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("home.settings")
        .popover(isPresented: $showSettings, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            settingsPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var settingsPopover: some View {
        HStack(spacing: 16) {
            PillButton(
                icon: settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                color: settings.soundOn ? Palette.teal : Palette.violet, size: .small,
                accessibilityLabel: settings.soundOn ? "Sound on" : "Sound off"
            ) {
                settings.soundOn.toggle()
            }
            .accessibilityIdentifier("settings.sound")
            PillButton(
                icon: settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff,
                color: settings.hapticsOn ? Palette.orange : Palette.violet, size: .small,
                accessibilityLabel: settings.hapticsOn ? "Haptics on" : "Haptics off"
            ) {
                settings.hapticsOn.toggle()
            }
            .accessibilityIdentifier("settings.haptics")
        }
        .padding(18)
        .background(Palette.night)
    }

    /// The owner's cat on a cushion, bottom-left. Tap for the people on this phone.
    private var ownerCorner: some View {
        HStack {
            Button {
                ownerWiggle += 1
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxPop)
                showPeople = true
            } label: {
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Palette.magenta.mix(with: .white, by: 0.25), Palette.magenta,
                                         Palette.magenta.mix(with: Palette.ink, by: 0.3)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 5))
                        .frame(width: 150, height: 58)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
                    Image(ArtName.cat(model.people.owner?.cat ?? 0, .idle))
                        .resizable().scaledToFit()
                        .frame(width: 112, height: 112)
                        .shadow(color: Palette.ink.opacity(0.35), radius: 0, x: 0, y: 4)
                        .offset(y: -22)
                        .wiggle(trigger: ownerWiggle)
                }
                .frame(width: 150, height: 142, alignment: .bottom)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("People on this phone"))
            .accessibilityIdentifier("home.people")
            Spacer()
        }
        .padding(.leading, 12)
        .padding(.bottom, 2)
    }
}
