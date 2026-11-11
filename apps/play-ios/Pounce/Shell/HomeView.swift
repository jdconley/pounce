import PounceKit
import SwiftUI

/// Home: the Cat Tower hero, two fat pills (Create, Join), a row of your tables, the owner's cat
/// bottom-left (people on this phone) and a small gear (sound, haptics, how to play). After a
/// "not now" to push, a small bell top-left offers it once more (spec §10). Long-press a table
/// to archive it; the sleeping-cat tile at the end of the row opens the archived ones.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPeople = false
    @State private var showSettings = false
    @State private var showArchived = false
    @State private var showRules = false
    @State private var heroWiggle = 0
    @State private var ownerWiggle = 0
    @State private var newGameShake = 0
    /// Notifications are fully allowed (no bell then; provisional still gets it, §12.5); nil until checked.
    @State private var pushAllowed: Bool?
    @State private var showPriming = false
    /// The streak badge's cloud was tapped: the sign-in offer is up (§10.5).
    @State private var streakSignIn = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            Group {
                if sizeClass == .regular {
                    roomy(geo.size)
                } else {
                    VStack(spacing: 14) {
                        // Under the bell and gear row, the phone's full width, so a connection or two shows whole.
                        if showStrip { strip(scale: 1).padding(.top, 40) }
                        hero(width: geo.size.width, height: geo.size.height * (showStrip ? 0.78 : 1))
                        pills(width: geo.size.width)
                        Spacer(minLength: 8)
                        tablesRow
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(alignment: .topTrailing) { gear }
            .overlay(alignment: .top) {
                if sizeClass == .regular, showStrip {
                    strip(scale: 1.3)
                        .frame(maxWidth: max(geo.size.width - 180, 300))
                        .padding(.top, 2)
                }
            }
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
        .sheet(isPresented: $showSettings) {
            GearSheet {
                showSettings = false
                // The rules wait for the gear sheet to finish going away.
                Task {
                    try? await Task.sleep(for: Pace.duration(.milliseconds(450)))
                    showRules = true
                }
            }
            .environment(model)
            .environment(settings)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.night)
        }
        .sheet(isPresented: $showArchived) {
            ArchivedSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.night)
        }
        .sheet(isPresented: $showRules) {
            HowToPlaySheet { showRules = false }
                .environment(model)
                // A big page on iPad, so the rules get two columns (no effect on a phone).
                .presentationSizing(.page)
                .presentationDetents([.large])
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
        .task { await model.refreshStreaks() }
        .overlay {
            if streakSignIn, let owner = model.people.owner {
                ZStack {
                    Palette.night.opacity(0.85).ignoresSafeArea().onTapGesture { streakSignIn = false }
                    SignInOffer(identifier: "home.streak.signin") {
                        Task {
                            await model.account.signIn(owner)
                            streakSignIn = false
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: streakSignIn)
        .task { await checkPush() }
        #if DEBUG
        // `-show-rules` / `-show-people`: open that sheet at launch (iPad screenshots).
        .task {
            let args = CommandLine.arguments
            try? await Task.sleep(for: .milliseconds(600))
            if args.contains("-show-rules") { showRules = true }
            if args.contains("-show-people") { showPeople = true }
            if args.contains("-show-gear") { showSettings = true }
        }
        #endif
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

    /// The streak strip (trophy room design §1), once the server said streaks are on: your own
    /// streak, your connections and the plus, which is there even before anyone is connected.
    private var showStrip: Bool { model.streaks.enabled == true }

    private func strip(scale: CGFloat) -> some View {
        StreakStripView(scale: scale) { streakSignIn = true }
            .transition(.scale.combined(with: .opacity))
    }

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
        // The game tile opens How to play, with a word under it so it says what it does.
        return Button {
            heroWiggle += 1
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            showRules = true
        } label: {
            Image(ArtName.gameTile)
                .resizable()
                .scaledToFit()
                .frame(width: side * 1.1, height: side)
                .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 8)
                .wiggle(trigger: heroWiggle)
                .overlay(alignment: .bottom) {
                    Text("How to play", comment: "Home: caption on the game tile, which opens the rules")
                        .font(.system(.callout, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.orange).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                        .offset(y: 16)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cat Tower")
        .accessibilityHint("Opens how to play")
        .accessibilityIdentifier("home.hero")
    }

    /// `wide`: each pill this wide, side by side (roomy portrait); else stacked.
    private func pills(width: CGFloat, wide: CGFloat? = nil) -> some View {
        let w = wide ?? min(width - 56, 360)
        let stack = wide == nil ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 20))
        return VStack(spacing: 10) {
            if let error = model.newGameError {
                Text(Self.createFailedMessage(error))
                    .font(.system(.callout, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("home.createError")
            }
            stack {
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
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: model.newGameError)
    }

    /// Why a new game didn't start, in words.
    static func createFailedMessage(_ error: APIError) -> String {
        switch error {
        case .transport:
            String(localized: "No internet. Check your connection and try again.", comment: "Home: Create failed offline")
        case .rateLimited:
            String(localized: "Too many tries. Wait a little and try again.", comment: "Home: Create was rate limited")
        default:
            String(localized: "Couldn't start a game. Try again.", comment: "Home: Create failed")
        }
    }

    @ViewBuilder private var tablesRow: some View {
        let items = shownItems
        let archivedCount = model.archivedItems.count
        if !items.isEmpty || archivedCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        TableCard(
                            item: item, people: model.tablePeople(item), streakPaw: model.streaks.completesToday(code: item.id)
                        ) {
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

    // MARK: roomy (iPad)

    /// A regular-width window. Wide (landscape): the hero and the two pills in a column on the
    /// left, your tables as a grid in a panel on the right. Tall (portrait): a bigger hero, the
    /// pills side by side, and the tables grid under them. With no tables the hero and pills
    /// stand alone in the middle.
    @ViewBuilder private func roomy(_ size: CGSize) -> some View {
        let hasTables = !shownItems.isEmpty || model.archivedItems.count > 0
        if Roomy.sideBySide(size) && hasTables {
            let left = min(size.width * 0.36, 480)
            HStack(alignment: .center, spacing: 36) {
                VStack(spacing: 26) {
                    hero(width: left, height: size.height * 1.15)
                    pills(width: left + 56)
                }
                .frame(width: left)
                tablesPanel
                    .frame(maxWidth: 720, maxHeight: min(size.height - 40, 640))
            }
            .padding(.horizontal, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let width = min(size.width - 80, 900)
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                hero(width: min(size.width, 640), height: size.height * (hasTables ? 0.8 : 1.25))
                pills(width: 0, wide: min((width - 20) / 2, 340))
                if hasTables {
                    tablesPanel
                        .frame(width: width)
                        .padding(.top, 10)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The tables Home shows (DEBUG: `-demo-home` puts sample tables here for screenshots).
    private var shownItems: [HomeTableItem] {
        #if DEBUG
        if CommandLine.arguments.contains("-demo-home") { return Self.demoItems }
        #endif
        return model.homeItems
    }

    /// Your tables as a grid of cards in a panel, hugging them, and scrolling once there are
    /// more than fit.
    private var tablesPanel: some View {
        RoomyPanel {
            ViewThatFits(in: .vertical) {
                tablesGrid
                ScrollView(.vertical, showsIndicators: false) { tablesGrid }
                    .scrollBounceBehavior(.basedOnSize)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.tables")
        }
    }

    private var tablesGrid: some View {
        let items = shownItems
        let archivedCount = model.archivedItems.count
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.roomyCard.width, maximum: Self.roomyCard.width + 30), spacing: 22)],
            spacing: 26
        ) {
            ForEach(items) { item in
                Self.roomyScaled(tableCard(item))
            }
            if archivedCount > 0 {
                Self.roomyScaled(ArchivedTile(count: archivedCount, cat: model.people.owner?.cat ?? 0) { showArchived = true })
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: items.map(\.id))
        .animation(.spring(duration: 0.4, bounce: 0.35), value: archivedCount)
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
    }

    /// Table cards are drawn this much bigger on a roomy Home.
    private static let roomyScale: CGFloat = 1.2
    private static var roomyCard: CGSize {
        CGSize(width: TableCard.size.width * roomyScale, height: TableCard.size.height * roomyScale)
    }

    private static func roomyScaled(_ card: some View) -> some View {
        card
            .scaleEffect(roomyScale)
            .frame(width: roomyCard.width, height: roomyCard.height)
    }

    private func tableCard(_ item: HomeTableItem) -> some View {
        TableCard(item: item, people: model.tablePeople(item), streakPaw: model.streaks.completesToday(code: item.id)) {
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

    #if DEBUG
    private static let demoItems: [HomeTableItem] = {
        // Your seat first, then the others: Mia, Kiki and Nova are `-demo-streaks`' connections.
        func seats(_ others: [(String, Int)], open: Int = 0, bots: Int = 0) -> [CachedSeat] {
            [CachedSeat(kind: .human, name: "You", cat: 2, yours: true)]
                + others.map { CachedSeat(kind: .human, name: $0.0, cat: $0.1) }
                + Array(repeating: CachedSeat(kind: .bot), count: bots)
                + Array(repeating: CachedSeat(kind: .open), count: open)
        }
        return [
            HomeTableItem(id: "M3W7Z", name: "Friday Night Cats", yourTurn: true, status: "playing", seats: seats([("Mia", 2)]), turnCat: 2, updatedAt: 0),
            HomeTableItem(id: "K9PQR", name: "Sunday Brunch", yourTurn: false, status: "playing", seats: seats([("Biscuit", 4), ("Kiki", 6)]), turnCat: 4, updatedAt: 0),
            HomeTableItem(id: "TB4XN", name: "Couch League", yourTurn: false, status: "lobby", seats: seats([], open: 2), turnCat: nil, updatedAt: 0),
            HomeTableItem(id: "GH2VD", name: "Rematch", yourTurn: false, status: "over", seats: seats([], bots: 1), turnCat: 3, updatedAt: 0),
            HomeTableItem(id: "WZ8CM", name: "Road Trip", yourTurn: true, status: "playing", seats: seats([("Pickle", 1), ("Nova", 5), ("Clementine", 3)]), turnCat: 2, updatedAt: 0),
        ]
    }()
    #endif

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
        pushAllowed = !PushPolicy.offersFullPrompt(PushCoordinator.mirror(await push.authorizationStatus()))
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
