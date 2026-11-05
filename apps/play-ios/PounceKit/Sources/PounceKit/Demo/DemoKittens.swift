#if DEBUG
import Foundation
import Synchronization

/// `-demo-kitten <locked|held|pending|on>` (the kitten's side) and `-demo-kittens` (a parent's):
/// the consent routes in memory, as the server would answer. The kitten's pairs are the demo
/// streaks' (`DemoFixtures.streaks()`), and only Mia is approved, so Kiki and Nova show padlocks.
public final class DemoKittenService: KittenService, Sendable {
    public enum Scenario: String, Sendable {
        case locked, held, pending, on
    }

    public static let code = "482913"
    public static let mochi = "k_demoMochiAAAAAAAAAAAAAA"
    public static let biscuit = "k_demoBiscuitAAAAAAAAAAAA"

    private let state: Mutex<(status: KittenStatus, kittens: [ParentKitten])>

    public init(scenario: Scenario) {
        let linked = scenario == .pending || scenario == .on
        let status = KittenStatus(
            state: scenario == .on ? .consented : linked ? .pending : .none, linked: linked,
            approved: linked ? ["pr_demoMiaAAAAAAAAAAAAAAA"] : [])
        state = Mutex((status, Self.parentKittens()))
    }

    /// Mochi waits on the text; Biscuit is on, with Apple's Communication Limits deciding.
    public static func parentKittens() -> [ParentKitten] {
        [
            ParentKitten(
                id: mochi, name: "Mochi", cat: 4, state: .pending, mode: .parent,
                people: [
                    KittenPerson(pair: "pr_demoJDAAAAAAAAAAAAAAAA", name: "JD", cat: 0, approved: true, parent: true),
                    KittenPerson(pair: "pr_demoMiaAAAAAAAAAAAAAAA", name: "Mia", cat: 2, approved: true, parent: false),
                    KittenPerson(pair: "pr_demoKikiAAAAAAAAAAAAAA", name: "Kiki", cat: 6, approved: false, parent: false),
                ]),
            ParentKitten(
                id: biscuit, name: "Biscuit", cat: 7, state: .on, mode: .apple,
                people: [
                    KittenPerson(pair: "pr_demoNovaAAAAAAAAAAAAAA", name: "Nova", cat: 5, approved: true, parent: false),
                    KittenPerson(pair: "pr_demoLeoAAAAAAAAAAAAAAA", name: "Leo", cat: 1, approved: false, parent: false),
                ]),
        ]
    }

    public func kittenStatus(person: String) async throws -> KittenStatus { state.withLock { $0.status } }

    public func linkCode(person: String, appTransactionId: String?) async throws -> LinkCode {
        LinkCode(code: Self.code, expiresAt: (Date.now.timeIntervalSince1970 + 600) * 1000)
    }

    public func mirrorApple(person: String, mirror: KittenApprovals.Mirror) async throws {
        state.withLock { $0.status.approved = mirror.apple ?? $0.status.approved }
    }

    public func kittens() async throws -> [ParentKitten] { state.withLock { $0.kittens } }

    /// The demo code links a third kitten; any other is wrong.
    public func link(code: String) async throws -> ParentKitten {
        guard code == Self.code else { throw APIError.notFound }
        let pickle = ParentKitten(id: "k_demoPickleAAAAAAAAAAAAA", name: "Pickle", cat: 3, state: .pending, mode: .parent, people: [])
        state.withLock { $0.kittens.append(pickle) }
        return pickle
    }

    public func setApproved(kitten: String, pairs: [String]) async throws {
        edit(kitten) { k in
            for i in k.people.indices where !k.people[i].parent { k.people[i].approved = pairs.contains(k.people[i].pair) }
        }
    }

    public func startConsent(kitten: String, phone: String) async throws { edit(kitten) { $0.state = .texted } }
    public func revokeConsent(kitten: String) async throws { edit(kitten) { $0.state = .pending } }
    public func unlink(kitten: String) async throws { state.withLock { $0.kittens.removeAll { $0.id == kitten } } }

    private func edit(_ id: String, _ change: (inout ParentKitten) -> Void) {
        state.withLock { s in
            if let i = s.kittens.firstIndex(where: { $0.id == id }) { change(&s.kittens[i]) }
        }
    }
}
#endif
