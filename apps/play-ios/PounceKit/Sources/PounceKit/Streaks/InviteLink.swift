import Foundation

/// The invite sheet's link (trophy room design §4): PR 5's Messages link pounce with target "new".
/// It's kept for an hour and shown again, so opening the sheet twice doesn't spend the server's
/// 3-an-hour limit; a new connection retires it (that link was probably the one used). A kitten's
/// device never makes one (§14.1): it shows a room code instead.
public struct InviteLink: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case link
        /// A room code and its QR, for in-person play only.
        case code
    }

    public var url: URL
    public var at: Date
    /// The connections when it was made.
    public var pairs: Set<String>

    public static let keepFor: TimeInterval = 60 * 60
    /// A link answers for a day (play-api `ANSWER_MS`).
    public static let lifetime: TimeInterval = 24 * 60 * 60

    public init(url: URL, at: Date, pairs: Set<String>) {
        self.url = url
        self.at = at
        self.pairs = pairs
    }

    public static func mode(_ limits: AgeLimits) -> Mode {
        limits.sharesLinks ? .link : .code
    }

    /// Shown again instead of making a new one: under an hour old, and no connection since.
    public func reusable(now: Date, pairs current: [String]) -> Bool {
        now.timeIntervalSince(at) < Self.keepFor && Set(current).isSubset(of: pairs)
    }

    /// While the bell rests (429) any link that can still be answered is better than none.
    public func usableWhileResting(now: Date) -> Bool {
        now.timeIntervalSince(at) < Self.lifetime
    }
}
