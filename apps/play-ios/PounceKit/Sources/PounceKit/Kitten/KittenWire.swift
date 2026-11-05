import Foundation

// Parent consent for kittens (consent design §2; plan decisions 1, 33, 36–38): the wire types of
// play-api's `/v1/kittens` routes, and the pure rules the screens draw from. No player ids reach
// the app: a kitten is a `k_` id, a person is a pair id.

/// The kitten's consent as its own device sees it (`GET /v1/kittens/me`).
public struct KittenStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        /// No parent linked yet.
        case none
        /// Linked, no text sent (or it was revoked).
        case pending
        /// A parent's text is out, not confirmed yet.
        case texted
        case consented
    }

    public var state: State
    public var linked: Bool
    /// Pair ids the kitten may hear from.
    public var approved: [String]

    public init(state: State, linked: Bool, approved: [String]) {
        self.state = state
        self.linked = linked
        self.approved = approved
    }

    public static let unlinked = KittenStatus(state: .none, linked: false, approved: [])

    public var consented: Bool { state == .consented }

    /// The padlock on a person (plan decision 38): once linked, everyone the parent didn't
    /// approve; an unlinked kitten pounces as before.
    public func locks(pair: String) -> Bool { linked && !approved.contains(pair) }
}

/// A six-digit code for a grown-up to enter, and when it stops working (epoch ms).
public struct LinkCode: Codable, Equatable, Sendable {
    public var code: String
    public var expiresAt: Double

    public init(code: String, expiresAt: Double) {
        self.code = code
        self.expiresAt = expiresAt
    }

    public func fresh(at now: Date) -> Bool { now.timeIntervalSince1970 * 1000 < expiresAt }
}

/// One person a kitten plays with, on the parent's panel.
public struct KittenPerson: Codable, Equatable, Sendable, Identifiable {
    public var pair: String
    public var name: String
    public var cat: Int
    public var approved: Bool
    /// A linked parent: always approved.
    public var parent: Bool

    public var id: String { pair }

    public init(pair: String, name: String, cat: Int, approved: Bool, parent: Bool) {
        self.pair = pair
        self.name = name
        self.cat = cat
        self.approved = approved
        self.parent = parent
    }
}

/// One kitten on the parent's Kittens panel (`GET /v1/kittens`).
public struct ParentKitten: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable {
        case pending, texted, on
    }

    public enum Mode: String, Codable, Sendable {
        /// The parent's own toggles.
        case parent
        /// Apple's Communication Limits decide; the toggles only show them.
        case apple
    }

    public var id: String
    public var name: String
    public var cat: Int
    public var state: State
    public var mode: Mode
    public var people: [KittenPerson]

    public init(id: String, name: String, cat: Int, state: State, mode: Mode, people: [KittenPerson]) {
        self.id = id
        self.name = name
        self.cat = cat
        self.state = state
        self.mode = mode
        self.people = people
    }

    /// The approved pairs after flipping one toggle. Parents stay on; nothing changes in Apple mode.
    public func approvals(toggling pair: String) -> [String]? {
        guard mode == .parent, let person = people.first(where: { $0.pair == pair }), !person.parent else { return nil }
        return people.filter { $0.pair == pair ? !$0.approved : $0.approved && !$0.parent }.map(\.pair)
    }
}

/// What the kitten's bell in the gear sheet shows (plan decision 33). Pictures only.
public enum KittenBell: Equatable, Sendable {
    /// A padlocked bell, and the code to show a grown-up when one is fresh.
    case locked(code: String?)
    /// A padlocked bell with no code: the significant change is owed or a parent said no.
    case held
    /// A sleeping bell: linked, waiting on the parent.
    case asleep
    /// The normal bell: consent is on.
    case on

    public static func of(status: KittenStatus?, held: Bool, code: LinkCode?, now: Date) -> KittenBell {
        if status?.consented == true { return .on }
        if held { return .held }
        if let status, status.linked { return .asleep }
        return .locked(code: code.flatMap { $0.fresh(at: now) ? $0.code : nil })
    }
}

/// The parent's six-digit keypad: up to six digits, no default.
public struct LinkCodeEntry: Equatable, Sendable {
    public static let length = 6
    public private(set) var digits = ""

    public init() {}

    public mutating func type(_ digit: Int) {
        guard (0...9).contains(digit), digits.count < Self.length else { return }
        digits.append(String(digit))
    }

    public mutating func delete() {
        if !digits.isEmpty { digits.removeLast() }
    }

    public mutating func clear() { digits = "" }

    public var complete: Bool { digits.count == Self.length }
}

/// The parent's mobile number as typed: digits, spaces, dashes, dots, brackets and one leading plus.
public enum PhoneEntry {
    public static let maxLength = 24

    /// The text with anything else dropped, capped.
    public static func clean(_ text: String) -> String {
        var out = ""
        for (i, ch) in text.enumerated() {
            if ch.isASCII && ch.isNumber || " -().".contains(ch) || (ch == "+" && i == 0 && out.isEmpty) { out.append(ch) }
        }
        return String(out.prefix(maxLength))
    }

    /// Worth sending: a US number of 10 digits (11 with the 1), or `+` and 8 to 15 digits. The
    /// server checks again.
    public static func plausible(_ text: String) -> Bool {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return (8...15).contains(digits.count) }
        return digits.count == 10 || (digits.count == 11 && digits.hasPrefix("1"))
    }
}
