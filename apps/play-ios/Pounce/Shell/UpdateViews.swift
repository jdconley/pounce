import PounceKit
import SwiftUI

/// The words and the button for "update", decided once for every update screen (app updates
/// design §4.4): where Update goes on this device, or that it goes nowhere.
private struct UpdateButton: View {
    @Environment(AppModel.self) private var model
    var need: UpdateRequirement?
    var size: PillSize = .medium
    var width: CGFloat = 190
    var identifier: String
    var onTap: () -> Void = {}

    var body: some View {
        let action = model.updates.action(band: model.ageBand, need: need)
        switch action {
        case .store:
            pill(String(localized: "Update", comment: "Update screens: the button that opens the App Store's page for Pounce"), action)
        case .testFlight:
            pill(String(localized: "Open TestFlight", comment: "Update screens, on a TestFlight install: the button that opens TestFlight"), action)
        case .askGrownUp:
            EmptyView()
        }
    }

    private func pill(_ title: String, _ action: UpdatePolicy.Action) -> some View {
        PillButton(icon: nil, color: Palette.lime, size: size, width: width, title: title, accessibilityLabel: LocalizedStringKey(title)) {
            model.updates.open(action)
            onTap()
        }
        .accessibilityIdentifier(identifier)
    }
}

/// "Ask a grown-up to update Pounce.": a child's device has no link to the store.
private let askGrownUp = String(
    localized: "Ask a grown-up to update.", comment: "Update screens on a child's device: there is no button, a parent updates the app")

// MARK: - the hard moment

/// The server no longer supports this version (design §4.3): one full screen, over everything,
/// with Update and, quietly under it, the way to the account (`UpdateAccountLink`: deleting it
/// must stay possible). `onHome`: only when a single table asked (a snapshot of a newer
/// protocol), where going home, and so the gear, is still possible.
struct UpdateRequiredScreen: View {
    @Environment(AppModel.self) private var model
    var need: UpdateRequirement?
    var onHome: (() -> Void)?

    @State private var appeared = false

    private var detail: String {
        switch model.updates.action(band: model.ageBand, need: need) {
        case .store:
            String(localized: "This version is too old.",
                   comment: "The full-screen update notice: why; the Update button below opens the App Store")
        case .testFlight:
            String(localized: "This version is too old.",
                   comment: "The full-screen update notice on a TestFlight install")
        case .askGrownUp:
            String(localized: "Ask a grown-up to update.",
                   comment: "The full-screen update notice on a child's device: no button")
        }
    }

    var body: some View {
        ZStack {
            RoomBackground()
            ScrollView {
                VStack(spacing: 22) {
                    UpdateArt(appeared: appeared)
                    VStack(spacing: 10) {
                        OutlinedText(
                            String(localized: "Update to keep playing", comment: "The full-screen update notice: the headline"),
                            size: 30, lines: 3)
                            .accessibilityAddTraits(.isHeader)
                        WordLine(detail, size: 17)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 520)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("update.required.text")
                    HStack(spacing: 18) {
                        UpdateButton(need: need, identifier: "update.required.update")
                        if let onHome {
                            PillButton(icon: ArtName.iconHome, color: Palette.orange, size: .medium, width: 150,
                                       title: String(localized: "Home", comment: "Update screens: the pill that goes Home"), accessibilityLabel: "Home", action: onHome)
                                .accessibilityIdentifier("update.required.home")
                        }
                    }
                    // Over everything, the gear is out of reach: the account stays reachable from here.
                    if onHome == nil { UpdateAccountLink().padding(.top, 6) }
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("update.required")
    }
}

/// The update cat on its glow, as the state cards draw their art.
private struct UpdateArt: View {
    var appeared: Bool
    var side: CGFloat = 220

    var body: some View {
        Image(ArtName.stateUpdate)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .background(
                Circle()
                    .fill(RadialGradient(
                        colors: [Palette.sky.opacity(0.9), Palette.violet.opacity(0)],
                        center: .center, startRadius: 10, endRadius: side * 0.77))
                    .frame(width: side * 1.55, height: side * 1.55)
            )
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)
    }
}

// MARK: - a table that needs a newer app

/// What a table shows when the store's phase is `needsUpdate` (design §4.2, §4.3): the game this
/// table is playing and how to get an app that draws it, or the hard screen when the app itself
/// is too old.
struct TableUpdateView: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession

    var body: some View {
        switch session.store.refusal {
        case .game(let id, let title):
            TableNeedsUpdateCard(game: id, title: UpdatePolicy.gameTitle(id: id, serverTitle: title)) { model.goHome() }
                // Kept for Home: the invite is still there after this card is closed.
                .task { model.updates.remember(code: session.code, game: id, title: title) }
        case .required(let need):
            // The same answer every table and every call will get: the app-wide screen takes over.
            UpdateRequiredScreen(need: need)
                .task { model.updates.require(need) }
        case nil:
            // A snapshot of a protocol this build doesn't speak: this table needs a newer app.
            UpdateRequiredScreen(need: nil) { model.goHome() }
        }
    }
}

/// "This table is playing Tuna Tiles. Update Pounce to join."
struct TableNeedsUpdateCard: View {
    @Environment(AppModel.self) private var model
    let game: String
    /// The game's name, or nil for a game nobody here has a name for.
    let title: String?
    let onHome: () -> Void

