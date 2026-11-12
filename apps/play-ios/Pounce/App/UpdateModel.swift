import Foundation
import Observation
import PounceKit
import StoreKit
import UIKit

/// Update awareness (docs/superpowers/specs/2026-11-12-app-updates-design.md): what the server
/// says is current, and the three moments that follow from it.
///
/// - Soft: a newer version is on the App Store. Home shows a small card (`softVersion`).
/// - A table needs a newer app: the room's own card, and the table stays on Home behind a
///   padlock (`lockedRows`).
/// - Hard: this version is too old for the server (`required`). One full screen over everything.
///
/// The decisions are `UpdatePolicy`'s (PounceKit, unit tested); this holds the state and does
/// the fetching, the remembering and the opening of links.
@MainActor @Observable
final class UpdateModel {
    /// The running app's version (`CFBundleShortVersionString`).
    let current: String
    /// What this device remembers: the server's last answer, the soft card's memory, refused tables.
    private(set) var record: UpdateRecord
    /// The server no longer supports this version, and what it said about getting a newer one.
    private(set) var required: UpdateRequirement?
    /// The tables the server's list says are locked for this app, from the last tables fetch.
    var serverLocked: [LockedTable] = []
    /// How this copy was installed. The App Store until StoreKit says otherwise.
    private(set) var channel: InstallChannel = .appStore

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let store: UpdateStore
    /// A demo, a UI test or a screenshot run: nothing is fetched and the soft card stays away.
    @ObservationIgnored private let staged: Bool
    @ObservationIgnored private var started = false

    init(api: APIClient, directory: URL, arguments: [String] = CommandLine.arguments, env: [String: String] = ProcessInfo.processInfo.environment) {
        self.api = api
        store = UpdateStore(directory: directory)
        current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var staged = RatingPrompt.isStaged(arguments: arguments, env: env)
        var record = store.load()
        record.locked = LockedTables.pruned(record.locked, now: .now)
        #if DEBUG
        if let demo = UpdateDemo.from(arguments: arguments) {
            // Canned, never saved: the demo shows its moment and touches nothing on disk.
            record = demo.record(current: current)
            serverLocked = demo.serverLocked
            required = demo.required
            staged = true
            self.record = record
            self.staged = staged
            softInDemo = demo == .soft
            channel = UpdateDemo.channel(arguments: arguments) ?? .appStore
            return
        }
        if let forced = UpdateDemo.channel(arguments: arguments) { channel = forced }
        #endif
        self.record = record
        self.staged = staged
    }

    #if DEBUG
    /// `-demo-update soft`: the card shows although the run is staged.
    @ObservationIgnored private var softInDemo = false
    #endif

    var status: AppStatus? { record.status }

    // MARK: asking the server

    /// At launch: hears every "too old" answer from here on, finds out how the app was
    /// installed, and asks what is current.
    func start() async {
        guard !started else { return }
        started = true
        guard !staged else { return }
        await api.setUpdateRequiredHandler { [weak self] need in
            Task { @MainActor in self?.require(need) }
        }
        channel = await Self.installedFrom()
        await refresh()
    }

    /// Asks what is current, at most every six hours (or now, with `force`). A failure keeps
    /// the last answer: nobody is told anything new on a guess.
    func refresh(force: Bool = false) async {
        guard !staged, force || required != nil || UpdatePolicy.shouldRefresh(fetchedAt: record.fetchedAt, now: .now) else { return }
        do {
            let status = try await api.appStatus()
            record = store.update { record in
                record.status = status
                record.fetchedAt = .now
            }
            // The server's word now: too old, or (a minimum taken back, an update installed) not.
            required = UpdatePolicy.isRequired(current: current, status: status)
                ? UpdateRequirement(minimum: status.minimum, storeUrl: status.storeUrl, testflightUrl: status.testflightUrl) : nil
        } catch APIError.updateRequired(let need) {
            require(need)
        } catch {
            // Offline, or a server that doesn't have the route yet.
        }
    }

    /// The server refused a call or a table: this version is no longer supported.
    func require(_ need: UpdateRequirement) {
        required = need
    }

    // MARK: the soft card

    /// The version Home's card offers now, or nil for no card.
    var softVersion: String? {
        #if DEBUG
        if softInDemo { return record.status?.latest }
        #endif
        return UpdatePolicy.soft(current: current, status: record.status, channel: channel, state: record.soft, now: .now, staged: staged)
    }

    /// The card's close button, or its Update button: that version's card is done.
    func dismissSoft() {
        guard let version = softVersion else { return }
        #if DEBUG
        if softInDemo {
            softInDemo = false
            return
        }
        #endif
        record = store.update { $0.soft = UpdatePolicy.dismissed($0.soft, version: version, now: .now) }
    }

    // MARK: tables behind an update

    /// The games this build can draw.
    static var drawable: Set<String> { Set(GameCatalog.all.filter(\.isAvailable).map(\.id)) }

