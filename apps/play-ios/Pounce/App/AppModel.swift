import Foundation
import Observation
import PounceKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    var route: Route
    var people: LocalPeople
    /// The server's list of this device's tables (Home).
    var tables: [TableEntry] = []
    /// Locally cached table summaries by room code, so Home can draw before sockets connect.
    var cache: [String: CachedTable]
    /// Set when creating a room failed; cleared by the next attempt.
    var newGameError: APIError?
    private(set) var isCreatingRoom = false
    /// The one live room connection (spec §7.2): the room on screen, or a typed code being
    /// checked from Join. Replaced or closed whenever the route leaves it.
    private(set) var room: RoomSession?
    /// The code Join is checking (its socket is `room`); nil once it arrives or fails.
    private(set) var probing: String?
    /// Bumped when a typed or linked code turns out not to exist; Join shakes on each bump.
    private(set) var joinNope = 0
    /// The bad code that bounced a link to Join, shown in the tiles before they shake.
    private(set) var bouncedCode: String?

    let api: APIClient
    let config: APIConfig
    let settings: Settings
    @ObservationIgnored let peopleStore: PeopleStore
    @ObservationIgnored let tableCache: TableCache

    init(
        config: APIConfig, credentials: CredentialStore, dataDirectory: URL, settings: Settings = .shared
    ) {
        api = APIClient(config: config, credentials: credentials)
        self.config = config
        self.settings = settings
        peopleStore = PeopleStore(directory: dataDirectory)
        tableCache = TableCache(directory: dataDirectory)
        let loaded = peopleStore.load()
        people = loaded
        cache = tableCache.all()
        route = loaded.owner == nil ? .pickCat(then: nil) : .home
    }

    /// The real app model, or the throwaway one for `-uitest-reset` (fresh temp data directory,
    /// in-memory credential, scratch settings).
    static func makeDefault(
        arguments: [String] = CommandLine.arguments,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppModel {
        let config = AppConfig.load(env: env)
        if arguments.contains("-uitest-reset") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pounce-uitest-\(UUID().uuidString)", isDirectory: true)
            return AppModel(config: config, credentials: MemoryCredentialStore(), dataDirectory: dir)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppModel(
            config: config, credentials: KeychainCredentialStore(),
            dataDirectory: support.appendingPathComponent("Pounce", isDirectory: true))
    }

    /// Called once at launch: reload local data, mint the device credential in the background,
    /// then refresh Home's table list. Never blocks the first frame.
    func bootstrap() async {
        reloadLocal()
        _ = try? await api.credential()
        if people.owner != nil { await refreshTables() }
    }

    func reloadLocal() {
        people = peopleStore.load()
        cache = tableCache.all()
    }

    /// Saves the owner, then continues to the link that interrupted onboarding, or Home.
    func finishPickCat(name: String, cat: Int) {
        peopleStore.setOwner(name: name, cat: cat)
        people = peopleStore.load()
        if case .pickCat(let then?) = route {
            handle(then)
        } else {
            route = .home
        }
        Task { await refreshTables() }
    }

    /// Home's cards: the server's list joined with the local cache.
    var homeItems: [HomeTableItem] {
        HomeTables.merge(entries: tables, cache: cache, now: .now)
    }

    func refreshTables() async {
        cache = tableCache.all()
        do {
            let listed = try await api.listTables()
            tables = listed
            // A cached room the server no longer lists is gone for good.
            let live = Set(listed.map(\.code))
            for code in cache.keys where !live.contains(code) { tableCache.remove(code: code) }
            cache = tableCache.all()
        } catch {
            // Offline or server down: keep the last list; Home still draws from the cache.
        }
    }

    func newGame() async {
        guard !isCreatingRoom else { return }
        isCreatingRoom = true
        newGameError = nil
        defer { isCreatingRoom = false }
        do {
            let code = try await api.createRoom()
            open(code: code, intent: .create)
        } catch let error as APIError {
            newGameError = error
        } catch {
            newGameError = .transport(String(describing: error))
        }
    }

    func open(code: String, intent: RoomIntent) {
        ensureRoom(code: code, intent: intent)
        route = .room(code: code, intent: intent)
    }

    /// The live session for `code`, created (and the previous one closed) if needed.
    @discardableResult
    func ensureRoom(code: String, intent: RoomIntent) -> RoomSession {
        if let room, room.code == code {
            probing = nil
            return room
        }
        closeRoom()
        let session = makeSession(code: code, intent: intent)
        room = session
        session.start()
        return session
    }

    /// Join's keypad finished a code. A table this device knows rejoins at once; any other
    /// code is checked first while Join stays on screen, so a bad one can shake the tiles.
    func joinTyped(_ code: String) {
        if isKnown(code) {
            open(code: code, intent: .rejoin)
            return
        }
        closeRoom()
        let session = makeSession(code: code, intent: .join)
        room = session
        probing = code
        session.start()
    }

    /// Join's tiles changed while a code was being checked: drop that check.
    func cancelProbe() {
        guard probing != nil else { return }
        closeRoom()
    }

    /// Hands Join the code that bounced it here (once).
    func takeBouncedCode() -> String? {
        defer { bouncedCode = nil }
        return bouncedCode
    }

    func closeRoom() {
        probing = nil
        guard let room else { return }
        self.room = nil
        room.close()
    }

    /// In the table cache or the last `/tables`: a 404 for it means the room closed.
    func isKnown(_ code: String) -> Bool {
        cache[code] != nil || tables.contains { $0.code == code } || tableCache.contains(code: code)
    }

    /// Scene phase: the room socket goes down in the background and comes back on return.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active: room?.foreground()
        case .background: room?.background()
        default: break
        }
    }

    private func makeSession(code: String, intent: RoomIntent) -> RoomSession {
        let config = config
        let api = api
        let socket = SuspendableSocket {
            RoomSocket(code: code, config: config, credential: { try await api.credential() })
        }
        let session = RoomSession(code: code, intent: intent, socket: socket)
        session.owner = { [weak self] in self?.people.owner }
        session.onSnapshot = { [weak self] room in self?.remember(room) }
        session.onArrive = { [weak self, weak session] in
            guard let self, let session, self.room === session, self.probing == session.code else { return }
            self.probing = nil
            self.route = .room(code: session.code, intent: .join)
        }
        session.onGone = { [weak self, weak session] phase in
            guard let self, let session, self.room === session else { return }
            self.roomGone(session, phase: phase)
        }
        return session
    }

    /// `room_closed`, or a 404 on connect.
    private func roomGone(_ session: RoomSession, phase: RoomPhase) {
        let meaning: NotFoundMeaning
        if phase == .closed {
            meaning = .roomClosed
        } else {
            // A room this screen already saw, or one this device made or sat at, closed.
            let known = session.arrived || session.intent != .join || isKnown(session.code)
            meaning = RoomEntry.notFoundMeaning(code: session.code, known: known)
        }
        session.goneMeaning = meaning
        switch meaning {
        case .roomClosed:
            forget(session.code)
            Task { await refreshTables() }
        case .badCode:
            let wasProbing = probing == session.code
            closeRoom()
            if !wasProbing { bouncedCode = session.code }
            joinNope += 1
            route = .join
        }
    }

    /// Caches a room this device sits at, so Home can draw it before connecting.
    private func remember(_ room: RoomView) {
        tableCache.store(room)
        cache[room.code] = tableCache.all()[room.code]
    }

    private func forget(_ code: String) {
        tableCache.remove(code: code)
        cache[code] = nil
        tables.removeAll { $0.code == code }
    }

    /// A share or move link arrived. Without a local owner, onboarding comes first and the link
    /// is remembered. A join link for a table already on this device rejoins it.
    func handle(_ link: DeepLink) {
        guard people.owner != nil else {
            route = .pickCat(then: link)
            return
        }
        switch link {
        case .join(let code):
            open(code: code, intent: tableCache.contains(code: code) ? .rejoin : .join)
        case .move(let code, let moveCode):
            open(code: code, intent: .move(moveCode: moveCode))
        }
    }

    func showJoin() {
        closeRoom()
        route = .join
    }

    // MARK: People on this phone (edits apply to tables joined afterwards)

    func updateOwner(name: String, cat: Int) {
        peopleStore.setOwner(name: name, cat: cat)
        people = peopleStore.load()
    }

    @discardableResult
    func addPerson(name: String, cat: Int) -> Person {
        let person = peopleStore.add(name: name, cat: cat)
        people = peopleStore.load()
        return person
    }

    func updatePerson(_ person: Person) {
        peopleStore.update(person)
        people = peopleStore.load()
    }

    func removePerson(id: String) {
        peopleStore.remove(id: id)
        people = peopleStore.load()
    }

    func goHome() {
        guard people.owner != nil else { return }
        closeRoom()
        cache = tableCache.all()
        route = .home
    }
}
