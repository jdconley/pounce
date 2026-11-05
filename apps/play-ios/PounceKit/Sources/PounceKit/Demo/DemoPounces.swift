#if DEBUG
import Foundation

/// `-demo-streaks`: the pounce routes in memory, acting on the demo streaks the way the server
/// would: a send marks the bell sent (or refuses while it rests), an answer clears the waiting
/// pounce and Play names a table, and a Messages link previews a pounce from Leo.
public final class DemoPounceService: PounceService, Sendable {
    public static let linkToken = "DemoLinkAAAAAAAAAAAAAAA".prefix(22).description
    /// The table a new game "deals".
    public static let newCode = "NWCDF"

    private let streaks: DemoStreakService

    public init(streaks: DemoStreakService) {
        self.streaks = streaks
    }

    public func send(to pair: String?, target: PounceTarget, person: String?) async throws -> PounceSent {
        guard let pair else {
            return PounceSent(id: "pc_demoLinkAAAAAAAAAAAAAA", link: DeepLink.pounceURL(token: Self.linkToken))
        }
        if streaks.first(where: { $0.pair == pair })?.pounce.resting == true { throw APIError.rateLimited }
        streaks.edit(pair) { $0.pounce.sent = true }
        return PounceSent(id: "pc_demoSentAAAAAAAAAAAAAA", link: nil)
    }

    public func answer(id: String, answer: PounceAnswer, choice: String?, link: String?, person: String?) async throws -> String? {
        if let view = streaks.first(where: { $0.pounce.waiting?.id == id }), let waiting = view.pounce.waiting {
            streaks.edit(view.pair) { $0.pounce.waiting = nil }
            guard answer == .play else { return nil }
            if case .table(let code) = waiting.target { return code }
            return choice.flatMap { $0 == "new" ? nil : $0 } ?? Self.newCode
        }
        guard answer == .play else { return nil }
        return choice.flatMap { $0 == "new" ? nil : $0 } ?? Self.newCode
    }

    public func linkPounce(token: String) async throws -> LinkPounce {
        LinkPounce(id: "pc_demoLinkAAAAAAAAAAAAAA", from: PushFace(name: "Leo", cat: 1), target: .pick)
    }
}
#endif
