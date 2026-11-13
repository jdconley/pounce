import PounceKit
import SwiftUI

/// UI tips: short bubbles that teach the app's own controls (the game's rules are the table
/// coach's, `CoachMark`). The rules and pacing are PounceKit's (`UITip`, `TipDirector`); this
/// file is where they meet the screens.
///
/// - A control says where it is with `.tipTarget("home.join")` (the same string as its
///   accessibility identifier).
/// - A screen draws its tips with `.tipHost(.home)`: it collects the anchors under it, tells the
///   center which are on screen, and draws the bubble for the tip up now. Sheets have hosts of
///   their own (preferences don't cross a sheet), and the top host is the only one that shows.
/// - Using a control calls `model.tips.used("home.join")`: its tip is learned, shown or not.
///
/// Tips are off in demos, UI tests and screenshot runs (`TipCenter.enabled`).
@MainActor @Observable
final class TipCenter {
    /// The tip up now (on the top screen).
    private(set) var current: UITip?
    /// Bumped each time a tip goes up, so a bubble for the same tip twice still springs in.
    private(set) var serial = 0
    var enabled = true

    @ObservationIgnored private var director = TipDirector()
    @ObservationIgnored private(set) var seen: UITipsSeen
    @ObservationIgnored private let store: TutorialStore
    @ObservationIgnored private let pacing: TipPacingStore
    @ObservationIgnored private(set) var opens = 0
    @ObservationIgnored private var events: Set<TipEvent> = []
    /// Screens with a host up, the top one last.
    @ObservationIgnored private var stack: [TipScreen] = []
    @ObservationIgnored private var paused: Set<TipScreen> = []
    @ObservationIgnored private var visible: [TipScreen: Set<String>] = [:]
    /// Whose screen it is when not the owner's (the tile game's face-up seat).
    @ObservationIgnored private var people: [TipScreen: String] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var backgroundedAt: Date?

    /// Who is looking by default, their age band, and whether others share the phone.
    @ObservationIgnored var who: () -> (owner: String?, band: AgeBand?, passAndPlay: Bool) = { (nil, nil, false) }
    /// Something covers every screen (a pounce pick, the invite sheet, the update wall).
    @ObservationIgnored var blocked: () -> Bool = { false }
    /// A tip was seen or learned (the account syncs the record).
    @ObservationIgnored var onChange: () -> Void = {}

    /// How long a screen has to sit still before a tip goes up, and the pause between two tips.
    static let settle = Duration.milliseconds(900)
    static let gap = Duration.milliseconds(1600)

    init(store: TutorialStore, pacing: TipPacingStore) {
        self.store = store
        self.pacing = pacing
        seen = store.loadUI()
    }

    /// A launch: one more app open.
    func launched() {
        guard enabled else { return }
        opens = pacing.opened()
    }

