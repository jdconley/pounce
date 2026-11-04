import Foundation
import PounceKit

/// The account routes of play-api (spec §13.4). `APIClient` in real runs; a Debug stub under
/// `-stub-accounts`.
protocol AccountService: Sendable {
    func uploadProfile(_ body: ProfileBody) async throws -> ProfileReply
    func signIn(provider: String, proof: AppleProof, personId: String, personKey: String) async throws -> SignInReply
    func link(provider: String, proof: AppleProof, confirmMerge: Bool, person: String?) async throws -> LinkResult
    func signOut() async throws
    func deleteMe(person: String?) async throws
    func state(person: String?) async throws -> MeState
    func patchState(_ patch: StatePatch, person: String?) async throws
}

extension APIClient: AccountService {}

#if DEBUG
/// What `-stub-accounts <scenario>` plays out (UI tests and screenshots, no Apple account, no server).
enum StubScenario: String {
    /// Sign-in attaches to the guest: the anonymous upgrade.
    case upgraded
    /// Sign-in finds the identity on another player (Mia, the calico): the guest merges into it.
    case merged
    /// Starts signed in with no provider linked; linking Apple finds another player and asks first.
    case linkMerge = "link-merge"
    /// The person closes Apple's sheet.
    case cancel
    /// Starts signed in with Apple; the account lists a household person from another device.
    case signedIn = "signed-in"

    static func from(arguments: [String]) -> StubScenario? {
        guard let i = arguments.firstIndex(of: "-stub-accounts") else { return nil }
        return arguments[safe: i + 1].flatMap(StubScenario.init) ?? .upgraded
    }
}

/// In-memory account routes for `-stub-accounts`.
actor StubAccountService: AccountService {
    static let other = SignInReply.Profile(name: "Mia", cat: 2)

    private let scenario: StubScenario
    private var names: [String: (String, Int)] = [:]
    private var linkedOnce = false
    private(set) var patches: [StatePatch] = []

    init(scenario: StubScenario) { self.scenario = scenario }

    private static func playerId(_ personId: String) -> String {
        "p_" + String(personId.replacingOccurrences(of: "-", with: "").prefix(22))
    }

    func uploadProfile(_ body: ProfileBody) async throws -> ProfileReply {
        for p in body.people { names[p.id] = (p.name, p.cat) }
        return ProfileReply(
            players: Dictionary(uniqueKeysWithValues: body.people.map { ($0.id, Self.playerId($0.id)) }), rejected: [])
    }

    func signIn(provider: String, proof: AppleProof, personId: String, personKey: String) async throws -> SignInReply {
        try await Task.sleep(for: .milliseconds(150))
        let own = names[personId].map { SignInReply.Profile(name: $0.0, cat: $0.1) } ?? Self.other
        if scenario == .merged {
            return SignInReply(playerId: "p_mia", outcome: .merged, account: true, profile: Self.other)
        }
        return SignInReply(playerId: Self.playerId(personId), outcome: .upgraded, account: true, profile: own)
    }

    func link(provider: String, proof: AppleProof, confirmMerge: Bool, person: String?) async throws -> LinkResult {
        if scenario == .linkMerge, !confirmMerge { return .mergeNeeded(name: Self.other.name, cat: Self.other.cat) }
        linkedOnce = true
        return .linked(merged: confirmMerge)
    }

    func signOut() async throws {}
    func deleteMe(person: String?) async throws {}

    func state(person: String?) async throws -> MeState {
        guard scenario == .signedIn else { return MeState() }
        return MeState(people: [
            HouseholdPerson(personId: "0c0ffee0-0000-4000-8000-00000000beef", playerId: "p_sam", name: "Sam", cat: 6),
        ])
    }

    func patchState(_ patch: StatePatch, person: String?) async throws { patches.append(patch) }
}
#endif
