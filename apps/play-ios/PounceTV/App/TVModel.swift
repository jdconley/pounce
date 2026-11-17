import Foundation
import Observation
import PounceKit

/// The Apple TV's whole state: which screen it shows, the link a phone scans, the table it shows
/// (as that table's screen: docs/tv-protocol.md) and the menu over it. Mirrors the web TV page
/// (`apps/play-web/src/ui/tv/tv-app.tsx`): its phases, its rules and its words.
///
/// - Home shows a link (`ScreenLink`) until a phone links a table, or makes one from a poster.
/// - A table is kept, so the TV goes straight back to it when it opens again. A table that's gone
///   or no longer lists this TV (404, `not_screen`) is forgotten and the TV goes home.
/// - Moving to another table (a phone's link, Play again, Change game) closes the old table's
///   screen socket before the new one opens.
/// - In the background the table's socket closes; back in front, the TV joins it again.
@MainActor @Observable
final class TVModel {
    enum Phase: Equatable {
        /// Reading what the TV kept: the launch backdrop, for a few milliseconds.
        case starting
        case home, lobby, table, over
    }

    /// The menu over a table: shut, its three choices, or the link for another table.
    enum Menu: Equatable {
        case closed, items, link
    }

    /// A link to show: a QR of `url` and the backup `code`.
    struct Link: Equatable {
        let code: String
        let url: URL
    }

    private(set) var phase: Phase = .starting
    /// Home's link, once the server gave one.
    private(set) var homeLink: Link?
    /// Home's link may not reach the server ("Reconnecting").
    private(set) var homeOffline = false
    /// The table this TV shows: in the lobby, at the table and at game over.
    private(set) var table: TVRoom?
    private(set) var menu: Menu = .closed
    /// The menu's "Link another table" link.
    private(set) var menuLink: Link?
    private(set) var menuOffline = false
    private(set) var soundOn = true
    /// Who won, from the table's game-over cheer.
    private(set) var winners: [Seat] = []
    /// Bumped each time a press is refused (a table that couldn't be made): the button shakes.
    private(set) var refused = 0
    /// A table is being made.
    private(set) var making = false

    @ObservationIgnored private let services: TVServices
    /// Socket work, one step at a time: an old table's socket is closed before a new one opens.
    @ObservationIgnored private var steps: Task<Void, Never>?
    /// Writes of what the TV keeps, in order and off the main thread.
    @ObservationIgnored private let writes = InOrder()
    @ObservationIgnored private var homeWatch: LinkWatch?
    @ObservationIgnored private var menuWatch: LinkWatch?
    @ObservationIgnored private var asleep = false
    /// The table whose show step has run: the one before it is closed, so its socket may open.
    /// Until then a background or return leaves the shown table alone.
    @ObservationIgnored private var ready: TVRoom?
    @ObservationIgnored private var started = false

    /// A link being shown, and the task reading it.
    private struct LinkWatch {
        let link: any ScreenLinking
        let task: Task<Void, Never>

        func stop() {
            task.cancel()
            let link = link
            Task { await link.stop() }
        }
    }

    init(services: TVServices) {
        self.services = services
    }

    // MARK: launch

    /// Reads what the TV kept (off the main thread), then goes back to its table or home.
    func start() async {
        guard !started else { return }
        started = true
        let kept = await services.keep.load()
        soundOn = kept.soundOn
        services.applySound(kept.soundOn)
        if let room = kept.room {
            show(room)
        } else {
            goHome()
        }
    }

    /// Waits for the socket steps and kept writes handed off so far (tests).
    func settle() async {
        await steps?.value
        await writes.settle()
    }

    // MARK: the table shown

