import Foundation

/// The pounce routes of play-api (spec §12.4, §13.4). `APIClient` in real runs;
/// `DemoPounceService` under the Debug `-demo-streaks`. Each call acts for a local person
/// (`?person=`). Resting is a 429 (`APIError.rateLimited`).
public protocol PounceService: Sendable {
    /// With `to` (a pair id), a push to the partner; without, a Messages link.
    func send(to pair: String?, target: PounceTarget, person: String?) async throws -> PounceSent
    /// Play (with `choice` for "you pick"), In a bit, or Not now; the table Play went to.
    func answer(id: String, answer: PounceAnswer, choice: String?, link: String?, person: String?) async throws -> String?
    /// A Messages pounce's sender and target, before answering it.
    func linkPounce(token: String) async throws -> LinkPounce
}

extension APIClient: PounceService {
    private static func query(_ person: String?) -> [URLQueryItem] {
        person.map { [URLQueryItem(name: "person", value: $0)] } ?? []
    }

    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) ?? id
    }

    private struct SendBody: Encodable, Sendable {
        let to: String?
        let target: PounceTarget

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(to, forKey: .to)
            try c.encode(target, forKey: .target)
        }

        private enum CodingKeys: String, CodingKey { case to, target }
    }

    private struct AnswerBody: Encodable, Sendable {
        let answer: PounceAnswer
        let choice: String?
        let link: String?
    }

    public func send(to pair: String?, target: PounceTarget, person: String?) async throws -> PounceSent {
        let data = try await authenticated(
            "POST", "/v1/pounces", body: SendBody(to: pair, target: target), query: Self.query(person))
        return try decode(PounceSent.self, from: data, status: 201)
    }

    public func answer(id: String, answer: PounceAnswer, choice: String?, link: String?, person: String?) async throws -> String? {
        struct Reply: Decodable { let code: String? }
        let data = try await authenticated(
            "POST", "/v1/pounces/\(Self.segment(id))/answer", body: AnswerBody(answer: answer, choice: choice, link: link),
            query: Self.query(person))
        return try decode(Reply.self, from: data, status: 200).code
    }

    public func linkPounce(token: String) async throws -> LinkPounce {
        let data = try await authenticated("GET", "/v1/pounces/links/\(Self.segment(token))", body: nil)
        return try decode(LinkPounce.self, from: data, status: 200)
    }
}
