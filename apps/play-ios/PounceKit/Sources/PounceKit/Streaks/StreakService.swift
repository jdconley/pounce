import Foundation

/// The streak routes of play-api (spec §13.4). `APIClient` in real runs; `DemoStreakService` for
/// the Debug `-demo-streaks` screens. Every call takes the local person it acts for (`?person=`).
/// A 404 from `streaks` means the server has streaks off.
public protocol StreakService: Sendable {
    func streaks(person: String?) async throws -> StreakList
    func pause(pair: String, days: Int, person: String?) async throws
    func unpause(pair: String, person: String?) async throws
    func openGift(pair: String, gift: String, person: String?) async throws
    func pin(pair: String, person: String?) async throws
    func leave(pair: String, person: String?) async throws
    /// The ghosted cat's plus: undo leaving `pair` and start a fresh pair at 0.
    func rejoin(pair: String, person: String?) async throws
}

extension APIClient: StreakService {
    private static func query(_ person: String?) -> [URLQueryItem] {
        person.map { [URLQueryItem(name: "person", value: $0)] } ?? []
    }

    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) ?? id
    }

    public func streaks(person: String?) async throws -> StreakList {
        let data = try await authenticated("GET", "/v1/me/streaks", body: nil, query: Self.query(person))
        return try decode(StreakList.self, from: data, status: 200)
    }

    public func pause(pair: String, days: Int, person: String?) async throws {
        _ = try await authenticated(
            "PUT", "/v1/pairs/\(Self.segment(pair))/pause", body: ["days": days], query: Self.query(person))
    }

    public func unpause(pair: String, person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/pairs/\(Self.segment(pair))/pause", body: nil, query: Self.query(person))
    }

    public func openGift(pair: String, gift: String, person: String?) async throws {
        _ = try await authenticated(
            "POST", "/v1/pairs/\(Self.segment(pair))/gifts/\(Self.segment(gift))/open", body: nil, query: Self.query(person))
    }

    public func pin(pair: String, person: String?) async throws {
        _ = try await authenticated("PUT", "/v1/pairs/\(Self.segment(pair))/pin", body: nil, query: Self.query(person))
    }

    public func leave(pair: String, person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/pairs/\(Self.segment(pair))", body: nil, query: Self.query(person))
    }

    public func rejoin(pair: String, person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/me/left/\(Self.segment(pair))", body: nil, query: Self.query(person))
    }
}