    @State private var appeared = false

    private var headline: String {
        if let title {
            return String(localized: "This table plays \(title)", comment: "A table whose game this version can't draw: the headline, with the game's name")
        }
        return String(localized: "This table plays a newer game", comment: "A table whose game this version can't draw, and has no name for")
    }

    private var advice: UpdatePolicy.TableAdvice { model.updates.tableAdvice(band: model.ageBand) }

    private var detail: String {
        switch advice {
        case .update:
            String(localized: "Update to join.", comment: "A table whose game needs a newer app: what to do")
        case .updateInTestFlight:
            String(localized: "Update in TestFlight to join.", comment: "A table whose game needs a newer app, on a TestFlight install")
        case .askGrownUp:
            askGrownUp
        case .notYet:
            if let title {
                String(localized: "\(title) isn't in this version yet.", comment: "A table whose game needs a newer app, when no newer app is out")
            } else {
                String(localized: "Not in this version yet.", comment: "A table whose game needs a newer app, when no newer app is out and the game has no name here")
            }
        }
    }

    var body: some View {
        ZStack {
            RoomBackground()
            ScrollView {
                VStack(spacing: 22) {
                    cover
                    VStack(spacing: 10) {
                        OutlinedText(headline, size: 28, lines: 3)
                            .accessibilityAddTraits(.isHeader)
                        WordLine(detail, size: 17)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 520)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("update.table.text")
                    HStack(spacing: 18) {
                        if advice == .update || advice == .updateInTestFlight {
                            UpdateButton(identifier: "update.table.update")
                        }
                        PillButton(icon: ArtName.iconHome, color: Palette.orange, size: .medium, width: 150,
                                   title: String(localized: "Home", comment: "Update screens: the pill that goes Home"), accessibilityLabel: "Home", action: onHome)
                            .accessibilityIdentifier("update.table.home")
                    }
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update.table")
    }

    /// The game's own cover when this build has one (a game on the shelf, on its way), framed
    /// like a card on Home; otherwise the update cat.
    @ViewBuilder private var cover: some View {
        if let entry = GameCatalog.entry(id: game) {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            Image(entry.art)
                .resizable()
                .scaledToFill()
                .frame(width: 270, height: 180)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
                .overlay(alignment: .bottomTrailing) { Padlock(side: 54).offset(x: 14, y: 14) }
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
        } else {
            UpdateArt(appeared: appeared)
        }
    }
}

/// A padlock on a coin, in the toy style: this needs an update first.
private struct Padlock: View {
    var side: CGFloat = 40

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: side * 0.46, weight: .black))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                Circle()
                    .fill(LinearGradient(colors: [Palette.orange.mix(with: .white, by: 0.3), Palette.orange], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(3, side * 0.09)))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3))
            .accessibilityHidden(true)
    }
}

// MARK: - Home

/// Home's update corner (design §4.1, §4.2): the soft "a new Pounce is ready" card, and the
/// tables waiting behind an update. Nothing at all when there is neither, which is nearly always.
struct HomeUpdates: View {
    @Environment(AppModel.self) private var model
    /// An iPad's wider column.
    var roomy = false

