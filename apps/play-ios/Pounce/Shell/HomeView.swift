import PounceKit
import SwiftUI

/// Home, laid out like a game's hub: a player bar on top, what to play in the middle, the dock
/// at the bottom.
///
/// - The player bar: the owner's cat on its cushion (the people on this phone), the streak strip
///   (your streak, your connections, the gift, Save, Invite), the bell when push is on offer again
///   (spec §10), and the gear (sound, haptics, how to play). One row, no wordmark.
/// - The middle scrolls: Home's notices (a newer version, a table behind one, why a game didn't
///   start), then what leads (`HomeLead`). With a game going your tables lead and the games sit
///   under them as compact tickets; with no table, or only finished ones, the games lead as
///   posters. An iPad lays the games out as a grid, beside your tables when it is on its side.
/// - The dock: Join, and Practice while there is no table. Its own band: nothing scrolls under it.
///
/// Long-press a table to archive it; the sleeping-cat tile at the end of the tables opens the
/// archived ones.
///
/// Home hosts UI tips (`Tips.swift`, `.tipHost(.home)`); the anchors are `home.play` (Cat Tower's
/// play mark), `home.practice`, `home.join`, `home.tables`, `home.idleTable`, `home.hero`,
/// `home.people`, `home.update`, and the strip's `home.own`, `home.add` and `home.gift`.
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
    /// The streak badge's Save was tapped: the sign-in card is up (§10.5).
    @State private var streakSignIn = false
    /// The column has scrolled up under the player bar, where it fades out.
    @State private var scrolled = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Home's one-time sign-in card, under no other overlay.
    private var showSignInPrompt: Bool {
        !showPriming && !streakSignIn && model.people.owner != nil
            && SignInPrompt.shows(
                band: model.ageBand, signedIn: model.account.isSignedIn, offersSignIn: model.account.offersSignIn,
                pairs: model.streaks.pairs.count, dismissed: settings.signInPromptSeen)
    }

    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            // In reading order, which is VoiceOver's: the player bar, the column, the dock.
            VStack(spacing: 0) {
                playerBar
                Group {
                    if roomy {
                        roomyColumn(geo.size)
                    } else {
                        compactColumn
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask { columnMask }
                dock(width: geo.size.width, bottomInset: geo.safeAreaInsets.bottom)
            }
        }
        // Under the bars, the status bar and the home indicator too.
        .background { background }
        // Tips wait while a sheet or a card covers Home.
        .tipHost(.home, paused: showPeople || showSettings || showArchived || showRules || showPriming || streakSignIn
            || showSignInPrompt)
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
                    .compositingGroup()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: showPriming)
        .animation(.spring(duration: 0.4, bounce: 0.4).paced, value: showBell)
        .animation(.easeOut(duration: 0.2).paced, value: scrolled)
        .task { await model.refreshTables() }
        .task { await model.refreshStreaks() }
        // Save on the top pair's streak, or once a pair formed: one sign-in card (§10.5, launch review).
        .overlay {
            if streakSignIn {
                SignInPromptCard(identifier: "home.streak.signinCard", appleIdentifier: "home.streak.signin") {
                    streakSignIn = false
                }
                .transition(.opacity)
            } else if showSignInPrompt {
                SignInPromptCard(identifier: "home.signinPrompt", appleIdentifier: "home.signinPrompt.apple") {
                    settings.signInPromptSeen = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: streakSignIn)
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

    /// The first table that has waited a day or more.
    private var firstIdle: String? { shownItems.first { ($0.idleDays ?? 0) >= 1 }?.id }

    private var hasTables: Bool { !shownItems.isEmpty || model.archivedItems.count > 0 }
    private var lead: HomeLead { HomeLead.pick(shownItems) }

    // MARK: the player bar

    /// The streak strip (trophy room design §1), once the server said streaks are on.
    private var showStrip: Bool { model.streaks.enabled == true }

    /// One row across the top: who you are (the owner's cat), your streaks and connections, then
    /// the bell and the gear. The strip scrolls sideways when it outgrows the row.
    private var playerBar: some View {
        HStack(spacing: roomy ? 14 : 6) {
            ownerBadge
            Group {
                if showStrip {
                    StreakStripView(scale: roomy ? 1.15 : 0.85) { streakSignIn = true }
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            if showBell { bell.transition(.scale.combined(with: .opacity)) }
            gear
        }
        .padding(.leading, roomy ? 20 : 8)
        .padding(.trailing, roomy ? 16 : 6)
        .frame(height: roomy ? 92 : 68)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.playerBar")
    }

    /// The owner's cat on its cushion: the people on this phone.
    private var ownerBadge: some View {
        let side: CGFloat = roomy ? 76 : 58
        return Button {
            ownerWiggle += 1
            model.tips.used("home.people")
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
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: roomy ? 4 : 3.5))
                    .frame(width: side, height: side * 0.36)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
                Image(ArtName.cat(model.people.owner?.cat ?? 0, .idle))
                    .resizable().scaledToFit()
                    .frame(width: side * 0.86, height: side * 0.86)
                    .shadow(color: Palette.ink.opacity(0.35), radius: 0, x: 0, y: 3)
                    .padding(.bottom, side * 0.14)
                    .wiggle(trigger: ownerWiggle)
            }
            .frame(width: side, height: side, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("People on this phone"))
        .accessibilityIdentifier("home.people")
        .tipTarget("home.people")
    }

    /// Re-offers push once: the priming screen again, then the system prompt (or its settings page).
    private var bell: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            settings.pushReoffered = true
            showPriming = true
        } label: {
            roundFace(Palette.magenta, icon: ArtName.iconBell, inset: 8)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .bounceLoop(active: true)
        .accessibilityLabel(Text("Turn on turn notifications", comment: "VoiceOver: Home's bell that offers push again"))
        .accessibilityIdentifier("home.bell")
    }

    private var gear: some View {
        Button {
            Haptics.shared.tick()
            showSettings = true
        } label: {
            roundFace(Palette.sky, icon: ArtName.iconGear, inset: 9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("home.settings")
    }

    /// A round toy button's face: the colour, the ink ring, the icon, a lip of shadow.
    private func roundFace(_ color: Color, icon: String, inset: CGFloat) -> some View {
        let side: CGFloat = roomy ? 56 : 46
        return Circle()
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.3), color], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
            .overlay { Image(icon).resizable().scaledToFit().padding(inset * side / 48) }
            .frame(width: side, height: side)
            .compositingGroup()
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
            .frame(width: max(side, 48), height: max(side + 4, 52))
            .contentShape(Rectangle())
    }

    /// What shows of the column. At rest, all of it (a card's glow may poke up past its edge);
    /// once it has scrolled, it fades out under the player bar.
    private var columnMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(scrolled ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
            Color.black
        }
        .padding(.top, scrolled ? 0 : -40)
        .padding(.horizontal, -60)
    }

    // MARK: the dock

    /// Pinned to the bottom, on a band of its own: Join, and Practice beside it while there is no
    /// table yet. The column ends at its edge.
    private func dock(width: CGFloat, bottomInset: CGFloat) -> some View {
        let practice = shownItems.isEmpty
        let gap: CGFloat = 12
        let pill: CGFloat =
            roomy
            ? 300
            : practice ? max(120, min(220, (width - 32 - gap) / 2)) : max(160, min(280, width - 32))
        return HStack(spacing: gap) {
            if practice { practicePill(width: pill) }
            joinPill(width: pill)
        }
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: practice)
        .padding(.top, 12)
        // Above the home indicator there is room already; a phone with a button needs a margin.
        .padding(.bottom, bottomInset > 0 ? 2 : 10)
        .frame(maxWidth: .infinity)
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
            shape
                .fill(LinearGradient(
                    colors: [Palette.violet.mix(with: Palette.ink, by: 0.35), Palette.night.mix(with: Palette.ink, by: 0.3)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
                .overlay(shape.strokeBorder(Palette.violet.mix(with: .white, by: 0.2).opacity(0.6), lineWidth: 2).padding(5))
                // The sides and the bottom edge run off the screen; only the top outline shows.
                .padding(.horizontal, -8)
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.dock")
    }

    private func joinPill(width: CGFloat) -> some View {
        PillButton(
            icon: ArtName.iconKeypad, color: Palette.teal, size: roomy ? .large : .medium, width: width,
            title: String(localized: "Join", comment: "Home: the pill that joins a game by code"),
            accessibilityLabel: "Join a game"
        ) {
            model.tips.used("home.join")
            model.showJoin()
        }
        .accessibilityIdentifier("home.join")
        .tipTarget("home.join")
    }

    /// With no tables yet, a way to just try the game: a practice round against the House Cat.
    private func practicePill(width: CGFloat) -> some View {
        PillButton(
            icon: ArtName.badgeBot, color: Palette.magenta, size: roomy ? .large : .medium, width: width,
            title: String(localized: "Practice", comment: "Home, with no tables: starts a game against the computer player"),
            accessibilityLabel: "Practice with the House Cat"
        ) {
            model.tips.used("home.practice")
            Task { await model.newGame(practice: true) }
        }
        .disabled(model.isCreatingRoom)
        // The pill's lip and face fade as one.
        .compositingGroup()
        .opacity(model.isCreatingRoom ? 0.7 : 1)
        .accessibilityIdentifier("home.practice")
        .tipTarget("home.practice")
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: sections

    // No titles over the sections: the cards say what they are, and a your-turn card glows and
    // bounces on its own (JD, 2026-11-13). Each group keeps its name for VoiceOver, on its container.

    private var shelfTitle: String {
        hasTables
            ? String(localized: "New game", comment: "Home: the game shelf's title when you already have tables")
            : String(localized: "Games", comment: "Home: the game shelf's title with no tables yet")
    }

    private static let tablesTitle = String(localized: "Your tables", comment: "Home: the title over your tables")


    /// Why a new game didn't start, over the shelf.
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
                .compositingGroup()
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("home.createError")
        }
    }

    /// Why a new game didn't start, in words.
    static func createFailedMessage(_ error: APIError) -> String {
        switch error {
        case .transport:
            String(localized: "No internet.", comment: "Home: Create failed offline")
        case .rateLimited:
            String(localized: "Too many tries. Wait a bit.", comment: "Home: Create was rate limited")
        default:
            String(localized: "Couldn't start. Try again.", comment: "Home: Create failed")
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
        // How to play rides on a poster's cover; a ticket's cover is too small (the gear has it too).
        let rules = dealt && (layout == .poster || bigType)
        return VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                GameCard(
                    game: game, layout: layout, coverRatio: coverRatio, roomy: roomy, playUnder: playUnder,
                    busy: model.isCreatingRoom && game.isAvailable, identifier: dealt ? "home.newGame" : nil,
                    playAnchor: dealt ? "home.play" : nil
                ) {
                    if dealt { model.tips.used("home.newGame") }
                    Task { await model.newGame(game) }
                }
                if rules, !bigType { rulesChip(roomy: roomy).padding(roomy ? 16 : 12) }
            }
            // At a big text size the chip would hide the cover, so it gets a row of its own.
            if rules, bigType { rulesChip(roomy: roomy, wide: true) }
        }
        .shake(trigger: dealt ? newGameShake : 0)
        .shelfEntrance(index: index)
    }

    private func rulesChip(roomy: Bool, wide: Bool = false) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.tips.used("home.hero")
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
        .tipTarget("home.hero")
    }

    /// A phone's shelf: one column. When it leads, games you can play are posters and games on
    /// the way tickets; under your tables, every game is a ticket, so the tables stay on top.
    private func shelfColumn(leads: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            createError
            ForEach(Array(shelf.enumerated()), id: \.element.id) { index, game in
                gameCard(game, index: index, layout: leads && game.isAvailable ? .poster : .ticket, coverRatio: 2.3)
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: model.newGameError)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelfTitle)
        .accessibilityIdentifier("home.shelf")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelfTitle)
        .accessibilityIdentifier("home.shelf")
    }

    // MARK: your tables

    /// A phone's tables: one row that scrolls sideways.
    @ViewBuilder private var tablesSection: some View {
        if hasTables {
            tablesRow
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Self.tablesTitle)
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
                        .compositingGroup()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.35), value: items.map(\.id))
            .animation(.spring(duration: 0.4, bounce: 0.35), value: archivedCount)
            // Room for the glow and the bounce so neither is clipped by the scroll view.
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
        .scrollClipDisabled()
        .frame(height: TableCard.size.height + 34)
        .accessibilityIdentifier("home.tables")
        .tipTarget("home.tables")
    }

    // MARK: compact (iPhone)

    /// A phone, or a narrow iPad window: one scrolling column between the player bar and the
    /// dock. Notices first, then whatever leads.
    private var compactColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // A newer version, or a table waiting behind one (app updates design §4.1, §4.2).
                HomeUpdates()
                if lead == .tables { tablesSection }
                shelfColumn(leads: lead == .shelf)
                if lead == .shelf { tablesSection }
            }
            .padding(.top, 6)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tracksScroll($scrolled)
    }

    // MARK: roomy (iPad)

    /// A regular-width window. Wide (landscape) with tables: two columns, your tables in a panel
    /// and the shelf beside it, whichever leads on the leading side. Otherwise one column: what
    /// leads, then the other. It scrolls when it has to and sits at the top when it doesn't.
    private func roomyColumn(_ size: CGSize) -> some View {
        let height = max(0, size.height - 92 - 90)
        return ScrollView(.vertical, showsIndicators: false) {
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
                            shelfGrid(width: width, height: height)
                            if lead == .shelf, hasTables { tablesColumn }
                        }
                        .frame(width: width)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tracksScroll($scrolled)
    }

    /// Your tables on an iPad: the panel.
    private var tablesColumn: some View {
        tablesPanel
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.tablesTitle)
    }

    /// The tables Home shows (DEBUG: `-demo-home` puts sample tables here for screenshots;
    /// `-demo-home calm` the same tables with none waiting on you).
    private var shownItems: [HomeTableItem] {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-demo-home") {
            if args.indices.contains(i + 1), args[i + 1] == "calm" { return Self.calmDemoItems }
            return Self.demoItems
        }
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
                .tipTarget("home.tables")
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
                    .compositingGroup()
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
            model.tips.used("home.table")
            model.open(code: item.id, intent: .rejoin)
        }
        // The archive tip points at the first table that has waited a day.
        .tipTarget(item.id == firstIdle ? "home.idleTable" : nil)
        .contextMenu {
            Button {
                settings.archiveHintSeen = true
                model.tips.used("home.table.archive")
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
            model.tips.used("home.table.archive")
            archive(item.id)
        }
        // The card's layers come and go as one.
        .compositingGroup()
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
            HomeTableItem(id: "K9PQR", name: "Sunday Brunch", yourTurn: false, status: "playing", seats: seats([("Biscuit", 4), ("Kiki", 6)]), turnCat: 4, updatedAt: 0, idleDays: 3, game: "tiles"),
            HomeTableItem(id: "TB4XN", name: "Couch League", yourTurn: false, status: "lobby", seats: seats([], open: 2), turnCat: nil, updatedAt: 0),
            HomeTableItem(id: "GH2VD", name: "Rematch", yourTurn: false, status: "over", seats: seats([], bots: 1), turnCat: 3, updatedAt: 0),
            HomeTableItem(id: "WZ8CM", name: "Road Trip", yourTurn: true, status: "playing", seats: seats([("Pickle", 1), ("Nova", 5), ("Clementine", 3)]), turnCat: 2, updatedAt: 0, game: "tiles"),
        ]
    }()

    /// `-demo-home calm`: the same tables, none waiting on you.
    private static let calmDemoItems: [HomeTableItem] = demoItems.map { item in
        var calm = item
        calm.yourTurn = false
        if item.status == "playing" { calm.turnCat = 4 }
        return calm
    }
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
}

/// Tells Home when its column has scrolled up under the player bar.
private struct ScrollTracker: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geo in
            // The offset counts the safe area's insets; the container is what shows inside them.
            geo.contentOffset.y + geo.contentInsets.top > 6
        } action: { _, value in
            scrolled = value
        }
    }
}

private extension View {
    func tracksScroll(_ scrolled: Binding<Bool>) -> some View {
        modifier(ScrollTracker(scrolled: scrolled))
    }
}
