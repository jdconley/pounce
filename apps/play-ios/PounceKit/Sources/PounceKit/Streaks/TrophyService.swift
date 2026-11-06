import Foundation
import Observation

/// The trophy room's route (trophy room design §5). A 404 means the server has no trophy room.
public protocol TrophyService: Sendable {
    func trophies(person: String?) async throws -> Trophies
}

extension APIClient: TrophyService {
    public func trophies(person: String?) async throws -> Trophies {
        let query = person.map { [URLQueryItem(name: "person", value: $0)] } ?? []
        let data = try await authenticated("GET", "/v1/me/trophies", body: nil, query: query, noPlayer: true)
        return try decode(Trophies.self, from: data, status: 200)
    }
}

/// The owner's trophy room. `enabled` is nil until the server answered, false after a 404; going
/// offline keeps what was shown.
@MainActor @Observable public final class TrophyStore {
    public var person: String? {
        didSet { if person != oldValue { trophies = nil; enabled = nil } }
    }
    public private(set) var enabled: Bool?
    public private(set) var trophies: Trophies?

    @ObservationIgnored private let service: any TrophyService

    public init(service: any TrophyService) {
        self.service = service
    }

    public func refresh() async {
        guard let person else { return }
        do {
            let t = try await service.trophies(person: person)
            guard person == self.person else { return }
            trophies = t
            enabled = true
        } catch APIError.notFound {
            guard person == self.person else { return }
            trophies = nil
            enabled = false
        } catch {
            // Offline or the server is down: keep what was shown.
        }
    }
}
