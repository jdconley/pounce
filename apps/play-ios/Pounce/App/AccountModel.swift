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
    @ObservationIgnored private var uploadState = UploadState()
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// This device just started the account (an upgrade): its values win the first sync.
    @ObservationIgnored private var firstLookWins = false
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

    /// A person's age band: the owner's from the age check; a household person's as whoever
    /// added them picked it. Nil for someone added before ages were asked, until a band is picked.
    /// On a kitten's device everyone counts as a kitten (§14.1).
    func band(of personId: String) -> AgeBand? {
        if personId == app.people.owner?.id { return app.ageBand }
        if app.ageBand == .kitten { return .kitten }
        return record.bands[personId]
    }

    /// Names are typed for this person (never for a kitten, or anyone whose band isn't known).
    func typesName(_ personId: String) -> Bool {
        app.limits.typedNames && (band(of: personId) == .teen || band(of: personId) == .adult)
    }

    /// Sets the band of someone added before ages were asked.
    func setBand(_ personId: String, _ band: AgeBand) {
        record.bands[personId] = band
        save()
        uploadState.noteChange()
        scheduleUpload()
    }

    /// Sign-in is offered on this device at all: never to a kitten (spec §14.1), never while a
    /// parent's approval of this update is owed.
    var offersSignIn: Bool { app.limits.signInOffered && !heldForApproval }

    /// This person may sign in from here: not a kitten (or a band nobody picked), not signed in
    /// already. A household person signs in on their own only once the owner has: on a phone with
    /// no account the server would make them the phone's account.
    func canSignIn(_ personId: String) -> Bool {
        guard offersSignIn, !isSignedIn(personId), !isImported(personId) else { return false }
        if personId == app.people.owner?.id { return true }
        guard let band = band(of: personId), band != .kitten else { return false }
        return isSignedIn
    }

    /// Providers the account could still link (v1 offers only Apple).
    var linkableProviders: [String] { ["apple"].filter { !record.providers.contains($0) } }

    // MARK: people bookkeeping

    /// A person's name or cat changed here: it goes up with that time, so the newest edit wins.
    func noteChanged(_ personId: String) {
        record.changedAt[personId] = Self.nowMs
        save()
        uploadState.noteChange()
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
        save()
        keys.remove(personId)
        uploadState.noteChange()
        scheduleUpload()
    }

    /// The device's time zone changed (spec §13.4).
    func timeZoneChanged() {
        uploadState.noteChange()
        scheduleUpload()
    }

    // MARK: profile upload

    /// Profile uploads wait for the age check and an owner, and for a parent's approval of this
    /// update where it's owed. A kitten's always go up: a generated name and the band `kitten` are
    /// internal operations, and the band is what stops the server pushing to the device.
    private var canUpload: Bool {
        app.ageRecord != nil && app.people.owner != nil && (!heldForApproval || app.ageBand == .kitten)
    }

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
        let service = service
        // Another change can land while this one is on the wire: go again until none did.
        for _ in 0..<3 {
            let started = uploadState.begin()
            do {
                let renamed = try await ProfileUploader.run(
                    people: app.peopleStore, tutorial: app.tutorialStore, keys: keys,
                    ownerBand: app.ageBand, timeZone: TimeZone.current.identifier,
                    record: { record }, update: { change in change(&record); save() }
                ) { body in try await service.uploadProfile(body) }
                if !renamed.isEmpty { app.peopleRenamed() }
                uploadState.finished(started)
                #if DEBUG
                print("[account] profile up: \(record.playerIds.count) players, \(renamed.count) renamed")
                #endif
            } catch {
                // Offline or the server is down: still owed for the next try. A rename that
                // already happened is in the stores and the record alike.
                uploadState.failed(started)
                app.peopleRenamed()
                #if DEBUG
                print("[account] profile upload failed: \(error)")
                #endif
                return
            }
            if !uploadState.pending { return }
        }
    }

    /// Whether a profile upload is owed (a change since the last one went up).
    var uploadPending: Bool { uploadState.pending }

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
        if uploadState.pending || record.playerIds[person.id] == nil { await uploadProfile() }
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
        // The device that upgrades in place started the account: what was chosen here as a guest
        // goes up as chosen. A device that merged into an account takes the account's values.
        firstLookWins = reply.account && reply.outcome != .merged
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
        save()
        uploadState.noteChange()
    }

    // MARK: sync (spec §13.1, "what syncs")

    /// Settings, the archive and the account person's tips, last writer wins per key; household
    /// people and the account's name and cat from the server. Signed-in devices only.
    func sync() async {
        guard isSignedIn, !heldForApproval, !syncing else { return }
        syncing = true
        defer { syncing = false }
        noteLocalChanges(scheduling: false)
        let state: MeState
        do {
            state = try await service.state(person: nil)
        } catch APIError.notFound {
            // The account is gone (deleted, or this device was detached elsewhere): a guest again.
            forgetAccount()
            await uploadProfile()
            await app.refreshTables()
            return
        } catch {
            return
        }
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
    func noteLocalChanges(scheduling: Bool = true) {
        guard isSignedIn else { return }
        defer { if scheduling { scheduleSync() } }
        let now = Self.nowMs
        for name in SyncSectionName.allCases {
            let current = app.syncedValues(name, accountPersonId: record.accountPersonId)
            // The first look after signing in: this device's values go up only where the account
            // has none (time 1 loses to any real write), so a fresh iPad's defaults never undo
            // what was chosen on the iPhone.
            let first = record.ledger[name.rawValue] == nil
            var ledger = record.ledger[name.rawValue] ?? [:]
            for (key, value) in current where ledger[key]?.v != value {
                ledger[key] = SyncEntry(v: value, at: first && !firstLookWins ? 1 : now)
            }
            // A key that went away (a table restored, tips shown again) is written as cleared.
            for (key, entry) in ledger where current[key] == nil && entry.v != .null && entry.v != .bool(false) {
                ledger[key] = SyncEntry(v: name == .tutorial ? .bool(false) : .null, at: now)
            }
            record.ledger[name.rawValue] = ledger
        }
        firstLookWins = false
        save()
    }

    /// A local change goes up soon, not only on the next foreground.
    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
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
