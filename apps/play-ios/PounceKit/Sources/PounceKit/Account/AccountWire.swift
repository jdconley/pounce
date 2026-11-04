import Foundation

/// The age bands the server keeps (spec §14.1). Never a birth date.
public enum AgeBand: String, Codable, CaseIterable, Sendable {
    /// Under 13.
    case kitten
    /// 13 to 17.
    case teen
    /// 18 and over.
    case adult
}

/// One person in `PUT /v1/devices/me/profile`. `at` is when the name or cat last changed here.
public struct ProfilePerson: Encodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cat: Int
    public var key: String
    public var ageBand: AgeBand?
    public var at: Int64

    public init(id: String, name: String, cat: Int, key: String, ageBand: AgeBand?, at: Int64) {
        self.id = id
        self.name = name
        self.cat = cat
        self.key = key
        self.ageBand = ageBand
        self.at = at
    }
}

/// `PUT /v1/devices/me/profile`: the device's time zone, its owner's band and its people.
public struct ProfileBody: Encodable, Equatable, Sendable {
    public var timeZone: String
    public var ageBand: AgeBand?
    public var people: [ProfilePerson]

    public init(timeZone: String, ageBand: AgeBand?, people: [ProfilePerson]) {
        self.timeZone = timeZone
        self.ageBand = ageBand
        self.people = people
    }
}

/// personId → playerId for each bound person; `rejected` ids were taken by someone else's key.
public struct ProfileReply: Decodable, Equatable, Sendable {
    public var players: [String: String]
    public var rejected: [String]

    public init(players: [String: String], rejected: [String]) {
        self.players = players
        self.rejected = rejected
    }
}

/// A Sign in with Apple proof: the identity token, the raw nonce (Apple saw its SHA-256), and the
/// authorization code the server may exchange for a refresh token.
public struct AppleProof: Encodable, Equatable, Sendable {
    public var identityToken: String
    public var nonce: String
    public var authorizationCode: String?

    public init(identityToken: String, nonce: String, authorizationCode: String?) {
        self.identityToken = identityToken
        self.nonce = nonce
        self.authorizationCode = authorizationCode
    }
}

/// `POST /v1/identities/{provider}`.
public struct SignInReply: Decodable, Equatable, Sendable {
    public enum Outcome: String, Decodable, Sendable {
        /// The identity was new: the guest player gained it in place.
        case upgraded
        /// The identity belonged to another player: the guest merged into it.
        case merged
        /// This player already had this identity.
        case same
    }

    public struct Profile: Decodable, Equatable, Sendable {
        public var name: String
        public var cat: Int
        public init(name: String, cat: Int) {
            self.name = name
            self.cat = cat
        }
    }

    public var playerId: String
    public var outcome: Outcome
    /// The device is now (or already was) signed in as this player.
    public var account: Bool
    public var profile: Profile

    public init(playerId: String, outcome: Outcome, account: Bool, profile: Profile) {
        self.playerId = playerId
        self.outcome = outcome
        self.account = account
        self.profile = profile
    }
}

/// `POST /v1/me/identities/{provider}`.
public enum LinkResult: Equatable, Sendable {
    case linked(merged: Bool)
    /// The identity is someone else's: ask before merging (`confirmMerge`).
    case mergeNeeded(name: String, cat: Int)
}

extension APIClient {
    private static func person(_ id: String?) -> [URLQueryItem] {
        id.map { [URLQueryItem(name: "person", value: $0)] } ?? []
    }

    /// Binds this device's people to players (spec §13.4). Called on launch, on a time-zone change
    /// and after people change.
    public func uploadProfile(_ body: ProfileBody) async throws -> ProfileReply {
        let data = try await authenticated("PUT", "/v1/devices/me/profile", body: body)
        return try decode(ProfileReply.self, from: data, status: 200)
    }

    /// Signs one person on this device in: the anonymous upgrade, or a merge into the identity's player.
    public func signIn(provider: String, proof: AppleProof, personId: String, personKey: String) async throws -> SignInReply {
        struct Body: Encodable, Sendable {
            struct Who: Encodable, Sendable { let id: String; let key: String }
            let proof: AppleProof
            let person: Who
        }
        let data = try await authenticated(
            "POST", "/v1/identities/\(provider)", body: Body(proof: proof, person: .init(id: personId, key: personKey)))
        return try decode(SignInReply.self, from: data, status: 200)
    }

    /// Adds a provider to the player. Someone else's identity comes back as `.mergeNeeded` until
    /// `confirmMerge` says yes.
    public func link(provider: String, proof: AppleProof, confirmMerge: Bool, person: String?) async throws -> LinkResult {
        struct Body: Encodable, Sendable { let proof: AppleProof; let confirmMerge: Bool }
        struct Reply: Decodable { let merged: Bool }
        do {
            let data = try await authenticated(
                "POST", "/v1/me/identities/\(provider)", body: Body(proof: proof, confirmMerge: confirmMerge),
                query: Self.person(person))
            return .linked(merged: try decode(Reply.self, from: data, status: 200).merged)
        } catch APIError.mergeNeeded(let name, let cat) {
            return .mergeNeeded(name: name, cat: cat)
        }
    }

    public func unlink(provider: String, person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/me/identities/\(provider)", body: nil, query: Self.person(person))
    }

    /// This device stops speaking for its account and plays on as a fresh guest.
    public func signOut() async throws {
        _ = try await authenticated("POST", "/v1/me/signout", body: nil)
    }

    /// Deletes the player and everything about it (spec §14).
    public func deleteMe(person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/me", body: nil, query: Self.person(person))
    }

    public func state(person: String?) async throws -> MeState {
        let data = try await authenticated("GET", "/v1/me/state", body: nil, query: Self.person(person))
        return try decode(MeState.self, from: data, status: 200)
    }

    public func patchState(_ patch: StatePatch, person: String?) async throws {
        _ = try await authenticated("PATCH", "/v1/me/state", body: patch, query: Self.person(person))
    }
}
