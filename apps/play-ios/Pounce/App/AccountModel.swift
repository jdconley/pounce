import Foundation
import Observation
import PounceKit

/// Accounts in the app (spec §10.5, §13.1): this device's players, the profile upload, Sign in
/// with Apple (the anonymous upgrade, merges, household people), sign-out, deletion, and sync of
/// settings, people, the archive and tips. Signing in is never required.
@MainActor @Observable
final class AccountModel {
    /// Two cats, about to become (or just become) one.
    struct Merge: Equatable {
        var mine: Int
        var theirs: Int
        var theirName: String
        /// Waiting for a yes (a link that found another player); false once it happened.
        var asking: Bool
    }

    private(set) var record: AccountRecord
    /// A sign-in or account call is running (its button shows the yarn).
    private(set) var busy = false
    /// The merge picture on screen, if any.
    var merge: Merge?
    /// Deletion finished: show the picture of the iOS Settings path for stopping Apple sign-in.
    var showSettingsPath = false
    /// The significant-change approval is still owed (spec §14.1): accounts stay off until then.
    var heldForApproval = false

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private let service: AccountService
    @ObservationIgnored private let apple: AppleSigning
    @ObservationIgnored let keys: PersonKeyStore
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private var pendingProof: AppleProof?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var uploading = false
    #if DEBUG
    @ObservationIgnored let stub: StubScenario?
    #endif

    init(app: AppModel, service: AccountService, apple: AppleSigning, keys: PersonKeyStore, store: AccountStore) {
        self.app = app
        self.service = service
        self.apple = apple
        self.keys = keys
        self.store = store
        record = store.load()
        #if DEBUG
        stub = StubScenario.from(arguments: CommandLine.arguments)
        #endif
    }

    private func save() { store.save(record) }

    private static var nowMs: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    // MARK: who

    var isSignedIn: Bool { record.isSignedIn }

    /// The person this device is signed in as.
    var accountPerson: Person? {
        guard let id = record.accountPersonId else { return nil }
        return app.everyone.first { $0.id == id }
    }

    func isSignedIn(_ personId: String) -> Bool { record.signedIn.contains(personId) }

    func isImported(_ personId: String) -> Bool { record.imported.contains(personId) }

    func band(of personId: String) -> AgeBand? {
        personId == app.people.owner?.id ? app.ageBand : record.bands[personId] ?? app.ageBand
    }

    /// Sign-in is offered on this device at all: never to a kitten (spec §14.1), never while a
    /// parent's approval of this update is owed.
    var offersSignIn: Bool { app.limits.signInOffered && !heldForApproval }

    /// This person may sign in from here: not a kitten, and not signed in already.
    func canSignIn(_ personId: String) -> Bool {
        offersSignIn && band(of: personId) != .kitten && !isSignedIn(personId) && !isImported(personId)
    }

    /// Providers the account could still link (v1 offers only Apple).
    var linkableProviders: [String] { ["apple"].filter { !record.providers.contains($0) } }

    // MARK: people bookkeeping

    /// A person's name or cat changed here: it goes up with that time, so the newest edit wins.
    func noteChanged(_ personId: String) {
        record.changedAt[personId] = Self.nowMs
        record.pendingUpload = true
        save()
        scheduleUpload()
    }

    /// A household person was added with the band their adder picked.
    func noteAdded(_ personId: String, band: AgeBand) {
        record.bands[personId] = band
        noteChanged(personId)
    }

    func noteRemoved(_ personId: String) {
        record.bands[personId] = nil
        record.changedAt[personId] = nil
        record.signedIn.remove(personId)
        record.pendingUpload = true
        save()
        keys.remove(personId)
        scheduleUpload()
    }

    /// The device's time zone changed (spec §13.4).
    func timeZoneChanged() {
        record.pendingUpload = true
        save()
        scheduleUpload()
    }

    // MARK: profile upload

    /// Profile uploads wait for the age check and an owner; a kitten's still go up (generated name,
    /// band `kitten`, so the server sends it nothing).
    private var canUpload: Bool { app.ageRecord != nil && app.people.owner != nil && !heldForApproval }

