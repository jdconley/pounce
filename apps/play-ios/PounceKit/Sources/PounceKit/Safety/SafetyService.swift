import Foundation

/// Why a player is reported: the reasons the picker offers (play-api `REPORT_REASONS`).
public enum ReportReason: String, Codable, CaseIterable, Sendable {
    /// Their name is rude.
    case name
    /// They keep nudging or pouncing.
    case bothering
    case other
}

/// Whose name the server is asked about.
public enum NameKind: String, Codable, Sendable {
    case person, table
}

/// What the server says about a name before it is saved.
public enum NameVerdict: Equatable, Sendable {
    case ok
    /// The name filter refuses it.
    case badName
    /// Not for this device (a kitten types no names).
    case notAllowed

    /// The answer of `POST /v1/names/check`. An answer this build doesn't know counts as refused.
    public init(ok: Bool, reason: String?) {
        if ok {
            self = .ok
        } else {
            self = reason == "not_allowed" ? .notAllowed : .badName
        }
    }
}

/// Someone a player blocked: the server's handle for them, and the person and name they had at
/// the table where they were blocked.
public struct BlockedPlayer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let person: String
    public let name: String

    public init(id: String, person: String, name: String) {
        self.id = id
        self.person = person
        self.name = name
    }
}

/// Reports, blocks and the name check of play-api. `APIClient` in real runs. Blocks belong to a
/// local person (`?person=`); a report comes from the device.
public protocol SafetyService: Sendable {
    /// Whether the server would take `name`.
    func checkName(_ name: String, kind: NameKind) async throws -> NameVerdict
    /// Reports the person `person` at table `code`. The server records who, where and what
    /// their name was. Too many is a 429 (`APIError.rateLimited`).
    func report(code: String, person: String, reason: ReportReason) async throws
    /// Blocks the person `person` at table `code` for the local person `me`; their handle.
    func block(code: String, person: String, me: String?) async throws -> String
    func blocks(me: String?) async throws -> [BlockedPlayer]
    func unblock(id: String, me: String?) async throws
}

extension APIClient: SafetyService {
    private static func me(_ person: String?) -> [URLQueryItem] {
        person.map { [URLQueryItem(name: "person", value: $0)] } ?? []
    }

    private static func part(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) ?? id
    }

    public func checkName(_ name: String, kind: NameKind) async throws -> NameVerdict {
        struct Body: Encodable, Sendable { let kind: NameKind; let name: String }
        struct Reply: Decodable { let ok: Bool; let reason: String? }
        let data = try await authenticated("POST", "/v1/names/check", body: Body(kind: kind, name: name))
        let reply = try decode(Reply.self, from: data, status: 200)
        return NameVerdict(ok: reply.ok, reason: reply.reason)
    }

    public func report(code: String, person: String, reason: ReportReason) async throws {
        struct Body: Encodable, Sendable { let person: String; let reason: ReportReason }
        _ = try await authenticated(
            "POST", "/v1/rooms/\(Self.part(code))/reports", body: Body(person: person.lowercased(), reason: reason))
    }

    public func block(code: String, person: String, me: String?) async throws -> String {
        struct Body: Encodable, Sendable { let person: String }
        struct Reply: Decodable { let id: String }
        let data = try await authenticated(
            "POST", "/v1/rooms/\(Self.part(code))/blocks", body: Body(person: person.lowercased()), query: Self.me(me))
        return try decode(Reply.self, from: data, status: 200).id
    }

    public func blocks(me: String?) async throws -> [BlockedPlayer] {
        struct Reply: Decodable { let blocks: [BlockedPlayer] }
        let data = try await authenticated("GET", "/v1/me/blocks", body: nil, query: Self.me(me))
        return try decode(Reply.self, from: data, status: 200).blocks
    }

    public func unblock(id: String, me: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/me/blocks/\(Self.part(id))", body: nil, query: Self.me(me))
    }
}
