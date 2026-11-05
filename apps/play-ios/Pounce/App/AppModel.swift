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
    /// Tables archived off Home on this phone: room code to the server's `updatedAt` then.
    private(set) var archived: [String: Double]
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
    @ObservationIgnored let tableArchive: TableArchive
    @ObservationIgnored let tutorialStore: TutorialStore
    /// The coaching tips each person on this phone has seen (first-game tutorial).
    private(set) var tipsSeen: TipsSeen
    /// Coaching tips show on the table. Off for the UI tests and demos, which never expect a
    /// bubble over the table, unless `-tips` asks for them, and under `-no-tips` (DEBUG only).
    var tipsEnabled = true
    /// Bumped by "Show the tips again": tables turn tips back on for everyone.
    private(set) var tipsReplays = 0
    /// Push and local notifications; attached by the app delegate once SwiftUI built this model.
    @ObservationIgnored weak var push: PushCoordinator?

    // MARK: age (spec §14.1)

    @ObservationIgnored let ageStore: AgeRecordStore
    @ObservationIgnored let ageAsker: AgeRangeAsking
    /// The phone owner's age band and where it came from; nil until the age check ran.
    private(set) var ageRecord: AgeRecord?
    var ageBand: AgeBand? { ageRecord?.band }
    /// What the owner's band allows on this device. Unknown counts as the most limited.
    var limits: AgeLimits { AgeLimits(band: ageBand) }
    /// Players, Sign in with Apple and sync (spec §10.5, §13.1).
    @ObservationIgnored private(set) var account: AccountModel!

    /// This phone had a person before this version asked ages: an existing player, for whom this
    /// update is a significant change (§14.1). A new install agreed to it at download.
    @ObservationIgnored private(set) var hadOwnerBeforeThisVersion = false

    /// The local "your turn" reminder: the person's choice, else the band's default.
    var turnReminderOn: Bool { settings.turnReminderChoice ?? limits.turnReminderDefault }

    init(
        config: APIConfig, credentials: CredentialStore, dataDirectory: URL, settings: Settings = .shared,
        ageStore: AgeRecordStore = KeychainAgeRecordStore(), ageAsker: AgeRangeAsking = LiveAgeRange(),
        personKeys: PersonKeyStore = KeychainPersonKeyStore()
    ) {
        api = APIClient(config: config, credentials: credentials)
        self.config = config
        self.settings = settings
        peopleStore = PeopleStore(directory: dataDirectory)
        tableCache = TableCache(directory: dataDirectory, fileName: TableCache.fileName(for: config))
        tableArchive = TableArchive(directory: dataDirectory, fileName: TableArchive.fileName(for: config))
        let loaded = peopleStore.load()
        people = loaded
        cache = tableCache.all()
        archived = tableArchive.all()
        tutorialStore = TutorialStore(directory: dataDirectory)
        tipsSeen = tutorialStore.load()
        self.ageStore = ageStore
        self.ageAsker = ageAsker
        let age = ageStore.load()
        ageRecord = age
        hadOwnerBeforeThisVersion = age == nil && loaded.owner != nil
        route = age == nil ? .age(then: nil) : loaded.owner == nil ? .pickCat(then: nil) : .home
        #if DEBUG
        let stub = StubScenario.from(arguments: CommandLine.arguments)
        let service: AccountService = stub.map { StubAccountService(scenario: $0) } ?? api
        let apple: AppleSigning = stub.map { StubAppleSignIn(scenario: $0) } ?? LiveAppleSignIn()
        #else
        let service: AccountService = api
        let apple: AppleSigning = LiveAppleSignIn()
        #endif
        account = AccountModel(
            app: self, service: service, apple: apple, keys: personKeys,
            store: AccountStore(directory: dataDirectory, fileName: AccountStore.fileName(for: config)))
        // Before anything can upload: hold accounts while this update's approval may be owed.
        SignificantChangeGate.prepare(self)
    }

    /// The real app model, or (DEBUG only) the throwaway one for `-uitest-reset` (fresh temp data
    /// directory, in-memory credential, scratch settings). The real one keeps its Keychain
    /// credential and table cache per server (`host:port`), so a Debug build on the dev server and
    /// a Release build on production never use each other's device identity.
    static func makeDefault(
        arguments: [String] = CommandLine.arguments,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppModel {
        let config = AppConfig.load(env: env)
        #if DEBUG
        let model: AppModel
        let asker = debugAgeAsker(arguments: arguments, env: env)
        if arguments.contains("-uitest-reset") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pounce-uitest-\(UUID().uuidString)", isDirectory: true)
            model = AppModel(
                config: config, credentials: MemoryCredentialStore(), dataDirectory: dir,
                ageStore: debugAgeStore(arguments: arguments), ageAsker: asker, personKeys: MemoryPersonKeyStore())
        } else {
            model = real(config: config, ageAsker: asker)
        }
        // `-seed-people`: a fresh run starts with an owner and two others (screenshots).
        if arguments.contains("-uitest-reset"), arguments.contains("-seed-people"), model.people.owner == nil {
            model.peopleStore.setOwner(name: "JD", cat: 4)
            model.peopleStore.add(name: "Ella", cat: 2)
            model.peopleStore.add(name: "Sam", cat: 6)
            model.people = model.peopleStore.load()
            if model.ageRecord != nil { model.route = .home }
        }
        // `-show-merge`: the two-cats question over the gear sheet (screenshots).
        if arguments.contains("-show-merge") {
            model.account.merge = .init(mine: 4, theirs: 2, theirName: StubAccountService.other.name, asking: true)
        }
        if let demo = DemoMode.from(arguments: arguments) { model.openDemo(demo) }
        if arguments.contains("-uitest-reset") || DemoMode.from(arguments: arguments) != nil {
            model.tipsEnabled = arguments.contains("-tips")
        }
        if arguments.contains("-no-tips") { model.tipsEnabled = false }
        // `-show-join`: open on Join (scripts/screenshots.sh).
        if arguments.contains("-show-join"), model.people.owner != nil { model.route = .join }
        // `-open-link <pounce-dev://…>`: open a share or move link at launch, as if tapped
        // (scripts/multi-sim.sh; `simctl openurl` stops at an "Open in Pounce?" system prompt).
        if let i = arguments.firstIndex(of: "-open-link"), let text = arguments[safe: i + 1],
           let url = URL(string: text), let link = DeepLink.parse(url, allowDevScheme: true) {
            model.handle(link)
        }
        return model
        #else
        return real(config: config)
        #endif
    }

    private static func real(config: APIConfig, ageAsker: AgeRangeAsking = LiveAgeRange()) -> AppModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppModel(
            config: config,
            credentials: KeychainCredentialStore(service: KeychainCredentialStore.serviceName(for: config)),
            dataDirectory: support.appendingPathComponent("Pounce", isDirectory: true),
            ageAsker: ageAsker)
    }

    #if DEBUG
    /// `-age-range <answer>` stubs Declared Age Range; any test run (`-anim-speed`) without it
    /// answers "adult", so the existing tests never meet the system sheet.
    private static func debugAgeAsker(arguments: [String], env: [String: String]) -> AgeRangeAsking {
        if let stub = StubAgeRange(arguments: arguments) { return stub }
        if PaceSetting.resolve(arguments: arguments, env: env).underTest { return StubAgeRange(answer: .band(.adult)) }
        return LiveAgeRange()
    }

    /// Under `-uitest-reset`: `-uitest-age-service <name>` keeps the record in a Keychain item of
    /// its own (the can't-retry test); `-age-band <band>` starts with that band; `-age-range`
    /// starts with none (the age screen); otherwise an adult, as before the age screen existed.
    private static func debugAgeStore(arguments: [String]) -> AgeRecordStore {
        if let i = arguments.firstIndex(of: "-uitest-age-service"), let service = arguments[safe: i + 1] {
            return KeychainAgeRecordStore(service: service)
        }
        if let i = arguments.firstIndex(of: "-age-band"), let band = arguments[safe: i + 1].flatMap(AgeBand.init) {
            return MemoryAgeRecordStore(AgeRecord(band: band, source: .keypad, checkedAt: .now))
        }
        if arguments.contains("-age-range") { return MemoryAgeRecordStore() }
        return MemoryAgeRecordStore(AgeRecord(band: .adult, source: .declared, checkedAt: .now))
    }
    #endif

    #if DEBUG
    /// `-demo <screen>`: the room screen fed by one fixture snapshot, no server, nothing cached.
    func openDemo(_ demo: DemoMode) {
        closeRoom()
        let room = demo.room
        let socket = SuspendableSocket { demo.makeSocket() }
        let session = RoomSession(code: room.code, intent: .rejoin, socket: socket)
        session.owner = { [weak self] in self?.people.owner }
        session.people = { [weak self] in self?.everyone ?? [] }
        self.room = session
        session.start()
        route = .room(code: room.code, intent: .rejoin)
        // `-demo-home-after <seconds>`: leave the table mid-animation (teardown check).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-demo-home-after"), let secs = args[safe: i + 1].flatMap(Double.init) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(secs))
                print("[demo] going home")
                self?.closeRoom()
                self?.route = .home
            }
        }
    }
    #endif

    /// Called once at launch: reload local data, mint the device credential in the background,
    /// then refresh Home's table list. Never blocks the first frame.
    func bootstrap() async {
        reloadLocal()
        _ = try? await api.credential()
        #if DEBUG
        await account.applyDebugPreset()
        #endif
        if ageRecord != nil { await accountsAfterAge() }
        if people.owner != nil { await refreshTables() }
        await recheckAge()
    }

    /// Once the age is known: the significant-change check, then the profile and sync.
    private func accountsAfterAge() async {
        await SignificantChangeGate.check(self)
        await account.uploadProfile()
        await account.sync()
    }

    // MARK: Age check (spec §14.1)

    /// The age screen's first step: Declared Age Range. True when it gave a band (and the
    /// screen moved on); false sends the person to the birth-year keypad.
    func askDeclaredAge() async -> Bool {
        guard ageRecord == nil else { return true }
        guard case .band(let band) = await ageAsker.ask() else { return false }
        finishAge(band, source: .declared)
        return true
    }

    /// Keeps the band (only the band) and goes on to pick-a-cat, the link that was waiting, or Home.
    func finishAge(_ band: AgeBand, source: AgeRecord.Source) {
        let record = AgeRecord(band: band, source: source, checkedAt: .now)
        ageStore.save(record)
        ageRecord = record
        applyAgeLimits()
        Task { await accountsAfterAge() }
        guard case .age(let then) = route else { return }
        if people.owner == nil {
            route = .pickCat(then: then)
        } else if let then {
            route = .home
            handle(then)
        } else {
            route = .home
        }
    }

    /// At most once a week, Declared Age Range again: a kitten who turned 13 gets the limits lifted.
    func recheckAge() async {
        guard var record = ageRecord, record.needsRecheck(now: .now) else { return }
        if case .band(let band) = await ageAsker.ask() {
            record.band = band
            record.source = .declared
        }
        record.checkedAt = .now
        ageStore.save(record)
        ageRecord = record
        applyAgeLimits()
    }

    /// A kitten keeps no typed name (a name plus an identifier is personal information): an owner
    /// from before the age check gets a generated one.
    private func applyAgeLimits() {
        guard !limits.typedNames, let owner = people.owner, AgeLimits.needsGeneratedName(owner.name) else { return }
        updateOwner(name: CatEditorView.randomName(), cat: owner.cat)
    }

    func reloadLocal() {
        people = peopleStore.load()
        cache = tableCache.all()
    }

    /// Saves the owner, then continues to the link that interrupted onboarding, or Home.
    func finishPickCat(name: String, cat: Int) {
        let owner = peopleStore.setOwner(name: name, cat: cat)
        people = peopleStore.load()
        account.noteChanged(owner.id)
        #if DEBUG
        Task { await account.applyDebugPreset() }
        #endif
        if case .pickCat(let then?) = route {
            handle(then)
        } else {
            route = .home
        }
        Task { await refreshTables() }
    }

    /// Home's cards: the server's list joined with the local cache, less what's archived.
    var homeItems: [HomeTableItem] {
        HomeTables.merge(entries: tables, cache: cache, archived: archived, now: .now)
    }

    /// Home's Archived sheet.
    var archivedItems: [HomeTableItem] {
        HomeTables.archivedItems(entries: tables, cache: cache, archived: archived, now: .now)
    }

    /// Hides a table from Home. The seat stays: links, pushes and Join still open it, and it
    /// comes back by itself when it is your turn there again.
    func archive(code: String) {
        let updatedAt = tables.first { $0.code == code }?.updatedAt ?? Date.now.timeIntervalSince1970 * 1000
        tableArchive.archive(code: code, updatedAt: updatedAt)
        archived = tableArchive.all()
        account.noteLocalChanges()
    }

    func restore(code: String) {
        tableArchive.restore(code: code)
        archived = tableArchive.all()
        account?.noteLocalChanges()
    }

    func refreshTables() async {
        cache = tableCache.all()
        do {
            let listed = try await api.listTables()
            tables = listed
            // The icon's badge: tables where it's your move (spec §12.5), on every device.
            push?.setBadge(PushPolicy.badgeCount(listed))
            // The server answered: a push token that failed to upload goes now.
            push?.retryUpload()
            // A cached room the server no longer lists is gone for good.
            let live = Set(listed.map(\.code))
            for code in cache.keys where !live.contains(code) { tableCache.remove(code: code) }
            cache = tableCache.all()
            // Forget archived rooms that closed, and ones a new turn brought back.
            tableArchive.replace(with: HomeTables.keptArchive(entries: listed, archived: tableArchive.all()))
            archived = tableArchive.all()
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
        let session = ensureRoom(code: code, intent: intent)
        // A move link for the room already open: its first snapshot is long gone, so claim now.
        if case .move(let moveCode) = intent, session.intent != intent { session.claimMove(moveCode) }
        route = .room(code: code, intent: intent)
    }

    /// The table for `code` is the screen in front (a push for it needs no banner).
    func isOnScreen(code: String) -> Bool {
        if case .room(let onScreen, _) = route { return onScreen == code }
        return false
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
    /// Going away mid-turn also schedules the local "your turn" reminder (spec §7.5): the server
    /// only pushes when a turn starts. Coming back cancels it and retries a held push token.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            room?.foreground()
            Task {
                await account.uploadProfile()
                await account.sync()
            }
            // Every reminder, not just this launch's: one may predate a relaunch.
            push?.cancelAllTurnReminders()
            push?.retryUpload()
        case .background:
            scheduleTurnReminder()
            room?.background()
        default: break
        }
    }

    private func scheduleTurnReminder() {
        #if DEBUG
        // `-debug-reminder <CODE>`: schedule one on every background, whoever's turn it is.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-debug-reminder"), let code = args[safe: i + 1] {
            push?.scheduleTurnReminder(
                code: code, name: "Debug", table: TableName.fallback(code: code), after: PushPolicy.reminderInterval)
            return
        }
        #endif
        guard turnReminderOn else { return }
        guard let room, let table = room.model, let delay = PushPolicy.reminderDelay(model: table),
              let turn = table.currentSeat, let person = table.room.seats[safe: turn]?.person else { return }
        push?.scheduleTurnReminder(code: room.code, name: person.name, table: table.room.title, after: delay)
    }

    private func makeSession(code: String, intent: RoomIntent) -> RoomSession {
        let config = config
        let api = api
        let socket = SuspendableSocket {
            RoomSocket(code: code, config: config, credential: { try await api.credential() })
        }
        let session = RoomSession(code: code, intent: intent, socket: socket)
        session.owner = { [weak self] in self?.people.owner }
        session.people = { [weak self] in self?.everyone ?? [] }
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
        restore(code: code)
        tables.removeAll { $0.code == code }
    }

    /// A share or move link arrived. Without a local owner, onboarding comes first and the link
    /// is remembered. A join link for a table already on this device rejoins it.
    func handle(_ link: DeepLink) {
        guard ageRecord != nil else {
            route = .age(then: link)
            return
        }
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

    // MARK: People on this phone

    /// The owner, then the others who share this phone.
    var everyone: [Person] { [people.owner].compactMap { $0 } + people.others }

    /// A new name or cat. A new name also reaches the open table at once (the other tables
    /// this phone sits at catch up when they next open); a new cat applies to tables joined
    /// afterwards.
    func updateOwner(name: String, cat: Int) {
        let owner = peopleStore.setOwner(name: name, cat: cat)
        people = peopleStore.load()
        room?.syncNames()
        account?.noteChanged(owner.id)
    }

    /// Renames whoever sits at `seat` of the open table: the person on this phone with that
    /// id (so the new name sticks for later tables too), or, for a seat moved here from
    /// another phone, just that seat.
    func renamePerson(seat: Seat, person: Person, to name: String) {
        if let local = everyone.first(where: { $0.id == person.id }) {
            if local.id == people.owner?.id {
                updateOwner(name: name, cat: local.cat)
            } else {
                updatePerson(Person(id: local.id, name: name, cat: local.cat))
            }
        } else {
            room?.send(.renameSeat(seat: seat, name: name))
        }
    }

    /// Someone else who shares this phone, with the age band whoever added them picked (§14.1).
    @discardableResult
    func addPerson(name: String, cat: Int, band: AgeBand) -> Person {
        let person = peopleStore.add(name: name, cat: cat)
        people = peopleStore.load()
        account.noteAdded(person.id, band: band)
        return person
    }

    func updatePerson(_ person: Person) {
        peopleStore.update(person)
        people = peopleStore.load()
        room?.syncNames()
        account.noteChanged(person.id)
    }

    func removePerson(id: String) {
        peopleStore.remove(id: id)
        people = peopleStore.load()
        account.noteRemoved(id)
    }

    // MARK: Accounts: what the account model changes here

    /// The profile upload gave people new ids: reload them and their tips.
    func peopleRenamed() {
        people = peopleStore.load()
        tipsSeen = tutorialStore.load()
    }

    /// Signed in on a second device: it shows the account's name and cat (spec §10.5). Not a
    /// local edit, so it isn't stamped as one.
    func adoptAccountProfile(name: String, cat: Int) {
        guard let owner = people.owner, owner.name != name || owner.cat != cat else { return }
        peopleStore.setOwner(name: name, cat: cat)
        people = peopleStore.load()
        room?.syncNames()
    }

    /// The account's household people from its other devices (they come and go with the account).
    func setImported(_ imported: [Person], previous: Set<String>) {
        let keep = Set(imported.map(\.id))
        for id in previous.subtracting(keep) { peopleStore.remove(id: id) }
        for person in imported { peopleStore.upsertOther(person) }
        people = peopleStore.load()
    }

    func removeImported(_ ids: Set<String>) {
        for id in ids { peopleStore.remove(id: id) }
        people = peopleStore.load()
    }

    /// Settings, sound and haptics, changed on the gear sheet.
    func settingsChanged() {
        account.noteLocalChanges()
    }

    /// This device's synced values for one section (spec §13.1, "what syncs").
    func syncedValues(_ section: SyncSectionName, accountPersonId: String?) -> [String: JSONValue] {
        switch section {
        case .settings:
            var values: [String: JSONValue] = ["soundOn": .bool(settings.soundOn), "hapticsOn": .bool(settings.hapticsOn)]
            if let reminder = settings.turnReminderChoice { values["turnReminder"] = .bool(reminder) }
            return values
        case .archive:
            return tableArchive.all().mapValues { .number($0) }
        case .tutorial:
            guard let id = accountPersonId else { return [:] }
            return Dictionary(uniqueKeysWithValues: (tipsSeen[id] ?? []).map { ($0.rawValue, JSONValue.bool(true)) })
        }
    }

    /// Takes in values another device wrote later than this one.
    func applySynced(_ section: SyncSectionName, _ entries: SyncSection, accountPersonId: String?) {
        switch section {
        case .settings:
            for (key, entry) in entries {
                guard let on = entry.v.boolValue else { continue }
                switch key {
                case "soundOn": settings.soundOn = on
                case "hapticsOn": settings.hapticsOn = on
                case "turnReminder": settings.turnReminderChoice = on
                default: break
                }
            }
        case .archive:
            for (code, entry) in entries where RoomCode.isValid(code) {
                if let updatedAt = entry.v.numberValue {
                    tableArchive.archive(code: code, updatedAt: updatedAt)
                } else {
                    tableArchive.restore(code: code)
                }
            }
            archived = tableArchive.all()
        case .tutorial:
            guard let id = accountPersonId else { return }
            var all = tutorialStore.load()
            for (key, entry) in entries {
                guard let tip = CoachTip(rawValue: key) else { continue }
                if entry.v.boolValue == true { all[id, default: []].insert(tip) } else { all[id]?.remove(tip) }
            }
            tutorialStore.replace(all)
            tipsSeen = all
        }
    }

    // MARK: Coaching tips (first-game tutorial)

    func markTipsSeen(_ tips: Set<CoachTip>, person: String) {
        guard !tips.isSubset(of: tipsSeen[person] ?? []) else { return }
        tipsSeen = tutorialStore.markSeen(tips, person: person)
        account.noteLocalChanges()
    }

    /// Everyone on this phone gets the tips again, from the next thing that fits.
    func replayTips() {
        tutorialStore.reset()
        tipsSeen = [:]
        tipsReplays += 1
        account.noteLocalChanges()
    }

    // MARK: Push priming (spec §10)

    /// The priming screen's paw: the system prompt. A "no" there counts as a decline.
    func acceptPush() async {
        settings.pushPrimed = true
        guard let push else { return }
        if await push.authorizationStatus() == .denied {
            // The system won't ask twice; its settings page is the only way back.
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        if await !push.requestAuthorization() { settings.pushDeclinedOnce = true }
    }

    /// The priming screen's "not now": Home's bell offers it once more.
    func declinePush() {
        settings.pushPrimed = true
        settings.pushDeclinedOnce = true
    }

    func goHome() {
        guard people.owner != nil else { return }
        closeRoom()
        cache = tableCache.all()
        route = .home
    }
}