    /// Back from the background after a while: a new session (its own count, one more open).
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background: backgroundedAt = Date()
        case .active:
            if let at = backgroundedAt, Date().timeIntervalSince(at) > 30 * 60, enabled {
                opens = pacing.opened()
                director.reset()
                events = []
            }
            backgroundedAt = nil
        default: break
        }
    }

    // MARK: what the screens tell it

    func appear(_ screen: TipScreen) {
        stack.removeAll { $0 == screen }
        stack.append(screen)
        director.visit(screen)
        sync()
        schedule(after: Self.settle)
    }

    func disappear(_ screen: TipScreen) {
        stack.removeAll { $0 == screen }
        visible[screen] = nil
        if current?.rule.screen == screen { takeDown() }
        if let top = stack.last { director.visit(top) }
        schedule(after: Self.settle)
    }

    func report(_ screen: TipScreen, visible ids: Set<String>) {
        guard visible[screen] != ids else { return }
        visible[screen] = ids
        // A tip whose control left the screen comes down at once; a new one waits for stillness.
        if let current, current.rule.screen == screen, !ids.contains(current.rule.anchor) { takeDown() }
        schedule(after: Self.settle)
    }

    func pause(_ screen: TipScreen, _ on: Bool) {
        if on { paused.insert(screen) } else { paused.remove(screen) }
        if on, current?.rule.screen == screen { takeDown() }
        if !on { schedule(after: Self.settle) }
    }

    func person(_ screen: TipScreen, _ id: String?) {
        guard people[screen] != id else { return }
        people[screen] = id
        if current?.rule.screen == screen { takeDown() }
        schedule(after: Self.settle)
    }

    /// Something happened that a tip waits for.
    func note(_ event: TipEvent) {
        events.insert(event)
    }

    /// A control was used: what it teaches is learned, for whoever's screen it is.
    func used(_ control: String) {
        let was = current
        let learned = director.used(control)
        if was != nil, director.tip == nil { current = nil }
        guard !learned.isEmpty, let person = person(for: was?.rule.screen ?? stack.last ?? .home) else { return }
        mark(learned, person: person)
        if was != nil, current == nil { schedule(after: Self.gap) }
    }

    /// "Got it": the bubble's tap, or VoiceOver's escape.
    func dismiss() {
        takeDown()
        schedule(after: Self.gap)
    }

    /// Settings' Reset tips: everyone sees them again.
    func reset() {
        takeDown()
        director.reset()
        pacing.reset()
        seen = [:]
        schedule(after: Self.settle)
    }

    /// The record changed under us (sync, a new id for a person).
    func reload() {
        seen = store.loadUI()
    }

    /// A tip learned some other way (the old "archive hint seen" flag).
    func learn(_ tips: Set<UITip>, person: String) {
        mark(tips, person: person)
    }

    // MARK: deciding

    private func person(for screen: TipScreen) -> String? {
        people[screen] ?? who().owner
    }

    private func takeDown() {
        director.dismiss()
        current = nil
    }

    private func mark(_ tips: Set<UITip>, person: String) {
        guard !tips.isSubset(of: seen[person] ?? []) else { return }
        seen = store.markSeen(tips, person: person)
        onChange()
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        guard enabled else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Pace.duration(delay))
            guard !Task.isCancelled else { return }
            self?.decide()
        }
    }

    /// Mirrors the director's tip (it may have come down inside an update).
    private func sync() {
        if current != director.tip { current = director.tip }
    }

    private func decide() {
        guard enabled, let screen = stack.last, !paused.contains(screen), !blocked(),
              let person = person(for: screen) else { return }
        let who = who()
        let facts = TipFacts(
            screen: screen, person: person, band: who.band, passAndPlay: who.passAndPlay, opens: max(opens, 1),
            visible: visible[screen] ?? [], events: events)
        let now = Date()
        let tip = director.update(facts, seen: seen[person] ?? [], today: pacing.shown(person: person, on: now))
        guard let tip else {
            sync()
            return
        }
        pacing.noteShown(person: person, on: now)
        mark([tip], person: person)
        serial += 1
        current = tip
        UIAccessibility.post(notification: .announcement, argument: UITipCopy.text(tip))
    }
}

// MARK: - The words

/// One line each, eight words at most: what to do, or what a thing is.
enum UITipCopy {
    static func text(_ tip: UITip) -> String {
        switch tip {
        case .homeShelf: String(localized: "Tap Play to start a game.", comment: "Tip on Home: the game card's play button")
        case .homePractice: String(localized: "Try a practice game with the House Cat.", comment: "Tip on Home: the Practice pill")
        case .homeJoin: String(localized: "Got a code? Join a friend's table.", comment: "Tip on Home: the Join pill")
        case .homeTables: String(localized: "Your games wait here. Tap one to play.", comment: "Tip on Home: the row of your tables")
        case .homeArchive: String(localized: "Press and hold a table to archive it.", comment: "Tip on Home: a table that has waited a day")
        case .homeRules: String(localized: "New to Cat Tower? Learn it here.", comment: "Tip on Home: the How to play chip")
        case .homeStreak: String(localized: "Your streak: days in a row you played.", comment: "Tip on Home: your streak in the strip")
        case .homeInvite: String(localized: "Invite someone to start a streak together.", comment: "Tip on Home: the Invite pill in the dock")
        case .homeGift: String(localized: "A gift for your streak. Tap to open.", comment: "Tip on Home: a streak gift waiting in the strip")
        case .homePeople: String(localized: "Tap your cat to add family.", comment: "Tip on Home: the owner's cat opens People")
        case .homeUpdate: String(localized: "New games and fixes are ready.", comment: "Tip on Home: the update card")
        case .lobbySeat: String(localized: "Tap a cushion to seat someone here.", comment: "Tip in the lobby: an open seat")
        case .lobbyAdd: String(localized: "Add a House Cat or a friend.", comment: "Tip in the lobby: the Add a player pill")
        case .lobbyShare: String(localized: "Send this code so friends can join.", comment: "Tip in the lobby: the share button by the code")
        case .lobbyStart: String(localized: "Everyone's here? Tap Start.", comment: "Tip in the lobby: the Start pill, once it can start")
        case .menuLook: String(localized: "Pick a new rug and card backs.", comment: "Tip in the table menu: the look button")
        case .menuMove: String(localized: "Move your seat to another phone.", comment: "Tip in the table menu: the move seat button")
        case .pouncePick: String(localized: "Pick a game, then tap Pounce.", comment: "Tip on the Pounce sheet: the game tiles")
        case .usBell: String(localized: "Ring to ask them to come play.", comment: "Tip on the Us screen: the Pounce bell")
        case .usTrophies: String(localized: "Win trophies by playing days in a row.", comment: "Tip on the Us screen: the trophy button")
        case .gearAlerts: String(localized: "A bell when a game waits on you.", comment: "Tip in settings: the turn alerts toggle")
        case .tilesMeter: String(localized: "Your first play must reach this score.", comment: "Tip in the tile game: the opening meter")
        case .tilesPlay: String(localized: "Tap Play to send your turn.", comment: "Tip in the tile game: the Play button")
        case .tilesDraw: String(localized: "Nothing to play? Draw a toy.", comment: "Tip in the tile game: the Draw button")
        case .tilesSort: String(localized: "Sort your stash by number or toy.", comment: "Tip in the tile game: the two sort buttons")
        case .tilesUndo: String(localized: "Undo a move. Hold reset to start over.", comment: "Tip in the tile game: the undo and reset buttons")
        case .tilesHint: String(localized: "Stuck? Tap for a hint.", comment: "Tip in the tile game (easy mode): the hint button")
        case .tilesLoupe: String(localized: "Tap a set to see it up close.", comment: "Tip in the tile game: a set on the rug opens in the loupe")
        }
    }
}

