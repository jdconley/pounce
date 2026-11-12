import PounceKit
import SwiftUI

/// Home: the game shelf (one card per `GameCatalog` game; a card you can play starts a table),
/// your tables, the streak strip, Join, the owner's cat bottom-left (people on this phone) and a
/// small gear (sound, haptics, how to play). After a "not now" to push, a small bell by the name
/// offers it once more (spec §10). Long-press a table to archive it; the sleeping-cat tile at
/// the end of the tables opens the archived ones.
///
/// What leads (`HomeLead`): with a game going your tables sit above the shelf, and the ones
/// waiting on you glow; with no table, or only finished ones, the shelf leads.
///
/// A phone scrolls one column: games you can play as posters, games on the way as tickets. An
/// iPad lays the shelf out as a grid of posters, beside your tables when it is on its side.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPeople = false
    @State private var showSettings = false
    @State private var showArchived = false
    @State private var showRules = false
    @State private var ownerWiggle = 0
    @State private var newGameShake = 0
    /// Notifications are fully allowed (no bell then; provisional still gets it, §12.5); nil until checked.
    @State private var pushAllowed: Bool?
    @State private var showPriming = false
    /// The streak badge's cloud was tapped: the sign-in offer is up (§10.5).
    @State private var streakSignIn = false
    /// The column has scrolled up past the top bar (it fades out there), or runs on under the
    /// bottom bar (which gets a shade behind it), so neither tangles with it.
    @State private var shadeTop = false
    @State private var shadeBottom = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var sectionTitleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var roomyTitleSize: CGFloat = 30

    /// Home's one-time "Keep your streak if you change phones" card, under no other overlay.
    private var showSignInPrompt: Bool {
        !showPriming && !streakSignIn && model.people.owner != nil
            && SignInPrompt.shows(
                band: model.ageBand, signedIn: model.account.isSignedIn, offersSignIn: model.account.offersSignIn,
                pairs: model.streaks.pairs.count, dismissed: settings.signInPromptSeen)
    }

    var body: some View {
        GeometryReader { geo in
            // A short window (a small phone, a small iPad on its side) gets a smaller bottom bar,
            // so more of the column shows.
            let bar = Self.bottomBarHeight(short: geo.size.height < (sizeClass == .regular ? 760 : 700))
            let top = topBarHeight
            let room = CGSize(width: geo.size.width, height: max(0, geo.size.height - top))
            // In reading order, which is VoiceOver's: the top bar, the column, the bottom bar.
            VStack(spacing: 0) {
                topBar.frame(height: top)
                // The column fades out under the top bar once it has scrolled, and runs on under
                // the bottom bar, where its own padding keeps it clear at rest.
                Group {
                    if sizeClass == .regular {
                        roomy(room, bar: bar)
                    } else {
                        compact(room, bar: bar)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask { columnMask }
            }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    bottomShade(bar: bar, beyond: geo.safeAreaInsets.bottom)
                    bottomBar(width: geo.size.width, height: bar)
                }
            }
        }
        // Under the bars, the status bar and the home indicator too.
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
        .animation(.easeOut(duration: 0.2).paced, value: shadeTop)
        .animation(.easeOut(duration: 0.2).paced, value: shadeBottom)
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
        // Once a pair formed, a signed-out adult is told in words what signing in keeps (launch review).
        .overlay {
            if showSignInPrompt { SignInPromptCard().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.25).paced, value: showSignInPrompt)
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

    private var hasTables: Bool { !shownItems.isEmpty || model.archivedItems.count > 0 }
    private var lead: HomeLead { HomeLead.pick(shownItems) }

    // MARK: bars

    /// The top bar: the name and the gear, and on an iPad the streak strip between them.
    private var topBarHeight: CGFloat { sizeClass == .regular && showStrip ? 112 : 58 }
    /// How much of the column the bottom bar covers: the owner's cat on its cushion.
    private static func bottomBarHeight(short: Bool) -> CGFloat { short ? 108 : 144 }

    /// Pinned to the top: the app's name, the bell when push is on offer again, the gear. On an
    /// iPad the streak strip sits in the middle of it.
    private var topBar: some View {
        let roomy = sizeClass == .regular
        return HStack(spacing: 4) {
            OutlinedText("Pounce", size: roomy ? 38 : 30, width: roomy ? 4 : 3.5)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.name")
            if showBell { bell.transition(.scale.combined(with: .opacity)) }
            Spacer(minLength: 0)
            gear
        }
        .padding(.leading, roomy ? 22 : 16)
        .padding(.trailing, roomy ? 14 : 8)
        .padding(.top, 2)
        .frame(height: 58)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if roomy, showStrip {
                strip(scale: 1.3)
                    .padding(.leading, 170)
                    .padding(.trailing, 84)
                    .padding(.top, -6)
            }
        }
    }

    /// Pinned to the bottom: the owner's cat on its cushion, and Join across from it, where a
    /// thumb is. With no tables yet, practice sits by Join (over it on a phone).
    private func bottomBar(width: CGFloat, height: CGFloat) -> some View {
        let short = height < 140
        return HStack(alignment: .bottom, spacing: 0) {
            ownerCorner
                .scaleEffect(short ? 0.74 : 1, anchor: .bottomLeading)
                .frame(width: short ? 111 : 150, height: height - 2, alignment: .bottomLeading)
            Spacer(minLength: 12)
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .bottom, spacing: 16) {
                        practicePill(width: 360, size: .medium)
                        joinPill(size: .large, width: 250)
                    }
                    .padding(.bottom, 6)
                } else {
                    // What the cushion leaves, up to a comfortable pill.
                    let pill = max(120, min(230, width - (short ? 151 : 190)))
                    VStack(spacing: short ? 6 : 8) {
                        practicePill(width: pill, size: .small, short: true)
                        joinPill(size: short ? .small : .medium, width: pill)
                    }
                    .padding(.bottom, 1)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: shownItems.isEmpty)
        }
        .padding(.leading, 12)
        .padding(.trailing, sizeClass == .regular ? 24 : 16)
        .padding(.bottom, 2)
    }

    /// What shows of the column. At rest, all of it and a little more (a strip badge may poke up
    /// past its edge); once it has scrolled, it fades out under the top bar.
    private var columnMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(shadeTop ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 20)
            Color.black
        }
        .padding(.top, shadeTop ? 0 : -60)
        .padding(.horizontal, -60)
        .padding(.bottom, -400)
    }

    /// Behind the bottom bar while the column runs on under it: it fades out above the cat.
    private func bottomShade(bar: CGFloat, beyond: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: Palette.night.opacity(0), location: 0),
                .init(color: Palette.night.opacity(0.9), location: 0.22),
                .init(color: Palette.night, location: 0.36),
                .init(color: Palette.night, location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
            .frame(height: bar + 64 + beyond)
            .offset(y: beyond)
            .opacity(shadeBottom ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func joinPill(size: PillSize, width: CGFloat) -> some View {
        PillButton(
            icon: ArtName.iconKeypad, color: Palette.teal, size: size, width: width,
            title: String(localized: "Join", comment: "Home: the pill that joins a game by code"),
            accessibilityLabel: "Join a game"
        ) {
            model.showJoin()
        }
        .accessibilityIdentifier("home.join")
    }

    // MARK: sections

    /// A section's name in toy lettering, with room for a chip after it.
    private func sectionTitle(_ title: String, @ViewBuilder chip: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .center, spacing: 10) {
            OutlinedText(
                title, size: sizeClass == .regular ? roomyTitleSize : sectionTitleSize, width: sizeClass == .regular ? 3.5 : 3,
                lines: 2, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            chip()
            Spacer(minLength: 0)
        }
    }

    private var shelfTitle: String {
        hasTables
            ? String(localized: "Start a new game", comment: "Home: the game shelf's title when you already have tables")
            : String(localized: "Pick a game", comment: "Home: the game shelf's title with no tables yet")
    }

    private static let tablesTitle = String(localized: "Your tables", comment: "Home: the title over your tables")

    /// "Your turn" beside the tables' title while any of them waits on this phone.
    @ViewBuilder private var turnChip: some View {
        let waiting = HomeLead.waiting(shownItems)
        if waiting > 0 {
            Text(
                waiting == 1
                    ? String(localized: "Your turn", comment: "Home: one table waits on you")
                    : String(localized: "Your turn at \(waiting) tables", comment: "Home: this many tables wait on you")
            )
            .font(.system(sizeClass == .regular ? .headline : .footnote, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.orange).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .fixedSize()
            .accessibilityIdentifier("home.yourTurn")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Why Create failed, over the shelf.
    @ViewBuilder private var createError: some View {
        if let error = model.newGameError {
            Text(Self.createFailedMessage(error))
                .font(.system(.callout, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                .frame(maxWidth: .infinity)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("home.createError")
        }
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

    // MARK: the shelf

    /// The games on the shelf, top to bottom (DEBUG: `-shelf all` unlocks every game, `-shelf six`
    /// fills the shelf, both for looking at layouts).
    private var shelf: [GameCatalog.Entry] {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-shelf"), args.indices.contains(i + 1) {
            if args[i + 1] == "all" { return GameCatalog.shelf(GameCatalog.all.map { $0.unlocked() }) }
            if args[i + 1] == "six" { return GameCatalog.shelf(Self.demoShelf) }
        }
        #endif
        return GameCatalog.shelf()
    }

    /// One game's card. The game the server deals keeps Create's old id, `home.newGame`: tapping
    /// it is how a table starts.
    private func gameCard(
        _ game: GameCatalog.Entry, index: Int, layout: GameCard.Layout, coverRatio: CGFloat, roomy: Bool = false,
        playUnder: Bool = false
    ) -> some View {
        let dealt = game.id == GameCatalog.dealt.id
        let bigType = typeSize.isAccessibilitySize
        return VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                GameCard(
                    game: game, layout: layout, coverRatio: coverRatio, roomy: roomy, playUnder: playUnder,
                    busy: model.isCreatingRoom && game.isAvailable, identifier: dealt ? "home.newGame" : nil
                ) {
                    Task { await model.newGame(game) }
                }
                // Cat Tower's rules, where the old hero tile had them.
                if dealt, !bigType { rulesChip(roomy: roomy).padding(roomy ? 16 : 12) }
            }
            // At a big text size the chip would hide the cover, so it gets a row of its own.
            if dealt, bigType { rulesChip(roomy: roomy, wide: true) }
        }
        .shake(trigger: dealt ? newGameShake : 0)
        .shelfEntrance(index: index)
    }

    private func rulesChip(roomy: Bool, wide: Bool = false) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            showRules = true
        } label: {
            Text("How to play", comment: "Home: the chip on Cat Tower's card that opens the rules")
                .font(.system(wide ? .body : roomy ? .headline : .footnote, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, wide ? 9 : 5)
                .frame(maxWidth: wide ? .infinity : nil)
                .background(
                    Capsule().fill(Palette.orange)
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: wide ? 4 : 3))
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3))
                // A finger-sized target around a small chip.
                .padding(6)
                .contentShape(Rectangle())
                .padding(-6)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens how to play")
        .accessibilityIdentifier("home.hero")
    }

    /// A phone's shelf: one column. Games you can play are posters; games on the way are tickets.
    private var shelfColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(shelfTitle)
            createError
            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, game in
                gameCard(game, index: index, layout: game.isAvailable ? .poster : .ticket, coverRatio: 2.3)
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: model.newGameError)
    }

    /// An iPad's shelf: posters in as many columns as fit `width` (three at most), each row as
    /// tall as its tallest card. `height`: what the window leaves for the first row; on a short
    /// window (a small iPad on its side) the posters narrow until that row shows whole.
    private func shelfGrid(width: CGFloat, height: CGFloat? = nil) -> some View {
        let games = shelf
        let gap: CGFloat = 22
        let fit: CGFloat = typeSize.isAccessibilitySize ? 380 : 240
        let columns = max(1, min(3, games.count, Int((width + gap) / (fit + gap))))
        // A poster is its 3:2 cover over a band of about this height, under the shelf's title.
        let share: CGFloat = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        var column = share
        if let height, !typeSize.isAccessibilitySize {
            let tallest: CGFloat = (height - 66 - 200) * 1.5
            column = min(share, max(fit, tallest))
        }
        let gridWidth: CGFloat = column * CGFloat(columns) + gap * CGFloat(columns - 1)
        let rows = stride(from: 0, to: games.count, by: columns).map { Array(games[$0..<min($0 + columns, games.count)]) }
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle(shelfTitle)
            createError
            Grid(alignment: .top, horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { row, games in
                    GridRow {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            gameCard(game, index: row * columns + index, layout: .poster, coverRatio: 1.5, roomy: column >= 300, playUnder: true)
                                .frame(width: column)
                        }
                    }
                }
            }
            // Each row as tall as its tallest card and no taller, whatever space is on offer.
            .fixedSize(horizontal: false, vertical: true)
        }
        // As wide as its columns, so the title lines up with the first card.
        .frame(width: gridWidth)
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: model.newGameError)
    }

    /// With no tables yet, a way to just try the game: a practice round against the House Cat.
    /// `short`: the one word, for the phone's bottom bar (VoiceOver still hears it all).
    @ViewBuilder private func practicePill(width: CGFloat, size: PillSize = .medium, short: Bool = false) -> some View {
        if shownItems.isEmpty {
            PillButton(
                icon: ArtName.badgeBot, color: Palette.magenta, size: size, width: width,
                title: short
                    ? String(localized: "Practice", comment: "Home, with no tables, on a phone: starts a game against the computer player")
                    : String(localized: "Practice with the House Cat", comment: "Home, with no tables: starts a game against the computer player"),
                accessibilityLabel: "Practice with the House Cat"
            ) {
                Task { await model.newGame(practice: true) }
            }
            .disabled(model.isCreatingRoom)
            .opacity(model.isCreatingRoom ? 0.7 : 1)
            .accessibilityIdentifier("home.practice")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: your tables

    /// Shown once, by the tables: a table can be put away with a long press.
    @ViewBuilder private var archiveHint: some View {
        if !settings.archiveHintSeen, !shownItems.isEmpty {
            HintBubble(
                text: String(localized: "Press and hold a table to archive it.", comment: "Home: the one-time hint about the long-press menu on a table card")
            ) {
                settings.archiveHintSeen = true
            }
            .accessibilityIdentifier("home.hint.archive")
            .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
        }
    }

    /// A phone's tables: their title, then one row that scrolls sideways.
    @ViewBuilder private var tablesSection: some View {
        if hasTables {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle(Self.tablesTitle) { turnChip }
                    .padding(.horizontal, 20)
                archiveHint
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                tablesRow
            }
            .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: settings.archiveHintSeen)
            .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: HomeLead.waiting(shownItems))
        }
    }

    private var tablesRow: some View {
        let items = shownItems
        let archivedCount = model.archivedItems.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    tableCard(item)
                }
                if archivedCount > 0 {
                    ArchivedTile(count: archivedCount, cat: model.people.owner?.cat ?? 0) { showArchived = true }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.35), value: items.map(\.id))
            .animation(.spring(duration: 0.4, bounce: 0.35), value: archivedCount)
            // Room for the glow and the bounce so neither is clipped by the scroll view.
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
        .scrollClipDisabled()
        .frame(height: TableCard.size.height + 34)
        .accessibilityIdentifier("home.tables")
    }

    // MARK: compact (iPhone)

    /// A phone, or a narrow iPad window: one scrolling column between the two bars. The strip
    /// first, then whatever leads.
    private func compact(_ size: CGSize, bar: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                if showStrip { strip(scale: 1).padding(.top, -16).padding(.bottom, -6) }
                // A newer version, or a table waiting behind one (app updates design §4.1, §4.2).
                HomeUpdates()
                if lead == .tables { tablesSection }
                shelfColumn
                if lead == .shelf { tablesSection }
            }
            .padding(.top, 4)
            .padding(.bottom, bar + 8)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .shadesBars(top: $shadeTop, bottom: $shadeBottom)
    }

    // MARK: roomy (iPad)

    /// A regular-width window. Wide (landscape) with tables: two columns, your tables in a panel
    /// and the shelf beside it, whichever leads on the leading side. Otherwise one column: what
    /// leads, then the other. It scrolls when it has to and sits in the middle when it doesn't.
    private func roomy(_ size: CGSize, bar: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            // A newer version, or a table waiting behind one, over the columns (app updates design).
            VStack(spacing: 24) {
            HomeUpdates(roomy: true)
            Group {
                if Roomy.sideBySide(size) && hasTables {
                    let tablesWidth = min(size.width * 0.44, 602)
                    let shelfWidth = size.width - 96 - 36 - tablesWidth
                    HStack(alignment: .top, spacing: 36) {
                        if lead == .tables { tablesColumn.frame(width: tablesWidth) }
                        shelfGrid(width: shelfWidth)
                            .frame(width: shelfWidth)
                        if lead == .shelf { tablesColumn.frame(width: tablesWidth) }
                    }
                } else {
                    let width = min(size.width - 80, 900)
                    VStack(spacing: 30) {
                        if lead == .tables { tablesColumn }
                        shelfGrid(width: width, height: size.height - bar - 20)
                        if lead == .shelf, hasTables { tablesColumn }
                    }
                    .frame(width: width)
                }
            }
            }
            .padding(.top, 10)
            .padding(.bottom, bar + 10)
            .frame(maxWidth: .infinity, minHeight: size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .shadesBars(top: $shadeTop, bottom: $shadeBottom)
    }

    /// Your tables on an iPad: their title over the panel.
    private var tablesColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(Self.tablesTitle) { turnChip }
            archiveHint.frame(maxWidth: 460)
            tablesPanel
        }
        .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: settings.archiveHintSeen)
    }

    /// The tables Home shows (DEBUG: `-demo-home` puts sample tables here for screenshots).
    private var shownItems: [HomeTableItem] {
        #if DEBUG
        if CommandLine.arguments.contains("-demo-home") { return Self.demoItems }
        #endif
        return model.homeItems
    }

    /// Your tables as a grid of cards in a panel that hugs them (Home scrolls, the panel doesn't).
    private var tablesPanel: some View {
        RoomyPanel {
            tablesGrid
                .frame(maxWidth: .infinity)
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
                settings.archiveHintSeen = true
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
    /// `-shelf six`: a full shelf, to check that six games need no new layout. The four extra
    /// games are made up and borrow the two real covers.
    private static let demoShelf: [GameCatalog.Entry] = {
        func game(_ id: String, _ title: String, _ pitch: String, _ players: ClosedRange<Int>, _ art: String,
                  _ tint: GameCatalog.Entry.Tint, soon: Bool = false) -> GameCatalog.Entry {
            GameCatalog.Entry(
                id: id, title: title, pitch: pitch, minPlayers: players.lowerBound, maxPlayers: players.upperBound, art: art,
                tint: tint, availability: soon ? .comingSoon : .available)
        }
        return [
            GameCatalog.catTower, GameCatalog.tiles.unlocked(),
            game("demo-a", "Yarn Dash", "Race to the last loop.", 2...4, ArtName.gameCatTower, .magenta),
            game("demo-b", "Nap Stack", "Pile up without a wobble.", 2...5, ArtName.gameTiles, .orange),
            game("demo-c", "Laser Tag", "Chase the dot together.", 3...6, ArtName.gameCatTower, .sky, soon: true),
            game("demo-d", "Box Fort", "Build it before bedtime.", 2...2, ArtName.gameTiles, .lime, soon: true),
        ]
    }()

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
            HomeTableItem(id: "K9PQR", name: "Sunday Brunch", yourTurn: false, status: "playing", seats: seats([("Biscuit", 4), ("Kiki", 6)]), turnCat: 4, updatedAt: 0, idleDays: 3),
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
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("home.settings")
    }

    /// The owner's cat on a cushion, bottom-left. Tap for the people on this phone.
    private var ownerCorner: some View {
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
    }
}

/// Tells Home when its scrolling column runs under the top bar or on under the bottom one.
private struct BarShades: ViewModifier {
    @Binding var top: Bool
    @Binding var bottom: Bool

    private struct Edges: Equatable {
        var top: Bool
        var bottom: Bool
    }

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Edges.self) { geo in
            // The offset counts the safe area's insets; the container is what shows inside them.
            let scrolled = geo.contentOffset.y + geo.contentInsets.top
            return Edges(top: scrolled > 6, bottom: scrolled + geo.containerSize.height < geo.contentSize.height - 6)
        } action: { _, edges in
            top = edges.top
            bottom = edges.bottom
        }
    }
}

private extension View {
    func shadesBars(top: Binding<Bool>, bottom: Binding<Bool>) -> some View {
        modifier(BarShades(top: top, bottom: bottom))
    }
}