    /// Shows table `code`: the lobby until its first news says more. A table already shown is
    /// let go first, its socket closed before this one opens.
    private func show(_ code: String) {
        stopLink(&homeWatch)
        stopLink(&menuWatch)
        homeLink = nil
        menuLink = nil
        menu = .closed
        winners = []
        let old = table
        let next = TVRoom(code: code, socket: services.socket, watchesNetwork: services.watchesNetwork)
        next.onChange = { [weak self] room in self?.roomChanged(room) }
        next.onGameOver = { [weak self, weak next] winners in
            guard let self, let next, self.table === next else { return }
            self.gameOver(winners)
        }
        table = next
        phase = .lobby
        keep(room: code)
        #if DEBUG
        fputs("[tv] table \(code)\n", stderr)
        #endif
        step {
            await old?.close()
            // A later show may have replaced this table while the old one closed: that show
            // closes it. In the background it starts on return (`syncSleep`).
            guard self.table === next else { return }
            self.ready = next
            guard !self.asleep else { return }
            next.start()
        }
    }

    /// Lets the table go and shows home's link. `forget` false keeps the table for the next
    /// launch: a TV too old for it goes back to it once updated.
    private func goHome(forget: Bool = true) {
        stopLink(&menuWatch)
        menuLink = nil
        menu = .closed
        winners = []
        let old = table
        table = nil
        phase = .home
        if forget { keep(room: nil) }
        if let old { step { await old.close() } }
        startHomeLink()
    }

    /// Moves to table `code`, unless it's the one shown.
    private func move(to code: String) {
        guard code != table?.code else {
            menu = .closed
            stopLink(&menuWatch)
            menuLink = nil
            return
        }
        show(code)
    }

    private func roomChanged(_ room: TVRoom) {
        guard room === table else { return }
        switch room.store.phase {
        case .notFound, .closed, .locked:
            // The table is gone, closed, no longer lists this TV (`not_screen` reads as not
            // found), or this device is locked out of it: forget it and go home.
            return goHome()
        case .needsUpdate:
            // The table needs a newer app: home for now, and back to it once updated.
            return goHome(forget: false)
        case .connecting:
            break
        case .lobby:
            phase = .lobby
        case .playing, .stalled:
            room.openTable()
            phase = .table
        case .over:
            room.openTable()
            // The table cheers the end first; game over comes up when it's done. A table this
            // build can't draw has no cheer to wait for.
            if phase != .over { phase = room.scene == nil ? .over : .table }
        }
        // Play again: the TV follows to the new table, as its screen there.
        if let next = room.store.rematch, next != room.code {
            move(to: next)
        }
    }

    private func gameOver(_ winners: [Seat]) {
        guard table?.store.phase == .over else { return }
        self.winners = winners
        phase = .over
    }

    // MARK: presses

    /// A game's poster at home: a new table of that game with this TV as its screen.
    func make(game: String) async {
        guard phase == .home, !making else { return }
        making = true
        defer { making = false }
        do {
            let code = try await services.createRoom(game)
            guard phase == .home else { return }
            show(code)
        } catch {
            refused += 1
        }
    }

    /// The link a phone scans to join the table shown.
    var inviteURL: URL? { table.map { services.inviteURL($0.code) } }

    /// The lobby may swap its game until anyone (a person or a House Cat) sits down.
    var canChangeGame: Bool {
        guard phase == .lobby, let room = table?.store.room, room.status == .lobby else { return false }
        return !room.seats.contains { $0.kind == .human || $0.kind == .bot }
    }

    /// The other game: a new table of it, and the TV moves there.
    func changeGame() async {
        guard canChangeGame, !making, let table else { return }
        making = true
        defer { making = false }
        let other = table.isTiles ? GameCatalog.catTower.id : GameCatalog.tiles.id
        do {
            let code = try await services.createRoom(other)
            // Someone may have sat down (or the TV moved) while the table was being made: the
            // lobby they sat in stays.
            guard self.table === table, canChangeGame else { return }
            move(to: code)
        } catch {
            refused += 1
        }
    }

    /// The remote's Menu (or Back) at a table: opens the menu, goes back from its link to its
    /// choices, and shuts it.
    func back() {
        guard table != nil else { return }
        switch menu {
        case .closed: menu = .items
        case .link: closeLink()
        case .items: menu = .closed
        }
    }

    func openMenu() {
        guard table != nil else { return }
        menu = .items
    }