    var body: some View {
        let updates = model.updates
        let rows = updates.lockedRows(listed: model.tables)
        // Never over the hard screen's shoulder, and never before there is someone to show it to.
        if updates.required == nil, model.people.owner != nil, updates.softVersion != nil || !rows.isEmpty {
            VStack(spacing: 12) {
                if updates.softVersion != nil {
                    SoftUpdateCard(roomy: roomy)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                ForEach(rows) { row in
                    LockedTableRow(row: row, roomy: roomy)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(maxWidth: roomy ? 620 : .infinity)
            .padding(.horizontal, roomy ? 0 : 20)
            .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: updates.softVersion)
            .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: rows.map(\.id))
        }
    }
}

/// The card's face: the toy panel every Home card sits on.
private struct UpdatePanel<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.18), tint.mix(with: Palette.ink, by: 0.12)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 6))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
    }
}

/// "Update ready": one small row, closed with one tap, and gone for that version. A child's
/// device has no button, only "Ask a grown-up."
struct SoftUpdateCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var roomy = false

    private var asksGrownUp: Bool { model.updates.action(band: model.ageBand) == .askGrownUp }

    var body: some View {
        UpdatePanel(tint: Palette.violet) {
            let words = VStack(alignment: .leading, spacing: 2) {
                Text("Update ready", comment: "Home's update card: the headline")
                    .font(.system(roomy ? .title3 : .headline, design: .rounded, weight: .black))
                    .accessibilityAddTraits(.isHeader)
                if asksGrownUp {
                    Text("Ask a grown-up.", comment: "Home's update card on a child's device: a parent updates the app")
                        .font(.system(roomy ? .body : .subheadline, design: .rounded, weight: .bold))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 1.5)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.update.text")

            let update = UpdateButton(size: .small, width: roomy ? 140 : 112, identifier: "home.update.update") {
                // Off to the store: this version's card has done its job.
                model.tips.used("home.update")
                model.updates.dismissSoft()
            }
            let close = RoundIconButton(systemName: "xmark", color: Palette.sky, side: 38, accessibilityLabel: "Not now") {
                model.updates.dismissSoft()
            }
            .accessibilityIdentifier("home.update.close")

            let art = Image(ArtName.stateUpdate)
                .resizable()
                .scaledToFit()
                .frame(width: roomy ? 56 : 40, height: roomy ? 56 : 40)
                .accessibilityHidden(true)

            if typeSize.isAccessibilitySize {
                // Big text: the words over the button.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        words
                        Spacer(minLength: 0)
                        close
                    }
                    update.padding(.bottom, 6)
                }
            } else {
                // One row; the cat steps aside where the row is short.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        art
                        words
                        Spacer(minLength: 0)
                        update.padding(.bottom, 6)
                        close
                    }
                    HStack(spacing: 10) {
                        words
                        Spacer(minLength: 0)
                        update.padding(.bottom, 6)
                        close
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.update")
        .tipTarget("home.update")
    }
}

/// A table on Home behind a padlock: someone is playing a game this version can't draw. A tap
/// opens it, and the table says what to do (or, after the update, deals you in).
struct LockedTableRow: View {
    @Environment(AppModel.self) private var model
    let row: LockedTables.Row
    var roomy = false

    private var title: String {
        row.invite.name ?? TableName.fallback(code: row.invite.code)
    }

    /// What to do, in a few words (the game's colour is on the row).
    private var detail: String {
        if row.opens {
            return String(localized: "Ready to join", comment: "Home, a table that needed an update and can be opened now")
        }
        switch model.updates.tableAdvice(band: model.ageBand) {
        case .update, .updateInTestFlight:
            return String(localized: "Update to join", comment: "Home, a table behind a padlock: what to do")
        case .askGrownUp:
            return String(localized: "Ask a grown-up", comment: "Home, a table behind a padlock, on a child's device")
        case .notYet:
            return String(localized: "Not out yet", comment: "Home, a table behind a padlock, when no newer app is out")
        }
    }

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            model.open(code: row.invite.code, intent: .join)
        } label: {
            UpdatePanel(tint: Palette.tint(GameCatalog.entry(id: row.invite.game)?.tint ?? .sky)) {
                HStack(spacing: 12) {
                    if row.opens {
                        Image(ArtName.iconPlay).resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                    } else {
                        Padlock(side: roomy ? 46 : 40)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: title)
                            .font(.system(roomy ? .title3 : .headline, design: .rounded, weight: .black))
                        Text(verbatim: detail)
                            .font(.system(roomy ? .body : .subheadline, design: .rounded, weight: .bold))
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.opens ? "Opens the table" : "Says how to join")
        .accessibilityIdentifier("home.locked.\(row.invite.code)")
    }
}
