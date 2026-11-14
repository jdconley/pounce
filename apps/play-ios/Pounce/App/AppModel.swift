import Foundation
import Observation
import PounceKit
import StoreKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    var route: Route {
        didSet { if case .home = route { funnel.reach(.homeSeen) } }
    }
    var people: LocalPeople
    /// The server's list of this device's tables (Home); at launch, the list saved last time.
    var tables: [TableEntry] = []
    /// There is a list to draw Home from: one was saved on this phone, or the server answered
    /// (or failed to) this launch. Until then Home doesn't guess (`HomeLead.pick(_:known:hadTables:)`).
    private(set) var tablesKnown = false
    /// Locally cached table summaries by room code, so Home can draw before sockets connect.
    var cache: [String: CachedTable]
    /// Tables archived off Home on this phone: room code to the server's `updatedAt` then.
    private(set) var archived: [String: Double]
    /// When this phone last sent each table's invite (epoch ms): a table you sit at alone is on
    /// Home only for a day after (`HomeTables.isWaitingAlone`).
    private(set) var invited: [String: Double]
    /// Set when creating a room failed; cleared by the next attempt.
    var newGameError: APIError?
    private(set) var isCreatingRoom = false
    /// A first table gets a House Cat (first-run funnel). Off in staged runs (UI tests,
    /// screenshots), like the tips, unless `-house-cat` turns it on.
    @ObservationIgnored private var firstTableCat = true
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
    @ObservationIgnored let tableList: TableList
    @ObservationIgnored let tableInvites: TableInvites
    @ObservationIgnored let tutorialStore: TutorialStore
    /// What the App Store rating ask remembers (`RatingPrompt`): the first launch, finished games,
    /// the last ask.
    @ObservationIgnored let ratingStore: RatingStore
    /// Update awareness (app updates design): what is current, Home's card, tables behind an
    /// update, and the screen for a version the server no longer supports.
    let updates: UpdateModel
    /// The first-run funnel's steps only the app sees, for our own server (`Funnel`).
    @ObservationIgnored let funnel: Funnel
    /// The coaching tips each person on this phone has seen (first-game tutorial).
    private(set) var tipsSeen: TipsSeen
    /// Coaching tips show on the table. Off for the UI tests and demos, which never expect a
    /// bubble over the table, unless `-tips` asks for them, and under `-no-tips` (DEBUG only).
    var tipsEnabled = true
    /// Bumped by "Show the tips again": tables turn tips back on for everyone.
    private(set) var tipsReplays = 0
    /// Tips about the app's own controls (`Tips.swift`), one at a time over the top screen.
    let tips: TipCenter
    /// The owner's shared streaks (spec §7–§10), and what each table socket says about them.
    let streaks: StreakStore
    /// The owner's trophy room (trophy room design §3).
    let trophies: TrophyStore
    /// The invite sheet is up (trophy room design §4), over Home or the trophy room.
    var inviteShown = false
    /// The last invite link, shown again for an hour (`InviteLink`).
    @ObservationIgnored private var inviteLink: InviteLink?
    /// A kitten's last invite table, shown again for an hour (`InviteCode`).
    @ObservationIgnored private var inviteCode: InviteCode?
    /// The condo stage this phone last showed per pair, so a new stage drops in once (§9.5).
    private(set) var condoSeen: [String: Int]
    @ObservationIgnored private let condoSeenURL: URL
    /// Push and local notifications; attached by the app delegate at launch.
    @ObservationIgnored weak var push: PushCoordinator?
    /// Pounces sent from here and answers owed to the server (spec §12.4).
    let pounces: PounceStore
    /// The notification settings chosen on this phone or another of the account's (§12.6).
    let notify: NotifySettingsStore
    /// A pounce to answer by picking (a "you pick" push, or a Messages link): the pick sheet.
    var pick: PickRequest?
    /// A Messages link that no longer works: the worded "This invite has expired" card.
    var expiredInviteShown = false
    /// A Messages link that couldn't be looked up (no connection): its token, for the card's Try again.
    var offlineInvite: String?
    /// Whether the pasteboard looks like it holds a link, for "Paste invite" (first-run funnel, part 2).
    let pasteboard = PasteboardWatch()
    /// Bumped when what was pasted isn't an invite: the paste card shakes and says so.
    private(set) var pasteNope = 0
    /// The widgets' snapshot, reloads and push token (spec §11.2).
    @ObservationIgnored let widgets: WidgetBridge
    /// The live table's tokens and ends (spec §11.3).
    @ObservationIgnored private(set) var liveTables: LiveTableBridge!
    /// Parent consent (consent design §2): a kitten's consent and code here, or a signed-in
    /// adult's kittens.
    let kittens: KittenStore
    /// The kitten-push significant change is owed or a parent said no: the bell stays padlocked.
    var kittenPushHeld = false
    /// The Kittens panel opened from a consent notification, on that kitten (consent design D6).
    var kittensPanel: KittensPanelRequest?
    /// Apple's Communication Limits approvals, mirrored up from a kitten's device.
    @ObservationIgnored private(set) var communicationLimits: CommunicationLimitsBridge!

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
        tableList = TableList(directory: dataDirectory, fileName: TableList.fileName(for: config))
        tableInvites = TableInvites(directory: dataDirectory, fileName: TableInvites.fileName(for: config))
        invited = tableInvites.all()
        let loaded = peopleStore.load()
        people = loaded
        cache = tableCache.all()
        // Last launch's list, so Home opens on your tables; the server's answer replaces it.
        if let saved = tableList.load() {
            tables = saved
            tablesKnown = true
        }
        archived = tableArchive.all()
        tutorialStore = TutorialStore(directory: dataDirectory)
        tipsSeen = tutorialStore.load()
        tips = TipCenter(store: tutorialStore, pacing: TipPacingStore(directory: dataDirectory))
        ratingStore = RatingStore(directory: dataDirectory)
        updates = UpdateModel(api: api, directory: dataDirectory)
        funnel = Funnel(sender: api, file: dataDirectory.appendingPathComponent("funnel-\(config.serverKey).json"))
        // The first launch is written down now: the rating ask waits days after it.
        ratingStore.load()
        self.ageStore = ageStore
        self.ageAsker = ageAsker
        let age = ageStore.load()
        ageRecord = age
        hadOwnerBeforeThisVersion = age == nil && loaded.owner != nil
        route = age == nil ? .age(then: nil) : loaded.owner == nil ? .pickCat(then: nil) : .home
        #if DEBUG
        let demoStreaks = Self.debugStreaks(arguments: CommandLine.arguments)
        streaks = StreakStore(service: demoStreaks ?? api)
        let pounceService: any PounceService = (demoStreaks as? DemoStreakService).map { DemoPounceService(streaks: $0) } ?? api
        let trophyOff: any TrophyService = TrophiesOffService()
        let trophyService: any TrophyService =
            (demoStreaks as? DemoStreakService).map { DemoTrophyService(streaks: $0) } ?? (demoStreaks == nil ? api : trophyOff)
        #else
        streaks = StreakStore(service: api)
        let pounceService: any PounceService = api
        let trophyService: any TrophyService = api
        #endif
        trophies = TrophyStore(service: trophyService)
        pounces = PounceStore(service: pounceService, file: dataDirectory.appendingPathComponent("pounce-answers.json"))
        #if DEBUG
        let kittenService: any KittenService = Self.debugKittens(arguments: CommandLine.arguments) ?? api
        #else
        let kittenService: any KittenService = api
        #endif
        kittens = KittenStore(service: kittenService, file: dataDirectory.appendingPathComponent("kitten.json"))
        if age?.band == .kitten { kittens.person = loaded.owner?.id }
        notify = NotifySettingsStore(file: dataDirectory.appendingPathComponent("notify-settings.json"))
        streaks.person = loaded.owner?.id
        trophies.person = loaded.owner?.id
        #if DEBUG
        // Demos and UI tests write demo data for the widgets, which then never fetch (no server).
        let args = CommandLine.arguments
        let offline = args.contains("-uitest-reset") || args.contains("-demo-streaks") || DemoMode.from(arguments: args) != nil
        widgets = WidgetBridge(server: offline ? nil : config.baseURL)
        #else
        widgets = WidgetBridge(server: config.baseURL)
        #endif
        condoSeenURL = dataDirectory.appendingPathComponent("streak-seen.json")
        condoSeen = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: condoSeenURL))) ?? [:]
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
        KittenPushChange.prepare(self)
        communicationLimits = CommunicationLimitsBridge(model: self)
        communicationLimits.start()
        // At launch, background ones too: a push-started live table hands its token over then.
        liveTables = LiveTableBridge(
            api: api, band: { [weak self] in self?.ageBand }, liveOn: { [weak self] in self?.notifySettings.liveTable ?? true })
        liveTables.start()
    }

    /// The app's one model: SwiftUI shows it and the app delegate attaches it at launch, so a
    /// notification button that launched the app in the background can use it before any scene.
    static let shared = makeDefault()

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
            // `-uitest-data <name>`: the same data directory on each launch, for tests that relaunch.
            let name = arguments.firstIndex(of: "-uitest-data").flatMap { arguments[safe: $0 + 1] } ?? UUID().uuidString
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pounce-uitest-\(name)", isDirectory: true)
            model = AppModel(
                config: config, credentials: MemoryCredentialStore(), dataDirectory: dir,
                ageStore: debugAgeStore(arguments: arguments), ageAsker: asker, personKeys: MemoryPersonKeyStore())
        } else {
            model = real(config: config, ageAsker: asker)
        }
        // `-seed-people`: a fresh run starts with an owner and two others (screenshots).
        if arguments.contains("-uitest-reset"), arguments.contains("-seed-people"), model.people.owner == nil {
            model.peopleStore.setOwner(name: DemoFixtures.castName(0, "JD"), cat: 4)
            model.peopleStore.add(name: DemoFixtures.castName(1, "Ella"), cat: 2)
            model.peopleStore.add(name: DemoFixtures.castName(2, "Sam"), cat: 6)
            model.people = model.peopleStore.load()
            model.streaks.person = model.people.owner?.id
            model.trophies.person = model.people.owner?.id
            // Screens for screenshots: no push priming over them.
            model.settings.pushPrimed = true
            if model.ageRecord != nil { model.route = .home }
        }
        // Home's one-time sign-in card stays out of the way of every other test, unless
        // `-signin-prompt` asks for it.
        if arguments.contains("-uitest-reset") || DemoMode.from(arguments: arguments) != nil,
           !arguments.contains("-signin-prompt") {
            model.settings.signInPromptSeen = true
        }
        // `-show-us`: open on the Us screen (UI tests, screenshots).
        if arguments.contains("-show-us"), model.people.owner != nil, model.ageRecord != nil { model.route = .us }
        // `-show-trophies` / `-show-invite`: the trophy room, or the invite sheet over Home (UI tests, screenshots).
        if arguments.contains("-show-trophies"), model.people.owner != nil, model.ageRecord != nil { model.route = .trophies }
        if arguments.contains("-show-invite"), model.people.owner != nil, model.ageRecord != nil { model.inviteShown = true }
        // `-show-merge`: the two-cats question over the gear sheet (screenshots).
        if arguments.contains("-show-merge") {
            model.account.merge = .init(mine: 4, theirs: 2, theirName: StubAccountService.other.name, asking: true)
        }
        if let demo = DemoMode.from(arguments: arguments) { model.openDemo(demo) }
        // `-demo-update table`: a table that answers "this game needs a newer app" (`UpdateDemo`).
        if UpdateDemo.from(arguments: arguments) == .table, model.people.owner != nil, model.ageRecord != nil {
            model.openDemoSocket(code: UpdateDemo.code) { UpdateDemo.refusingSocket() }
        }
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
        // `-open-kittens <k_…>`: a consent notification's tap at launch (KittenTests).
        if let i = arguments.firstIndex(of: "-open-kittens"), let kid = arguments[safe: i + 1] { model.showKittens(focus: kid) }
        // `-show-link`: a Messages pounce link opens at launch (the demo's, from Leo).
        if arguments.contains("-show-link") { model.handle(.pounce(token: DemoPounceService.linkToken)) }
        // `-open-widget-link <pounce-widget://…>`: a widget tap at launch (WidgetLinkTests).
        if let i = arguments.firstIndex(of: "-open-widget-link"), let text = arguments[safe: i + 1],
           let url = URL(string: text), let link = WidgetLink.parse(url) {
            model.handle(link)
        }
        model.startTips(arguments: arguments, env: env)
        model.startPasteboard(arguments: arguments, env: env)
        return model
        #else
        let model = real(config: config)
        model.startTips(arguments: arguments, env: env)
        model.startPasteboard(arguments: arguments, env: env)
        return model
        #endif
    }

    /// "Paste invite" is off wherever a run is staged (UI tests, demos, screenshots: a link left
    /// in the simulator's pasteboard must not cover their Home), unless `-paste-invite` asks for it.
    private func startPasteboard(arguments: [String], env: [String: String]) {
        pasteboard.enabled = !RatingPrompt.isStaged(arguments: arguments, env: env) || arguments.contains("-paste-invite")
        pasteboard.refresh()
    }

    /// UI tips are off wherever a run is staged (demos, UI tests, screenshots and videos: the
    /// same runs the rating ask stays out of), unless `-ui-tips` asks for them; `-no-tips` turns
    /// them off on a phone's own data too.
    private func startTips(arguments: [String], env: [String: String]) {
        tips.enabled = (!RatingPrompt.isStaged(arguments: arguments, env: env) || arguments.contains("-ui-tips"))
            && !arguments.contains("-no-tips")
        firstTableCat = !RatingPrompt.isStaged(arguments: arguments, env: env) || arguments.contains("-house-cat")
        tips.who = { [weak self] in
            guard let self else { return (nil, nil, false) }
            return (people.owner?.id, ageBand, !people.others.isEmpty)
        }
        tips.blocked = { [weak self] in
            guard let self else { return true }
            return pick != nil || inviteShown || expiredInviteShown || offlineInvite != nil || offersPasteInvite
                || updates.required != nil || kittensPanel != nil
        }
        tips.onChange = { [weak self] in self?.account.noteLocalChanges() }
        // Home's old one-time archive hint: whoever closed it has learned the tip.
        if settings.archiveHintSeen, let owner = people.owner?.id { tips.learn([.homeArchive], person: owner) }
        #if DEBUG
        // `-tips-seen ui.home.shelf,ui.home.join`: the owner has had these (screenshots of later tips).
        if let i = arguments.firstIndex(of: "-tips-seen"), let list = arguments[safe: i + 1], let owner = people.owner?.id {
            tips.learn(Set(list.split(separator: ",").compactMap { UITip(rawValue: String($0)) }), person: owner)
        }
        #endif
        tips.launched()
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
    /// `-demo-streaks`: the streak routes from `DemoFixtures.streaks()`, no server; `-demo-streaks off`:
    /// a server with streaks off (every list is a 404); `-demo-streaks empty`: the trophy room on and
    /// nobody connected yet (Home's big plus).
    private static func debugStreaks(arguments: [String]) -> (any StreakService)? {
        guard let i = arguments.firstIndex(of: "-demo-streaks") else { return nil }
        switch arguments[safe: i + 1] {
        case "off": return StreaksOffService()
        case "empty": return DemoStreakService(DemoFixtures.emptyStreaks())
        default: return DemoStreakService()
        }
    }

    /// `-demo-kitten <locked|held|pending|on>` and `-demo-kittens`: the consent routes in memory.
    private static func debugKittens(arguments: [String]) -> (any KittenService)? {
        if let i = arguments.firstIndex(of: "-demo-kitten") {
            return DemoKittenService(scenario: arguments[safe: i + 1].flatMap(DemoKittenService.Scenario.init) ?? .locked)
        }
        return arguments.contains("-demo-kittens") ? DemoKittenService(scenario: .locked) : nil
    }

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
    /// A room on a canned socket, opened as a link would open it (`-demo-update table`).
    func openDemoSocket(code: String, make: @escaping @Sendable () -> any RoomSocketing) {
        closeRoom()
        let session = RoomSession(code: code, intent: .join, socket: SuspendableSocket(make: make))
        session.owner = { [weak self] in self?.people.owner }
        session.people = { [weak self] in self?.everyone ?? [] }
        room = session
        session.start()
        route = .room(code: code, intent: .join)
    }

    /// `-demo <screen>`: the room screen fed by one fixture snapshot, no server, nothing cached.
    func openDemo(_ demo: DemoMode, code: String? = nil) {
        closeRoom()
        var room = demo.room
        if let code { room.code = code }
        let socket = SuspendableSocket { [room] in code == nil ? demo.makeSocket() : DemoSocket(room: room) }
        let session = RoomSession(code: room.code, intent: .rejoin, socket: socket)
        session.owner = { [weak self] in self?.people.owner }
        session.people = { [weak self] in self?.everyone ?? [] }
        session.onStreak = { [weak self] pair, person, view in self?.streakArrived(pair: pair, person: person, view: view) }
        self.room = session
        session.start()
        route = .room(code: room.code, intent: .rejoin)
        // `-demo-stamp`: a streak view keeps today for the top pair a moment in (the stamp, screenshots).
        // `-demo-stamp new`: a brand-new pair's first kept day instead (its badge appears with it).
        let args = CommandLine.arguments
        let newPair = args.firstIndex(of: "-demo-stamp").flatMap { args[safe: $0 + 1] } == "new"
        if args.contains("-demo-stamp") {
            Task { [weak self, weak session] in
                await self?.streaks.refresh()
                try? await Task.sleep(for: Pace.duration(.seconds(2.5)))
                // For the demo seat's person (the owner doesn't sit at a demo table).
                guard let self, let session, var view = self.streaks.top,
                      let seat = session.model?.mySeats.first, let person = session.model?.room.seats[seat].person?.id
                else { return }
                view.count = newPair ? 1 : view.count + 1
                if newPair { view.pair = "pr_demoNewAAAAAAAAAAAAAAAA" }
                view.me = true
                view.them = true
                view.kept = true
                view.todayToy = "toy-golden-mouse"
                view.myMove = [session.code]
                session.store.handle(.message(.streak(pair: view.pair, person: person, view: view)))
            }
        }
        // `-demo-streaks` at a demo table: the demo seat's person has the demo pairs (the owner
        // doesn't sit there), so the badge and the look tray's unlocks show as for a real seat.
        // (Not with `-demo-stamp new`: there the badge appears with its first message.)
        if args.contains("-demo-streaks"), !newPair,
           let seat = room.seats.firstIndex(where: \.yours),
           let person = room.seats[seat].person?.id {
            Task { [weak self] in
                guard let self else { return }
                await self.streaks.refresh()
                for view in self.streaks.pairs { self.streaks.apply(pair: view.pair, person: person, view: view) }
            }
        }
        // `-demo-home-after <seconds>`: leave the table mid-animation (teardown check).
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
        if ageRecord != nil { funnel.allow() }
        #if DEBUG
        // `-request-push`: the system prompt at launch (the notification screenshots).
        if CommandLine.arguments.contains("-request-push") { _ = await push?.requestAuthorization() }
        #endif
        // Hears "this version is too old" from the first call on, and asks what is current.
        Task { await updates.start() }
        _ = try? await api.credential()
        #if DEBUG
        await account.applyDebugPreset()
        #endif
        if ageRecord != nil { await accountsAfterAge() }
        if people.owner != nil { await refreshTables() }
        await refreshStreaks()
        await refreshKitten()
        await kittens.drainRevokes()
        await pounces.retryPending()
        await recheckAge()
        await uploadWidgetToken()
        await liveTables.retry()
    }

    /// Once the age is known: the significant-change check, then the profile and sync.
    private func accountsAfterAge() async {
        await SignificantChangeGate.check(self)
        await KittenPushChange.check(self)
        await account.uploadProfile()
        await account.sync()
        await uploadGuestNotify()
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
        funnel.ageChecked()
        applyAgeLimits()
        push?.registerIfAllowed()
        syncWidgets()
        Task { await accountsAfterAge() }
        Task { await liveTables.retry() }
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
        push?.registerIfAllowed()
        syncWidgets()
        await uploadWidgetToken()
        await liveTables.retry()
    }

    /// The age screen's "Check with Apple" (launch review): a band from the keypad, or a limited
    /// one, put right by a fresh Declared Age Range answer. A decline or no answer changes nothing,
    /// and the keypad never comes back. True when the band changed.
    @discardableResult
    func correctAge() async -> Bool {
        guard let record = ageRecord, AgeCorrection.offered(record) else { return false }
        let answer: AgeBand? = if case .band(let band) = await ageAsker.ask() { band } else { nil }
        let fixed = AgeCorrection.corrected(record, answer: answer, now: .now)
        guard fixed != record else { return false }
        ageStore.save(fixed)
        ageRecord = fixed
        limitsAnswer = nil
        applyAgeLimits()
        push?.registerIfAllowed()
        syncWidgets()
        Task { await accountsAfterAge() }
        await uploadWidgetToken()
        await liveTables.retry()
        return fixed.band != record.band
    }

    /// A kitten keeps no typed name (a name plus an identifier is personal information): an owner
    /// from before the age check gets a generated one.
    private func applyAgeLimits() {
        // A kitten who turned 13 loses the kitten-only panel, so its local 17:00 reminder goes too.
        if ageBand != .kitten, settings.kittenDaily {
            settings.kittenDaily = false
            push?.setKittenDaily(on: false, name: "")
        }
        guard !limits.typedNames, let owner = people.owner, AgeLimits.needsGeneratedName(owner.name) else { return }
        updateOwner(name: CatEditorView.randomName(), cat: owner.cat)
    }

    func reloadLocal() {
        people = peopleStore.load()
        cache = tableCache.all()
        streaks.person = people.owner?.id
    }

    // MARK: Streaks (spec §7–§10)

    /// The owner's streaks again (Home, foreground, back from a table). Quiet when offline.
    func refreshStreaks() async {
        streaks.person = people.owner?.id
        await streaks.refresh()
        syncWidgets()
    }

    // MARK: The trophy room and adding people (trophy room design §1, §3, §4)

    /// The trophy room, from your own streak's chip or the Us screen's trophy.
    func showTrophies() {
        guard people.owner != nil else { return }
        closeRoom()
        route = .trophies
    }

    func refreshTrophies() async {
        trophies.person = people.owner?.id
        await trophies.refresh()
    }

    /// The plus: the invite sheet.
    func showInvite() {
        guard people.owner != nil else { return }
        inviteShown = true
    }

    /// The invite sheet's Messages link (PR 5's link pounce, target "new"): the kept one when it's
    /// under an hour old, nobody new connected since and the server says nobody answered it yet,
    /// else a new one; while the bell rests, a kept one nobody used. Nil on a kitten's device, and
    /// when there's none to show.
    func inviteURL() async -> URL? {
        guard InviteLink.mode(limits) == .link else { return nil }
        let pairs = streaks.pairs.map(\.pair)
        if let kept = inviteLink, kept.reusable(now: .now, pairs: pairs), await unused(kept) { return kept.url }
        if let url = await sharePounce(target: .new) {
            inviteLink = InviteLink(url: url, at: .now, pairs: Set(pairs))
            return url
        }
        if let kept = inviteLink, kept.usableWhileResting(now: .now, pairs: pairs), await unused(kept) { return kept.url }
        return nil
    }

    /// Any answer to a link (Play, or In a bit / Not now, which make it that person's) takes it
    /// off the sender's hands: the server's preview says so.
    private func unused(_ link: InviteLink) async -> Bool {
        guard let token = link.token else { return false }
        if case .found = await pounces.link(token: token, person: people.owner?.id) { return true }
        return false
    }

    /// A kitten's invite (§14.1): a new table whose code and QR are for in-person play only, the
    /// same one again within the hour.
    func inviteTable() async -> String? {
        if let kept = inviteCode, kept.reusable(now: .now) { return kept.code }
        #if DEBUG
        if CommandLine.arguments.contains("-demo-streaks") { return "TB4XN" }
        #endif
        guard let code = try? await api.createRoom() else { return nil }
        inviteCode = InviteCode(code: code, at: .now)
        return code
    }

    /// The kitten's invite table was opened: the next plus makes a new one.
    func inviteTableUsed() {
        inviteCode = nil
    }

    /// A table socket's `{t:"streak"}`: the store takes it (its stamp plays at the table), and the
    /// widgets see the owner's new paws.
    @discardableResult
    func streakArrived(pair: String, person: String, view: StreakView) -> StreakStamp? {
        let stamp = streaks.apply(pair: pair, person: person, view: view)
        if person == people.owner?.id { widgets.fold(view) }
        return stamp
    }

    // MARK: Widgets (spec §11)

    /// The widgets' snapshot from what this phone knows now; they reload only when it changed
    /// (and always when `reload`, going to the background).
    func syncWidgets(reload: Bool = false) {
        var names: [String: String] = [:]
        for (code, table) in cache { if let name = table.name { names[code] = name } }
        for entry in tables { if let name = entry.name { names[entry.code] = name } }
        #if DEBUG
        // `-demo-streaks`: the demo pairs' tables have names, as on a server.
        if CommandLine.arguments.contains("-demo-streaks") {
            names.merge(DemoFixtures.widgetSnapshot().tableNames) { mine, _ in mine }
        }
        #endif
        // Until the server answered for this person the list is unknown, not empty (an offline
        // launch); once it has, it is news only as of that answer.
        let pairs: [StreakView]? = streaks.fetchedAt == nil ? nil : (streaks.enabled == false ? [] : streaks.pairs)
        widgets.update(
            owner: people.owner, band: ageBand, pairs: pairs, pairsAt: streaks.fetchedAt, names: names,
            quietStart: notifySettings.quietStart, reload: reload)
    }

    /// The widgets' push token, from a teen's or an adult's device only.
    func uploadWidgetToken() async {
        await widgets.uploadToken(api: api, band: ageBand)
    }

    /// A widget was tapped (spec §11.1). Before the age and a cat exist there's nowhere to go.
    func handle(_ link: WidgetLink) {
        guard ageRecord != nil, people.owner != nil else { return }
        switch link {
        case .table(let code):
            pick = nil
            open(code: code, intent: .rejoin)
        case .us(let pair):
            pick = nil
            showUs(pair: pair)
        case .app:
            break
        }
    }

    /// A gift Home asked the Us screen to open (§9.5: the gift waits on Home).
    var pendingGift: String?

    /// The pair the Us screen should open on (Home's waiting pounce).
    var pendingPair: String?

    func showUs(openingGift gift: String? = nil, pair: String? = nil) {
        guard people.owner != nil else { return }
        inviteShown = false
        closeRoom()
        pendingGift = gift
        pendingPair = pair
        route = .us
    }

    func noteCondoSeen(pair: String, stage: Int) {
        guard condoSeen[pair] != stage else { return }
        condoSeen[pair] = stage
        if let data = try? JSONEncoder().encode(condoSeen) {
            try? FileManager.default.createDirectory(at: condoSeenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: condoSeenURL, options: .atomic)
        }
    }

    /// Saves the owner, then continues to the link that interrupted onboarding, or Home.
    func finishPickCat(name: String, cat: Int) {
        let owner = peopleStore.setOwner(name: name, cat: cat)
        funnel.reach(.named)
        people = peopleStore.load()
        streaks.person = owner.id
        account.noteChanged(owner.id)
        syncWidgets()
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
        HomeTables.merge(entries: tables, cache: cache, archived: archived, invited: invited, now: .now)
    }

    /// Who's at a table besides you, for its card: your connections and the people sharing this
    /// phone first, bots under the bot's name; a kitten's phone names only its own people (§14.1).
    func tablePeople(_ item: HomeTableItem) -> TablePeople.Line {
        TablePeople.line(
            seats: item.seats, code: item.id, owner: people.owner?.id, household: people.others, pairs: streaks.pairs,
            band: ageBand, bot: SeatInfo.botName, botCat: SeatInfo.botCat)
    }

    /// Home's Archived sheet.
    var archivedItems: [HomeTableItem] {
        HomeTables.archivedItems(entries: tables, cache: cache, archived: archived, invited: invited, now: .now)
    }

    /// Hides a table from Home. The seat stays: links, pushes and Join still open it, and it
    /// comes back by itself when it is your turn there again.
    func archive(code: String) {
        let updatedAt = tables.first { $0.code == code }?.updatedAt ?? Date.now.timeIntervalSince1970 * 1000
        tableArchive.archive(code: code, updatedAt: updatedAt)
        archived = tableArchive.all()
        account.noteLocalChanges()
    }

    /// A table's invite went out (the share sheet sent it, or its QR code showed): it can wait on
    /// Home for people to accept.
    func noteInvited(code: String) {
        funnel.reach(.inviteSent)
        tableInvites.note(code: code)
        invited = tableInvites.all()
    }

    func restore(code: String) {
        tableArchive.restore(code: code)
        archived = tableArchive.all()
        account?.noteLocalChanges()
    }

    func refreshTables() async {
        cache = tableCache.all()
        #if DEBUG
        // `-tables-offline`: the server never answers, so Home stays as it is at launch.
        if CommandLine.arguments.contains("-tables-offline") { return }
        #endif
        do {
            let reply = try await api.listTablesAndLocked()
            let listed = reply.tables
            tables = listed
            tablesKnown = true
            tableList.save(listed)
            // The tables this version was left out of, for Home's padlocked rows.
            updates.serverLocked = reply.locked
            // The icon's badge: tables where it's your move (spec §12.5), on every device.
            push?.setBadge(PushPolicy.badgeCount(listed))
            // A snoozed "your move" for a table that no longer waits on you goes.
            push?.cancelSnoozes(codes: listed.filter { !$0.yourTurn || $0.status == "over" }.map(\.code))
            // The server answered: a push token that failed to upload goes now.
            push?.retryUpload()
            // A cached room the server no longer lists is gone for good.
            let live = Set(listed.map(\.code))
            for code in cache.keys where !live.contains(code) { tableCache.remove(code: code) }
            cache = tableCache.all()
            // Forget archived rooms that closed, and ones a new turn brought back.
            tableArchive.replace(with: HomeTables.keptArchive(entries: listed, archived: tableArchive.all()))
            archived = tableArchive.all()
            tableInvites.keep(live)
            invited = tableInvites.all()
            // Table names for the medium widget.
            syncWidgets()
        } catch {
            // Offline or server down: keep the last list; Home still draws from the cache.
            tablesKnown = true
        }
    }

    /// `practice`: a game against the House Cat that starts at once, with no stop in the lobby.
    func newGame(_ game: GameCatalog.Entry = GameCatalog.dealt, practice: Bool = false) async {
        // A game still on its way has a card on the shelf but no table to start.
        guard game.isAvailable, !isCreatingRoom else { return }
        isCreatingRoom = true
        newGameError = nil
        defer { isCreatingRoom = false }
        do {
            // Before `open`, which caches the new table.
            let first = isFirstTable
            let code = try await api.createRoom(game: game.id)
            open(code: code, intent: .create)
            if practice {
                room?.practicePending = true
            } else if first && firstTableCat {
                room?.firstTablePending = true
            }
        } catch let error as APIError {
            newGameError = error
        } catch {
            newGameError = .transport(String(describing: error))
        }
    }

    /// No table on this phone, listed, cached or archived: whoever starts one now is a
    /// first-time host, and their lobby opens with a House Cat so Start is lit.
    var isFirstTable: Bool { tables.isEmpty && cache.isEmpty && archived.isEmpty }

    func open(code: String, intent: RoomIntent) {
        // A push tap or a link while the invite sheet is up: the table, not the sheet over it.
        inviteShown = false
        push?.cancelSnoozes(codes: [code])
        // Back at this table in the app: its live table goes now (spec §11.3).
        Task { await liveTables.sweep(entering: code) }
        funnel.tableOpened()
        let session = ensureRoom(code: code, intent: intent)
        // A move link for the room already open: its first snapshot is long gone, so claim now.
        if case .move(let moveCode) = intent, session.intent != intent { session.claimMove(moveCode) }
        route = .room(code: code, intent: intent)
    }

    /// Play again's table (§10.4): open it as one this phone sits at.
    func openRematch(code: String) {
        #if DEBUG
        // A demo's Play again deals a demo table under the new code.
        if DemoMode.from() != nil {
            openDemo(.table, code: code)
            return
        }
        #endif
        open(code: code, intent: .rejoin)
    }

    /// The table on screen, if any.
    var onScreenCode: String? {
        if case .room(let code, _) = route { return code }
        return nil
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
        tips.scenePhaseChanged(phase)
        switch phase {
        case .active:
            room?.foreground()
            funnel.flush()
            Task { await updates.refresh() }
            Task {
                await account.uploadProfile()
                await account.sync()
                await uploadGuestNotify()
                await refreshStreaks()
                await refreshKitten()
                await kittens.drainRevokes()
                await pounces.retryPending()
                await uploadWidgetToken()
                await liveTables.retry()
            }
            // Back at the table on screen: its live table goes; stale and older ones too (§11.3).
            Task { await liveTables.sweep(entering: onScreenCode) }
            // Every reminder, not just this launch's: one may predate a relaunch.
            push?.cancelAllTurnReminders()
            push?.retryUpload()
        case .background:
            // One last reload on the way out (spec §11.2), with whatever changed meanwhile.
            syncWidgets(reload: true)
            #if DEBUG
            // `-demo-communication`: once the app is away, a pounce from Mia lands, drawn exactly as
            // PounceNotify draws a push (the simulator's `simctl push` skips service extensions).
            if CommandLine.arguments.contains("-demo-communication") { push?.postDemoPounce(after: 2) }
            #endif
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
        session.onStreak = { [weak self] pair, person, view in self?.streakArrived(pair: pair, person: person, view: view) }
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
        // Closed or never there: nothing left to update for.
        updates.forget(code: session.code)
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
        if tablesKnown { tableList.save(tables) }
    }

    /// The game at the table a share or move link is for, for its share text: the open room's
    /// game, else Home's list's. A pounce link deals a new Cat Tower table (play-api `dealFor`).
    func gameID(for url: URL) -> String? {
        let code: String
        switch DeepLink.parse(url, allowDevScheme: true) {
        case .join(let c), .move(let c, _): code = c
        case .pounce, nil: return GameCatalog.dealt.id
        }
        if let room, room.code == code, let id = room.store.room?.gameId { return id }
        return homeItems.first { $0.id == code }?.game
    }

    /// A share or move link arrived. Without a local owner, onboarding comes first and the link
    /// is remembered. A join link for a table already on this device rejoins it.
    func handle(_ link: DeepLink) {
        funnel.opened(link)
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
        case .pounce(let token):
            // Onboarding is done: the pick sheet (or its card) opens over Home, not the name screen.
            if case .pickCat = route { route = .home }
            Task { await openLink(token) }
        }
    }

    // MARK: Pounce (spec §12.4)

    /// A Messages pounce: who sent it and what it asks, then the pick sheet. A link the server
    /// doesn't know any more (expired, played on, or someone else's) gets the worded expired
    /// card; one that can't be checked (offline) gets the nope thump and sound, and no sheet.
    private func openLink(_ token: String) async {
        switch await pounces.link(token: token, person: people.owner?.id) {
        case .found(let found):
            showPick(PickRequest(id: found.id, target: found.target, from: found.from, link: token, person: people.owner?.id))
        case .expired:
            Haptics.shared.thump()
            if case .room = route { closeRoom(); route = .home }
            expiredInviteShown = true
        case .unreachable:
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
            offlineInvite = token
        }
    }

    /// The offline card's Try again.
    func retryInvite(_ token: String) {
        offlineInvite = nil
        Task { await openLink(token) }
    }

    // MARK: Paste invite (first-run funnel, part 2)

    /// Home's first visit offers to paste an invite: this phone has no table yet, the pasteboard
    /// looks like it holds a link, and nothing else is on screen.
    var offersPasteInvite: Bool {
        route == .home && people.owner != nil && pasteboard.hasLink && tables.isEmpty && cache.isEmpty
            && pick == nil && !inviteShown && !expiredInviteShown && offlineInvite == nil && updates.required == nil
            && kittensPanel == nil
    }

    /// What the system paste control handed over (a tap, so no "Allow paste?"): an invite opens
    /// its table exactly as the tapped link would; anything else says so.
    func pasteInvite(_ text: String) {
        #if DEBUG
        let dev = true
        #else
        let dev = false
        #endif
        guard let link = DeepLink.pasted(text, allowDevScheme: dev) else {
            pasteNope += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
            return
        }
        pasteboard.settle()
        Haptics.shared.success()
        funnel.pasted()
        handle(link)
    }

    /// The person on this phone a pounce push is for: its title is their name (§12.2).
    func pounceRecipient(title: String?) -> String? {
        PounceRecipient.person(title: title, owner: people.owner, others: people.others)
    }

    func showPick(_ request: PickRequest) {
        guard people.owner != nil else { return }
        if case .room = route { closeRoom(); route = .home }
        pick = request
    }

    /// The pair a pounce's sender is, by their name and cat (a pick's shared tables come from it).
    func pairOf(_ face: PushFace?) -> StreakView? {
        guard let face else { return nil }
        return streaks.pairs.first { $0.partner.name == face.name && $0.partner.cat == face.cat }
    }

    /// Sends a pounce to a pair's partner; the bell's state comes back with the streaks.
    func sendPounce(pair: String, target: PounceTarget) async -> PounceStore.SendResult {
        let result = await pounces.send(pair: pair, target: target, person: people.owner?.id)
        // A pounce to a table invites them to it.
        if case .sent = result, case .table(let code) = target { noteInvited(code: code) }
        await refreshStreaks()
        return result
    }

    // MARK: Parent consent (consent design §2)

    /// A kitten's device: its consent from the server, push registration to match, and Apple's
    /// approvals mirrored. Quiet when offline.
    func refreshKitten() async {
        guard ageBand == .kitten, let owner = people.owner else { return }
        kittens.person = owner.id
        await kittens.refreshStatus()
        push?.registerIfAllowed()
        await communicationLimits.sync()
    }

    /// Screen Time's Communication Limits, asked once a launch and only when the age came from
    /// Declared Age Range (a person who declined it never sees its sheet again from here).
    @ObservationIgnored private var limitsAnswer: Bool?

    func communicationLimitsOn() async -> Bool {
        if let limitsAnswer { return limitsAnswer }
        let on = ageRecord?.source == .declared ? await ageAsker.communicationLimits() : false
        limitsAnswer = on
        return on
    }

    /// A linked parent consented for this kitten's device (the server's word, or the last one seen).
    var kittenConsented: Bool { ageBand == .kitten && kittens.consented }

    /// Signed in as an adult: the gear sheet offers the Kittens panel.
    var isParent: Bool { ageBand == .adult && account.isSignedIn }

    /// A consent notification's tap: the Kittens panel on that kitten, over whatever is up. Only a
    /// consenting parent's devices get that notification; the panel's list comes from the server,
    /// which answers only a signed-in adult (the account may still be loading at launch).
    func showKittens(focus: String) {
        if case .room = route { closeRoom(); route = .home }
        kittensPanel = KittensPanelRequest(focus: focus)
    }

    /// A person this kitten can't pounce yet (plan decision 38).
    func pounceLocked(_ pair: String) -> Bool { ageBand == .kitten && kittens.locks(pair: pair) }

    /// The code for a grown-up, with this copy's app transaction id for `RESCIND_CONSENT`.
    func requestKittenCode() async {
        guard ageBand == .kitten, !kittenPushHeld else { return }
        await kittens.requestCode(appTransactionId: await Self.appTransactionId())
    }

    /// `AppTransaction.shared`'s `appTransactionID`, when StoreKit has one (not in Debug runs).
    private static func appTransactionId() async -> String? {
        #if DEBUG
        return nil
        #else
        guard case .verified(let tx)? = try? await AppTransaction.shared else { return nil }
        return tx.appTransactionID
        #endif
    }

    /// A Messages pounce's link, never from a kitten's device (§14.1).
    func sharePounce(target: PounceTarget) async -> URL? {
        guard limits.sharesLinks else { return nil }
        return await pounces.share(target: target, person: people.owner?.id)
    }

    /// Answers a pounce (a notification button, the waiting card, or the pick sheet). Play with
    /// `opens` goes to the table the answer names.
    @discardableResult
    func answerPounce(
        id: String, answer: PounceAnswer, choice: String?, link: String?, person: String? = nil, opens: Bool = true
    ) async -> PounceStore.AnswerResult {
        let who = person ?? people.owner?.id
        let result = await pounces.answer(PendingAnswer(id: id, answer: answer, choice: choice, link: link, person: who))
        if pick?.id == id { pick = nil }
        if opens, answer == .play, case .done(let code?) = result {
            #if DEBUG
            if DemoMode.from() != nil || CommandLine.arguments.contains("-demo-streaks") {
                openDemo(.table, code: code)
                return result
            }
            #endif
            open(code: code, intent: .rejoin)
        }
        Task { await refreshStreaks() }
        return result
    }

    // MARK: Notification settings (spec §12.6)

    var notifySettings: NotifySettings { notify.settings(band: ageBand) }

    /// A dial or toggle changed on the panel: kept here, then synced (signed in) or sent (guest).
    func setNotify(_ key: String, _ value: JSONValue) {
        notify.set(key, value, now: Int64(Date.now.timeIntervalSince1970 * 1000))
        // Quiet hours move the widgets' evening.
        if key == NotifyKey.quietStart { syncWidgets() }
        // The live table toggle off ends any on the Lock Screen now (spec §11.3).
        if key == NotifyKey.liveTable { Task { await liveTables.sweep(entering: nil) } }
        if account.isSignedIn {
            account.noteLocalChanges()
        } else {
            Task { await uploadGuestNotify() }
        }
    }

    /// A guest device's changed notification settings go to its player: the server decides
    /// every player's reminders, not just signed-in ones. Kept for the next try on failure.
    func uploadGuestNotify() async {
        guard !account.isSignedIn, people.owner != nil, let patch = notify.pendingPatch(band: ageBand) else { return }
        do {
            try await api.patchState(patch, person: nil)
            notify.sent(patch)
        } catch {
            // Offline, or no player yet: the next foreground tries again.
        }
    }

    /// A kitten's local daily reminder (§14.1), off until they turn it on.
    var kittenDailyOn: Bool { settings.kittenDaily }

    func setKittenDaily(_ on: Bool) {
        settings.kittenDaily = on
        let name = people.owner?.name ?? ""
        Task {
            if on, let push, await push.authorizationStatus() == .notDetermined { _ = await push.requestAuthorization() }
            push?.setKittenDaily(on: on, name: name)
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
        syncWidgets()
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
        tips.reload()
        streaks.person = people.owner?.id
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
            // The notification settings someone chose (none on a kitten's device).
            values.merge(notify.values(band: ageBand)) { $1 }
            return values
        case .archive:
            return tableArchive.all().mapValues { .number($0) }
        case .tutorial:
            guard let id = accountPersonId else { return [:] }
            // The game's tips and the UI tips, by name.
            let names = (tipsSeen[id] ?? []).map(\.rawValue) + (tips.seen[id] ?? []).map(\.rawValue)
            return Dictionary(uniqueKeysWithValues: names.map { ($0, JSONValue.bool(true)) })
        }
    }

    /// Takes in values another device wrote later than this one.
    func applySynced(_ section: SyncSectionName, _ entries: SyncSection, accountPersonId: String?) {
        switch section {
        case .settings:
            notify.takeRemote(entries.filter { NotifyKey.all.contains($0.key) })
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
            var all = tutorialStore.loadNames()
            for (key, entry) in entries where CoachTip(rawValue: key) != nil || UITip(rawValue: key) != nil {
                if entry.v.boolValue == true { all[id, default: []].insert(key) } else { all[id]?.remove(key) }
            }
            tutorialStore.replaceNames(all)
            tipsSeen = tutorialStore.load()
            tips.reload()
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
        tips.reset()
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

    /// The priming screen's "not now": provisional authorization, with no prompt (§12.5), so
    /// notifications arrive quietly in Notification Center; Home's bell offers the full prompt once.
    func declinePush() {
        settings.pushPrimed = true
        settings.pushDeclinedOnce = true
        Task { await push?.requestProvisional() }
    }

    func goHome() {
        guard people.owner != nil else { return }
        inviteShown = false
        closeRoom()
        cache = tableCache.all()
        route = .home
        Task { await refreshStreaks() }
    }
}

/// Which kitten a consent notification opened the Kittens panel on.
struct KittensPanelRequest: Identifiable, Equatable {
    let focus: String
    var id: String { focus }
}
