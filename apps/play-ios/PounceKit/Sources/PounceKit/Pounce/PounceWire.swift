import Foundation

/// A pair's pounce state as one of its people sees it (`PounceView` on the server, §12.4):
/// the `pounce` field of every `StreakView`. PR 3's stub sends only `sent` and `resting`.
public struct PounceState: Codable, Equatable, Sendable {
    public struct Waiting: Codable, Equatable, Sendable {
        public var id: String
        public var target: PounceTarget

        public init(id: String, target: PounceTarget) {
            self.id = id
            self.target = target
        }
    }

    /// My latest pounce on them is out and unanswered, this hour.
    public var sent: Bool
    /// I can't pounce on them right now (the sleeping bell).
    public var resting: Bool
    /// My pounce landed in their quiet hours (the moon).
    public var quiet: Bool
    /// Their answer to my latest pounce, this hour.
    public var answer: PounceAnswer?
    /// The table their Play went to.
    public var code: String?
    /// Their unanswered pounce on me, this hour.
    public var waiting: Waiting?

    public init(
        sent: Bool = false, resting: Bool = false, quiet: Bool = false, answer: PounceAnswer? = nil,
        code: String? = nil, waiting: Waiting? = nil
    ) {
        self.sent = sent
        self.resting = resting
        self.quiet = quiet
        self.answer = answer
        self.code = code
        self.waiting = waiting
    }

    public static let none = PounceState()

    private enum CodingKeys: String, CodingKey { case sent, resting, quiet, answer, code, waiting }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = try c.decodeIfPresent(Bool.self, forKey: .sent) ?? false
        resting = try c.decodeIfPresent(Bool.self, forKey: .resting) ?? false
        quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
        answer = try? c.decodeIfPresent(PounceAnswer.self, forKey: .answer)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        // A waiting pounce this build can't read is as good as none.
        waiting = try? c.decodeIfPresent(Waiting.self, forKey: .waiting)
    }
}

/// `POST /v1/pounces`: the pounce's id, and for a Messages pounce its link.
public struct PounceSent: Codable, Equatable, Sendable {
    public var id: String
    public var link: URL?

    public init(id: String, link: URL?) {
        self.id = id
        self.link = link
    }
}

/// `GET /v1/pounces/links/{token}`: who sent a Messages pounce, and what it asks for.
public struct LinkPounce: Codable, Equatable, Sendable {
    public var id: String
    public var from: PushFace
    public var target: PounceTarget

    public init(id: String, from: PushFace, target: PounceTarget) {
        self.id = id
        self.from = from
        self.target = target
    }
}

/// A pounce answer this phone owes the server: kept on disk before it's sent, so a background
/// action that iOS cut short, or one sent offline, goes out at the next launch (§12.5).
public struct PendingAnswer: Codable, Equatable, Sendable {
    public var id: String
    public var answer: PounceAnswer
    /// A "you pick" Play's table code, or `new`.
    public var choice: String?
    /// A Messages pounce's token.
    public var link: String?
    /// The local person answering (`?person=`).
    public var person: String?

    public init(id: String, answer: PounceAnswer, choice: String?, link: String?, person: String?) {
        self.id = id
        self.answer = answer
        self.choice = choice
        self.link = link
        self.person = person
    }
}
