import Foundation
import Observation
import PounceKit

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

    let api: APIClient
    let settings: Settings
    @ObservationIgnored let peopleStore: PeopleStore
    @ObservationIgnored let tableCache: TableCache

    init(
        config: APIConfig, credentials: CredentialStore, dataDirectory: URL, settings: Settings = .shared
    ) {
        api = APIClient(config: config, credentials: credentials)
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

    func refreshTables() async {
        cache = tableCache.all()
        do {
            tables = try await api.listTables()
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
        route = .room(code: code, intent: intent)
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

    func goHome() {
        guard people.owner != nil else { return }
        cache = tableCache.all()
        route = .home
    }
}