// MARK: - Anchors and hosts

/// Where each tip target is under a host. (Not TipKit's `tipAnchor`: Pounce's tips are drawn by
/// its own hosts.)
struct TipTargetKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

extension View {
    /// Marks this view as the place a tip can point at. Nil marks nothing (a control that only
    /// counts as a target in some states, like Start once the table can start).
    func tipTarget(_ id: String?) -> some View {
        transformAnchorPreference(key: TipTargetKey.self, value: .bounds) { all, anchor in
            if let id, all[id] == nil { all[id] = anchor }
        }
    }

    /// Draws this screen's tips over it. `paused`: something covers it (a sheet with no host).
    func tipHost(_ screen: TipScreen, paused: Bool = false, person: String? = nil) -> some View {
        modifier(TipHost(screen: screen, paused: paused, person: person))
    }
}

private struct TipHost: ViewModifier {
    @Environment(AppModel.self) private var model
    let screen: TipScreen
    let paused: Bool
    let person: String?

    func body(content: Content) -> some View {
        let tips = model.tips
        content
            .overlayPreferenceValue(TipTargetKey.self) { anchors in
                if tips.enabled {
                    GeometryReader { proxy in
                        let bounds = CGRect(origin: .zero, size: proxy.size)
                        let rects = anchors.mapValues { proxy[$0] }
                        let shown = Set(rects.filter { Self.onScreen($0.value, in: bounds) }.keys)
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .onChange(of: shown, initial: true) { _, ids in tips.report(screen, visible: ids) }
                            if let tip = tips.current, tip.rule.screen == screen,
                               let target = rects[tip.rule.anchor], Self.onScreen(target, in: bounds) {
                                TipBubble(tip: tip, target: target, bounds: bounds) { tips.dismiss() }
                                    .id(tips.serial)
                            }
                        }
                    }
                }
            }
            .onAppear { tips.appear(screen) }
            .onDisappear { tips.disappear(screen) }
            .onChange(of: paused, initial: true) { _, on in tips.pause(screen, on) }
            .onChange(of: person, initial: true) { _, id in tips.person(screen, id) }
    }

    /// Mostly on screen: its middle inside the host, and some size to it.
    static func onScreen(_ rect: CGRect, in bounds: CGRect) -> Bool {
        rect.width > 4 && rect.height > 4 && bounds.contains(CGPoint(x: rect.midX, y: rect.midY))
    }
}

// MARK: - The bubble

/// A tip: a yellow speech bubble in toy lettering with an ink outline, pointing at its control
/// from below or above (whichever side has room), never over it. A ring pulses around the
/// control (still under Reduce Motion). One tap on the bubble puts it away; VoiceOver reads it
/// when it shows and dismisses it with a double tap or the escape gesture. The rest of the screen
/// keeps working under and around it.
struct TipBubble: View {
    let tip: UITip
    let target: CGRect
    let bounds: CGRect
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = CGSize(width: 240, height: 60)
    @State private var shown = false
    @State private var pulse = false

    private static let margin: CGFloat = 12
    private static let gap: CGFloat = 14
    private static let arrow: CGFloat = 11