    func closeMenu() {
        if menu == .link { closeLink() }
        menu = .closed
    }

    /// "Link another table": this TV's link, saying which table it shows, while the table stays on.
    func showLink() {
        guard let table, menu != .closed else { return }
        menu = .link
        startMenuLink(showing: table.code)
    }

    private func closeLink() {
        stopLink(&menuWatch)
        menuLink = nil
        menuOffline = false
        menu = .items
    }

    /// "Leave table": home, and the table is forgotten.
    func leave() {
        guard table != nil else { return }
        goHome()
    }

    /// "Sound on" / "Sound off": the TV's own setting, kept off the main thread.
    func toggleSound() {
        soundOn.toggle()
        services.applySound(soundOn)
        let keep = services.keep
        let on = soundOn
        writes.run { await keep.keep(soundOn: on) }
    }

    // MARK: background

    /// The app went to the background: the table's socket and any link close. Returns once the
    /// socket work queued so far is done.
    func background() async {
        guard started, !asleep else { return }
        asleep = true
        stopLink(&homeWatch)
        stopLink(&menuWatch)
        step { await self.syncSleep() }
        await steps?.value
    }

    /// Back in front: the TV joins its table again, and shows a fresh link where it showed one.
    func active() async {
        guard started, asleep else { return }
        asleep = false
        if phase == .home { startHomeLink() }
        if menu == .link, let table { startMenuLink(showing: table.code) }
        step { await self.syncSleep() }
        await steps?.value
    }

    /// Brings the shown table's socket in line with `asleep`, in the socket queue, so a quick
    /// background and return (or a move under way) always ends with the socket the TV wants: down
    /// in the background, up in front. A later change queues another sync after this one.
    private func syncSleep() async {
        guard let table = ready, table === self.table else { return }
        while true {
            let sleep = asleep
            if sleep {
                await table.suspend()
            } else {
                table.start()
                await table.resume()
            }
            // Another table now (its own show step starts it, after this one closes) or the same
            // wish after the await: done. Otherwise the app changed its mind meanwhile: again.
            guard self.table === table, asleep != sleep else { return }
        }
    }

    // MARK: links

    private func startHomeLink() {
        guard phase == .home, !asleep, homeWatch == nil else { return }
        homeWatch = watch(showing: nil) { [weak self] event in
            guard let self else { return }
            switch event {
            case .code(_, let code, let url):
                homeLink = Link(code: code, url: url)
                homeOffline = false
                #if DEBUG
                fputs("[tv] link \(code) \(url.absoluteString)\n", stderr)
                #endif
            case .offline:
                homeOffline = true
            case .linked(let room):
                // The link is spent; showing the table stops it.
                guard phase == .home else { return }
                show(room)
            }
        }
    }

    private func startMenuLink(showing code: String) {
        guard !asleep, menuWatch == nil else { return }
        menuLink = nil
        menuOffline = false
        menuWatch = watch(showing: code) { [weak self] event in
            guard let self else { return }
            switch event {
            case .code(_, let code, let url):
                menuLink = Link(code: code, url: url)
                menuOffline = false
                #if DEBUG
                fputs("[tv] link \(code) \(url.absoluteString)\n", stderr)
                #endif
            case .offline:
                menuOffline = true
            case .linked(let room):
                move(to: room)
            }
        }
    }

    private func watch(showing: String?, _ handle: @escaping @MainActor (ScreenLinkEvent) -> Void) -> LinkWatch {
        let link = services.link()
        let task = Task {
            await link.start(showing: showing)
            for await event in link.events {
                guard !Task.isCancelled else { return }
                handle(event)
            }
        }
        return LinkWatch(link: link, task: task)
    }

    private func stopLink(_ watch: inout LinkWatch?) {
        watch?.stop()
        watch = nil
    }

    // MARK: helpers

    private func step(_ work: @escaping @MainActor () async -> Void) {
        let previous = steps
        steps = Task {
            await previous?.value
            await work()
        }
    }

    private func keep(room: String?) {
        let keep = services.keep
        writes.run { await keep.keep(room: room) }
    }
}