    private func scheduleUpload() {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.uploadProfile()
        }
    }

    /// Launch, foreground and after edits. A failure leaves it owed for the next try.
    func uploadProfile() async {
        guard canUpload, !uploading else { return }
        uploading = true
        defer { uploading = false }
        var working = record
        let service = service
        do {
            let renamed = try await ProfileUploader.run(
                people: app.peopleStore, tutorial: app.tutorialStore, record: &working, keys: keys,
                ownerBand: app.ageBand, timeZone: TimeZone.current.identifier
            ) { body in try await service.uploadProfile(body) }
            record = working
            save()
            if !renamed.isEmpty { app.peopleRenamed() }
            #if DEBUG
            print("[account] profile up: \(working.playerIds.count) players, \(renamed.count) renamed")
            #endif
        } catch {
            // Offline or the server is down: still owed (pendingUpload stays set).
            #if DEBUG
            print("[account] profile upload failed: \(error)")
            #endif
        }
    }

    // MARK: sign in (spec §13.1)

    enum Outcome: Equatable {
        case upgraded
        case merged
        case cancelled
        case refused
        case failed
    }

    /// Signs `person` in with Apple: the anonymous upgrade in place, or a merge into the player
    /// that already has this Apple ID (a second device), which shows two cats becoming one.
    @discardableResult
    func signIn(_ person: Person) async -> Outcome {
        guard canSignIn(person.id), !busy else { return .refused }
        busy = true
        defer { busy = false }
        if record.pendingUpload || record.playerIds[person.id] == nil { await uploadProfile() }
        let proof: AppleProof
        do {
            proof = try await apple.proof()
        } catch AppleSignInError.cancelled {
            return .cancelled
        } catch {
            return .failed
        }
        let reply: SignInReply
        do {
            reply = try await service.signIn(
                provider: "apple", proof: proof, personId: person.id, personKey: keys.key(for: person.id))
        } catch APIError.forbidden {
            return .refused
        } catch {
            return .failed
        }
        record.signedIn.insert(person.id)
        record.playerIds[person.id] = reply.playerId
        if reply.account {
            record.accountPersonId = person.id
            if !record.providers.contains("apple") { record.providers.append("apple") }
        }
        save()
        if reply.outcome == .merged {
            // The account keeps its own name and cat; this device shows them now.
            if person.id == app.people.owner?.id {
                app.adoptAccountProfile(name: reply.profile.name, cat: reply.profile.cat)
            }
            merge = Merge(mine: person.cat, theirs: reply.profile.cat, theirName: reply.profile.name, asking: false)
        }
        await afterAccountChange()
        return reply.outcome == .merged ? .merged : .upgraded
    }

    /// Links a provider the account doesn't have. If that identity is someone else's, the two
    /// cats show and nothing merges until the yes (`confirmMerge`).
    func link(_ provider: String = "apple") async {
        guard isSignedIn, offersSignIn, !busy else { return }
        busy = true
        defer { busy = false }
        guard let proof = try? await apple.proof() else { return }
        do {
            switch try await service.link(provider: provider, proof: proof, confirmMerge: false, person: nil) {
            case .linked:
                linked(provider)
                await afterAccountChange()
            case .mergeNeeded(let name, let cat):
                pendingProof = proof
                merge = Merge(mine: accountPerson?.cat ?? 0, theirs: cat, theirName: name, asking: true)
            }
        } catch {
            // Already linked or offline: nothing changes.
        }
    }

    /// The yes on the merge question: the other player folds into this one.
    func confirmMerge(_ provider: String = "apple") async {
        guard let proof = pendingProof, var shown = merge, shown.asking else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await service.link(provider: provider, proof: proof, confirmMerge: true, person: nil)
            pendingProof = nil
            linked(provider)
            shown.asking = false
            merge = shown
            await afterAccountChange()
        } catch {
            pendingProof = nil
            merge = nil
        }
    }

    func cancelMerge() {
        pendingProof = nil
        merge = nil
    }

    private func linked(_ provider: String) {
        if !record.providers.contains(provider) { record.providers.append(provider) }
        save()
    }

    private func afterAccountChange() async {
        await sync()
        await app.refreshTables()
    }

    // MARK: sign out and delete (spec §13.1, §14)

    /// This device unlinks and plays on as a fresh guest; the account keeps its data.
    func signOut() async {
        guard isSignedIn, !busy else { return }
        busy = true
        defer { busy = false }
        do { try await service.signOut() } catch { return }
        forgetAccount()
        await uploadProfile()
        await app.refreshTables()
    }

    /// Deletes the account (the device's, or a household person's own), then shows how to stop
    /// Apple sign-in in Settings. False when the server didn't take it.
    @discardableResult
    func deleteAccount(personId: String? = nil) async -> Bool {
        let target = personId ?? record.accountPersonId
        guard let target, !busy else { return false }
        busy = true
        defer { busy = false }
        let isAccount = target == record.accountPersonId
        do { try await service.deleteMe(person: isAccount ? nil : target) } catch { return false }
        if isAccount {
            forgetAccount()
        } else {
            record.signedIn.remove(target)
            save()
        }
        showSettingsPath = true
        await uploadProfile()
        await app.refreshTables()
        return true
    }

    /// Everything the account brought to this device goes: its household people, links and sync
    /// record. This device's own people, settings and tables stay.
    private func forgetAccount() {
        if let id = record.accountPersonId { record.signedIn.remove(id) }
        app.removeImported(Set(record.imported))
        record.accountPersonId = nil
        record.providers = []
        record.imported = []
        record.ledger = [:]
        record.pendingUpload = true
        save()
    }

    // MARK: sync (spec §13.1, "what syncs")

    /// Settings, the archive and the account person's tips, last writer wins per key; household
    /// people and the account's name and cat from the server. Signed-in devices only.
    func sync() async {
        guard isSignedIn, !heldForApproval else { return }
        noteLocalChanges()
        guard let state = try? await service.state(person: nil) else { return }
        for name in SyncSectionName.allCases {
            let local = record.ledger[name.rawValue] ?? [:]
            let (push, apply) = SyncMerge.reconcile(local: local, remote: state[name])
            if !apply.isEmpty { app.applySynced(name, apply, accountPersonId: record.accountPersonId) }
            record.ledger[name.rawValue] = local.merging(apply) { $1 }
            for chunk in SyncMerge.chunks(StatePatch(settings: name == .settings ? push : nil,
                                                     tutorial: name == .tutorial ? push : nil,
                                                     archive: name == .archive ? push : nil)) {
                try? await service.patchState(chunk, person: nil)
            }
        }
        importHousehold(state.people)
        if let profile = state.profile, let owner = app.people.owner, record.accountPersonId == owner.id,
           profile.at > (record.changedAt[owner.id] ?? 0) {
            app.adoptAccountProfile(name: profile.name, cat: profile.cat)
            record.changedAt[owner.id] = profile.at
        }
        save()
    }

    /// Writes this device's current settings, archive and tips into the ledger, stamping what
    /// changed since the last look with now. Called after each local change, and before a sync.
    func noteLocalChanges() {
        guard isSignedIn else { return }
        let now = Self.nowMs
        for name in SyncSectionName.allCases {
            let current = app.syncedValues(name, accountPersonId: record.accountPersonId)
            // The first look after signing in: this device's values go up only where the account
            // has none (time 1 loses to any real write), so a fresh iPad's defaults never undo
            // what was chosen on the iPhone.
            let first = record.ledger[name.rawValue] == nil
            var ledger = record.ledger[name.rawValue] ?? [:]
            for (key, value) in current where ledger[key]?.v != value {
                ledger[key] = SyncEntry(v: value, at: first ? 1 : now)
            }
            // A key that went away (a table restored, tips shown again) is written as cleared.
            for (key, entry) in ledger where current[key] == nil && entry.v != .null && entry.v != .bool(false) {
                ledger[key] = SyncEntry(v: name == .tutorial ? .bool(false) : .null, at: now)
            }
            record.ledger[name.rawValue] = ledger
        }
        save()
    }

    /// The account's household people from its other devices, for pass-and-play here too.
    private func importHousehold(_ household: [HouseholdPerson]) {
        let own = Set(app.everyone.map(\.id)).subtracting(record.imported)
        let listed = household.filter { !own.contains($0.personId) }
        app.setImported(listed.map { Person(id: $0.personId, name: $0.name, cat: $0.cat) }, previous: Set(record.imported))
        record.imported = listed.map(\.personId)
        for person in listed { record.playerIds[person.personId] = person.playerId }
    }

    // MARK: debug

    #if DEBUG
    /// `-stub-accounts signed-in` / `link-merge`: start signed in, once there is an owner.
    func applyDebugPreset() async {
        guard let stub, stub == .signedIn || stub == .linkMerge, !isSignedIn, let owner = app.people.owner else { return }
        record.accountPersonId = owner.id
        record.signedIn.insert(owner.id)
        record.providers = stub == .signedIn ? ["apple"] : []
        save()
        await sync()
    }
    #endif
}
