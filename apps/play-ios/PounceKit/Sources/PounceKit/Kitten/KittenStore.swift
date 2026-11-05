import Foundation
import Observation

/// Parent consent on both sides (consent design §2). On a kitten's device: its consent, the code
/// to show a grown-up, and Apple's approvals mirrored up. On a signed-in adult's: their kittens,
/// linking by code, the toggles, the text and revoking. What the kitten's device last knew is kept
/// on disk, so a launch can decide about push before the server answers.
@MainActor @Observable public final class KittenStore {
    public enum LinkResult: Equatable, Sendable {
        case linked(ParentKitten)
        /// Wrong, used or expired.
        case wrong
        /// Too many tries: wait a bit.
        case tooMany
        case failed
    }

    public enum PhoneResult: Equatable, Sendable {
        case sent
        /// The server has no text provider yet: nothing was sent, the kitten stays pending.
        case notConfigured
        case failed
    }

    /// What survives a launch on the kitten's device.
    struct Saved: Codable, Equatable {
        var consented = false
        var asked: [String] = []
        var mirror: KittenApprovals.Mirror?
        /// This device registered for remote push as a consented kitten (so it unregisters after).
        var registered = false
    }

    // The kitten's device.
    /// The local person the kitten routes act for (the owner of a kitten's device).
    public var person: String?
    public private(set) var status: KittenStatus?
    public private(set) var code: LinkCode?
    public private(set) var fetchingCode = false

    // The parent's device.
    public private(set) var kittens: [ParentKitten] = []
    /// The server answered the list at least once.
    public private(set) var kittensLoaded = false

    @ObservationIgnored private let service: any KittenService
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var saved: Saved

    public init(service: any KittenService, file: URL?) {
        self.service = service
        self.file = file
        saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    /// Consent is on: from the server's last answer, else what the device last knew.
    public var consented: Bool { status?.consented ?? saved.consented }

    /// This device registered for push as a consented kitten at some point (it must unregister when consent ends).
    public var registeredAsKitten: Bool { saved.registered }

    public func noteRegistered(_ on: Bool) {
        saved.registered = on
        save()
    }

    // MARK: the kitten's device

    public func refreshStatus() async {
        guard let person else { return }
        guard let fresh = try? await service.kittenStatus(person: person) else { return }
        status = fresh
        if saved.consented != fresh.consented {
            saved.consented = fresh.consented
            save()
        }
    }

    /// A fresh code unless the one held is still good for a minute.
    public func requestCode(appTransactionId: String?, now: Date = .now) async {
        guard let person, !fetchingCode else { return }
        if let code, code.fresh(at: now.addingTimeInterval(60)) { return }
        fetchingCode = true
        defer { fetchingCode = false }
        code = try? await service.linkCode(person: person, appTransactionId: appTransactionId)
    }

    /// Whether a person is padlocked for this kitten (plan decision 38). Unknown counts as open:
    /// the server refuses an unapproved pounce anyway.
    public func locks(pair: String) -> Bool { status?.locks(pair: pair) ?? false }

    /// Apple's answers up to the server (plan decision 22). Returns the partners to ask about; the
    /// caller asks PermissionKit, then calls `noteAsked`.
    @discardableResult
    public func mirror(limits: Bool, partners: [String], known: Set<String>) async -> [String] {
        let plan = KittenApprovals.plan(limits: limits, partners: partners, known: known, asked: Set(saved.asked), last: saved.mirror)
        if let send = plan.send, let person {
            do {
                try await service.mirrorApple(person: person, mirror: send)
                saved.mirror = send
                save()
                await refreshStatus()
            } catch {
                // Kept for the next launch or refresh.
            }
        }
        return plan.ask
    }

    public func noteAsked(_ pairs: [String]) {
        saved.asked = Array(Set(saved.asked).union(pairs)).sorted()
        save()
    }

    /// The kitten asks again from a padlocked person: forget that it was asked.
    public func forgetAsked(_ pair: String) {
        saved.asked.removeAll { $0 == pair }
        save()
    }

    // MARK: the parent's device

    public func refreshKittens() async {
        guard let list = try? await service.kittens() else { return }
        kittens = list
        kittensLoaded = true
    }

    public func link(code: String) async -> LinkResult {
        do {
            let kitten = try await service.link(code: code)
            if let i = kittens.firstIndex(where: { $0.id == kitten.id }) { kittens[i] = kitten } else { kittens.append(kitten) }
            return .linked(kitten)
        } catch APIError.notFound {
            return .wrong
        } catch APIError.rateLimited {
            return .tooMany
        } catch {
            return .failed
        }
    }

    /// Flips one person's toggle, showing it at once and putting it back if the server refuses.
    public func toggle(kitten id: String, pair: String) async {
        guard let i = kittens.firstIndex(where: { $0.id == id }), let pairs = kittens[i].approvals(toggling: pair) else { return }
        let before = kittens[i]
        for j in kittens[i].people.indices where kittens[i].people[j].pair == pair { kittens[i].people[j].approved.toggle() }
        do {
            try await service.setApproved(kitten: id, pairs: pairs)
        } catch {
            if let k = kittens.firstIndex(where: { $0.id == id }) { kittens[k] = before }
        }
    }

    public func sendPhone(kitten id: String, phone: String) async -> PhoneResult {
        do {
            try await service.startConsent(kitten: id, phone: phone)
            if let i = kittens.firstIndex(where: { $0.id == id }) { kittens[i].state = .texted }
            return .sent
        } catch APIError.notConfigured {
            return .notConfigured
        } catch {
            return .failed
        }
    }

    public func revoke(kitten id: String) async {
        guard (try? await service.revokeConsent(kitten: id)) != nil else { return }
        if let i = kittens.firstIndex(where: { $0.id == id }) { kittens[i].state = .pending }
    }

    public func unlink(kitten id: String) async {
        guard (try? await service.unlink(kitten: id)) != nil else { return }
        kittens.removeAll { $0.id == id }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
