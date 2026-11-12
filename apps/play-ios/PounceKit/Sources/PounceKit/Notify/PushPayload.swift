import Foundation

/// What a push is about (play-api `NotifyKind`, plus the background `dismiss`). Anything this
/// build doesn't know is `unknown`, which still opens its `code` like the legacy payload.
public enum PushKind: String, Sendable {
    case yourMove = "your_move"
    case reminder
    case lastChance = "last_chance"
    case freshStart = "fresh_start"
    case goingQuiet = "going_quiet"
    case nap, winback, paused, milestone
    case playAgain = "play_again"
    case pounce
    case pounceAnswered = "pounce_answered"
    /// Someone at the table asks for your move (YOUR_MOVE: Play, In an hour).
    case nudge
    case dismiss
    /// Parent consent's confirmation on the parent's own device (consent design D6).
    case consent
    /// Someone asked this device to a table its version can't draw (app updates design §5).
    case update
    case unknown
}

/// The notification categories the app registers (spec §12.5).
public enum PushCategory: String, CaseIterable, Sendable {
    case yourMove = "YOUR_MOVE"
    case reminder = "REMINDER"
    case pounce = "POUNCE"
    /// Parent consent's confirmation: Revoke.
    case consent = "CONSENT"
    case status = "STATUS"
}

/// Who a push is from: their name and cat.
public struct PushFace: Codable, Hashable, Sendable {
    public var name: String
    public var cat: Int

    public init(name: String, cat: Int) {
        self.name = name
        self.cat = cat
    }
}

/// What a pounce asks for (§12.4): a table you share, a new game, or "you pick".
/// On the wire: `{"table": "<CODE>"}`, `"new"` or `"pick"`.
public enum PounceTarget: Codable, Hashable, Sendable {
    case table(String)
    case new
    case pick

    private struct Table: Codable { let table: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let word = try? c.decode(String.self) {
            switch word {
            case "new": self = .new
            case "pick": self = .pick
            default: throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown target \(word)")
            }
            return
        }
        let table = try c.decode(Table.self).table
        guard RoomCode.isValid(table) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad table code")
        }
        self = .table(table)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .table(let code): try c.encode(Table(table: code))
        case .new: try c.encode("new")
        case .pick: try c.encode("pick")
        }
    }
}

/// Play, In a bit, or Not now (§12.4).
public enum PounceAnswer: String, Codable, Hashable, Sendable {
    case play, later, no
}

/// A push's top-level fields as play-api sends them (§12.7), read from `userInfo`. Every field
/// but `kind` is optional, and a field that doesn't parse is left out rather than failing the
/// whole payload: an older app must never drop a push it half-understands.
public struct PushPayload: Equatable, Sendable {
    public struct Pounce: Equatable, Sendable {
        public var id: String
        public var target: PounceTarget?
        public var answer: PounceAnswer?

        public init(id: String, target: PounceTarget? = nil, answer: PounceAnswer? = nil) {
            self.id = id
            self.target = target
            self.answer = answer
        }
    }

    /// The pair's streak block (`StreakBlock` on the server), for widgets (PR 6).
    public struct Streak: Equatable, Sendable {
        public var pair: String
        public var count: Int
        public var me: Bool
        public var them: Bool
        public var naps: Int
        public var myMove: [String]
        public var theirMove: [String]
    }

    public var kind: PushKind
    public var category: PushCategory?
    public var title: String?
    public var body: String?
    public var threadId: String?
    /// The table, when it is a well-formed room code.
    public var code: String?
    public var from: PushFace?
    public var pounce: Pounce?
    public var streak: Streak?
    public var pair: String?
    /// A consent push's kitten (`k_…`), the public id the Kittens panel uses.
    public var kitten: String?
    /// An update push's table (`update.code`). Never the top-level `code`: an app from before
    /// update pushes would open it, and be told there is no such table.
    public var updateCode: String?

    /// Nil only when `userInfo` has nothing of ours at all.
    public init?(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let rawKind = userInfo["kind"] as? String
        guard rawKind != nil || userInfo["code"] != nil || aps != nil else { return nil }
        kind = rawKind.flatMap(PushKind.init(rawValue:)) ?? .unknown
        category = (aps?["category"] as? String).flatMap(PushCategory.init(rawValue:))
        title = alert?["title"] as? String
        body = alert?["body"] as? String
        threadId = aps?["thread-id"] as? String
        code = (userInfo["code"] as? String).flatMap { RoomCode.isValid($0) ? $0 : nil }
        from = Self.face(userInfo["from"])
        pounce = Self.pounce(userInfo["pounce"])
        streak = Self.streak(userInfo["streak"])
        pair = userInfo["pair"] as? String
        kitten = (userInfo["kitten"] as? String).flatMap { Self.isKittenId($0) ? $0 : nil }
        updateCode = ((userInfo["update"] as? [String: Any])?["code"] as? String).flatMap { RoomCode.isValid($0) ? $0 : nil }
    }

    /// `k_` and base64url characters (play-api's `KID` has 22; the server checks it again).
    private static func isKittenId(_ s: String) -> Bool {
        guard s.hasPrefix("k_"), (3...66).contains(s.count) else { return false }
        return s.dropFirst(2).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    private static func int(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    private static func face(_ v: Any?) -> PushFace? {
        guard let o = v as? [String: Any], let name = o["name"] as? String, let cat = int(o["cat"]) else { return nil }
        return PushFace(name: name, cat: cat)
    }

    private static func pounce(_ v: Any?) -> Pounce? {
        guard let o = v as? [String: Any], let id = o["id"] as? String else { return nil }
        var target: PounceTarget?
        // `data(withJSONObject:)` raises (not throws) on a non-JSON value: check first.
        if let raw = o["target"], JSONSerialization.isValidJSONObject([raw]),
           let data = try? JSONSerialization.data(withJSONObject: [raw]) {
            target = (try? JSONDecoder().decode([PounceTarget].self, from: data))?.first
        }
        return Pounce(id: id, target: target, answer: (o["answer"] as? String).flatMap(PounceAnswer.init(rawValue:)))
    }

    private static func streak(_ v: Any?) -> Streak? {
        guard let o = v as? [String: Any], let pair = o["pair"] as? String, let count = int(o["count"]) else { return nil }
        return Streak(
            pair: pair, count: count, me: o["me"] as? Bool ?? false, them: o["them"] as? Bool ?? false,
            naps: int(o["naps"]) ?? 0, myMove: o["myMove"] as? [String] ?? [], theirMove: o["theirMove"] as? [String] ?? [])
    }
}