    /// Home's padlocked rows: the server's locked tables and the ones this device was refused at.
    func lockedRows(listed: [TableEntry]) -> [LockedTables.Row] {
        LockedTables.rows(
            server: serverLocked, local: record.locked, listed: Set(listed.map(\.code)), drawable: Self.drawable, now: .now)
    }

    /// The server said this table's game needs a newer app: keep the table for Home.
    func remember(code: String, game: String, title: String?) {
        guard !staged else { return }
        record = store.update { $0.locked = LockedTables.remembering($0.locked, code: code, game: game, title: title, now: .now) }
    }

    /// The table closed, or never was: nothing to keep.
    func forget(code: String) {
        guard record.locked.contains(where: { $0.code == code }) else { return }
        record = store.update { $0.locked.removeAll { $0.code == code } }
    }

    // MARK: the Update button

    /// What Update does on this device. `need`: a refusal's own links, which beat the last status.
    func action(band: AgeBand?, need: UpdateRequirement? = nil) -> UpdatePolicy.Action {
        UpdatePolicy.action(
            channel: channel, band: band, storeUrl: need?.storeUrl ?? record.status?.storeUrl,
            testflightUrl: need?.testflightUrl ?? record.status?.testflightUrl)
    }

    /// What stands between this device and a table of a game it can't draw.
    func tableAdvice(band: AgeBand?) -> UpdatePolicy.TableAdvice {
        UpdatePolicy.tableAdvice(current: current, status: record.status, channel: channel, band: band)
    }

    func open(_ action: UpdatePolicy.Action) {
        switch action {
        case .store(let url), .testFlight(let url): UIApplication.shared.open(url)
        case .askGrownUp: break
        }
    }

    /// TestFlight builds run against StoreKit's sandbox; the App Store's against production.
    /// A build run from Xcode, or in the simulator, counts as the App Store's.
    private static func installedFrom() async -> InstallChannel {
        #if DEBUG || targetEnvironment(simulator)
        return .appStore
        #else
        guard case .verified(let transaction)? = try? await AppTransaction.shared else { return .appStore }
        return transaction.environment == .sandbox ? .testFlight : .appStore
        #endif
    }
}

#if DEBUG
/// `-demo-update <soft|locked|table|required>`: one of the update moments with no server (the
/// screenshots in `Art/screenshots/app-updates/`). `-update-channel testflight` makes any run a
/// TestFlight install; `-age-band kitten` (with `-uitest-reset`) makes it a child's device.
///
/// - `soft`: Home with "A new Pounce is ready".
/// - `locked`: Home with a table behind a padlock.
/// - `table`: a table that answers "this game needs a newer app" (Tuna Tiles); add
///   `-update-latest none` for the wording when the store has nothing newer.
/// - `required`: the full "Update Pounce to keep playing" screen.
enum UpdateDemo: String {
    case soft, locked, table, required

    static let code = "GH2VD"

    static func from(arguments: [String]) -> UpdateDemo? {
        guard let i = arguments.firstIndex(of: "-demo-update"), arguments.indices.contains(i + 1) else { return nil }
        return UpdateDemo(rawValue: arguments[i + 1])
    }

    static func channel(arguments: [String]) -> InstallChannel? {
        guard let i = arguments.firstIndex(of: "-update-channel"), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1] == "testflight" ? .testFlight : .appStore
    }

    /// A version above whatever this build is.
    private static let newer = "99.0"

    func record(current: String) -> UpdateRecord {
        let args = CommandLine.arguments
        let none = args.firstIndex(of: "-update-latest").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } == "none"
        return UpdateRecord(status: AppStatus(latest: none ? nil : Self.newer, minimum: self == .required ? Self.newer : nil), fetchedAt: .now)
    }

    var serverLocked: [LockedTable] {
        guard self == .locked else { return [] }
        let seats = [
            TableSeat(kind: .human, person: Person(id: "demo-mia", name: DemoFixtures.castName(1, "Mia"), cat: 2)),
            TableSeat(kind: .human, person: Person(id: "demo-leo", name: DemoFixtures.castName(2, "Leo"), cat: 5)),
        ]
        return [
            LockedTable(
                code: Self.code, name: "Taco Night", game: GameCatalog.tiles.id, title: GameCatalog.tiles.title,
                updatedAt: Date.now.timeIntervalSince1970 * 1000, seats: seats)
        ]
    }

    var required: UpdateRequirement? {
        self == .required ? UpdateRequirement(minimum: Self.newer) : nil
    }

    /// The `table` demo's socket: the server's answer to an app that can't draw the game.
    static func refusingSocket() -> any RoomSocketing {
        RefusingSocket(refusal: .game(id: GameCatalog.tiles.id, title: GameCatalog.tiles.title))
    }
}

/// A socket whose every connect is refused the same way.
private actor RefusingSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let refusal: UpdateRefusal

    init(refusal: UpdateRefusal) {
        self.refusal = refusal
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() {
        continuation.yield(.connecting)
        continuation.yield(.refused(refusal))
        continuation.finish()
    }

    func send(_ m: ClientMessage) throws { throw RoomSocketError.notConnected }
    func reconnectNow() {}
    func stop() { continuation.finish() }
}
#endif