    var body: some View {
        let below = Self.placesBelow(target: target, bounds: bounds, height: size.height)
        let width = min(bounds.width - 2 * Self.margin, 340)
        let x = min(max(target.midX - size.width / 2, Self.margin), max(bounds.width - Self.margin - size.width, Self.margin))
        let rawY = below ? target.maxY + Self.gap : target.minY - Self.gap - size.height
        let y = min(max(rawY, Self.margin / 2), bounds.height - size.height - Self.margin / 2)
        let arrowAt = min(max(target.midX - x, 26), size.width - 26)
        ZStack(alignment: .topLeading) {
            ring
            card(below: below, arrowAt: arrowAt)
                .frame(maxWidth: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                // Springs out of its pointer (Reduce Motion: it only fades in).
                .scaleEffect(shown || reduceMotion ? 1 : 0.6, anchor: UnitPoint(x: arrowAt / max(size.width, 1), y: below ? 0 : 1))
                .opacity(shown ? 1 : 0)
                .offset(x: x, y: y)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2).paced : .spring(duration: 0.45, bounce: 0.45).paced) { shown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).paced) { pulse = true }
        }
    }

    /// Below when the bubble fits there; above when it fits there instead; else the roomier side.
    static func placesBelow(target: CGRect, bounds: CGRect, height: CGFloat) -> Bool {
        let need = height + gap + margin / 2
        let roomBelow = bounds.maxY - target.maxY
        let roomAbove = target.minY - bounds.minY
        if roomBelow >= need, target.midY < bounds.midY || roomAbove < need { return true }
        if roomAbove >= need { return false }
        return roomBelow >= roomAbove
    }

    /// A ring around the control, outside its edge so it hides nothing.
    private var ring: some View {
        let r = target.insetBy(dx: -5, dy: -5)
        return RoundedRectangle(cornerRadius: min(22, r.height / 2), style: .continuous)
            .strokeBorder(Palette.ink, lineWidth: 6)
            .overlay(
                RoundedRectangle(cornerRadius: min(22, r.height / 2), style: .continuous)
                    .strokeBorder(Palette.yellow, lineWidth: 3).padding(1.5))
            .frame(width: r.width, height: r.height)
            .scaleEffect(pulse ? 1.04 : 1)
            .offset(x: r.minX, y: r.minY)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func card(below: Bool, arrowAt: CGFloat) -> some View {
        Button {
            Haptics.shared.tick()
            onDismiss()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: UITipCopy.text(tip))
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.ink))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 11)
            .frame(minHeight: 48)
            .background {
                let shape = TipShape(below: below, arrowAt: arrowAt, arrow: Self.arrow)
                shape.fill(Palette.yellow)
                    .overlay(shape.stroke(Palette.ink, style: StrokeStyle(lineWidth: 3.5, lineJoin: .round)))
                    .compositingGroup()
                    .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityLabel(Text(verbatim: UITipCopy.text(tip)))
        .accessibilityHint(Text("Tip. Double-tap to dismiss.", comment: "VoiceOver: hint on a UI tip bubble"))
        .accessibilityAction(.escape) { onDismiss() }
        .accessibilityIdentifier("tip")
        .accessibilityValue(Text(verbatim: tip.rawValue))
    }
}

/// A rounded bubble with a pointer on the edge that faces the control.
private struct TipShape: Shape {
    let below: Bool
    let arrowAt: CGFloat
    let arrow: CGFloat

    func path(in r: CGRect) -> Path {
        let corner = min(20, r.height / 2)
        var p = Path()
        let a = arrow
        let x = min(max(arrowAt, corner + a), r.width - corner - a)
        p.move(to: CGPoint(x: r.minX + corner, y: r.minY))
        if below {
            p.addLine(to: CGPoint(x: x - a, y: r.minY))
            p.addLine(to: CGPoint(x: x, y: r.minY - a))
            p.addLine(to: CGPoint(x: x + a, y: r.minY))
        }
        p.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + corner), radius: corner)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - corner, y: r.maxY), radius: corner)
        if !below {
            p.addLine(to: CGPoint(x: x + a, y: r.maxY))
            p.addLine(to: CGPoint(x: x, y: r.maxY + a))
            p.addLine(to: CGPoint(x: x - a, y: r.maxY))
        }
        p.addLine(to: CGPoint(x: r.minX + corner, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - corner), radius: corner)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + corner))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + corner, y: r.minY), radius: corner)
        p.closeSubpath()
        return p
    }
}

/// A scene's controls as tip anchors: an empty frame at each spot, in the scene view's points.
struct TipSpots: View {
    let spots: [String: CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(spots.keys.sorted(), id: \.self) { id in
                if let r = spots[id] {
                    Color.clear
                        .frame(width: r.width, height: r.height)
                        .tipTarget(id)
                        .padding(.leading, max(r.minX, 0))
                        .padding(.top, max(r.minY, 0))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
