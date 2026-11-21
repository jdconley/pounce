import Foundation

/// The Daily Dish board a TV shows (docs/daily-protocol.md, "A board on the TV"): a random token
/// naming no one, kept for 30 days so the TV opens straight to the board every evening.
public struct KeptBoard: Codable, Equatable, Sendable {
    /// How long a TV keeps its board: the server's own limit.
    public static let days = 30

    public let token: String
    public let until: Date

    public init(token: String, until: Date) {
        self.token = token
        self.until = until
    }

    /// A token a phone just linked, kept for 30 days from `now`.
    public static func fresh(_ token: String, now: Date) -> KeptBoard {
        KeptBoard(token: token, until: now.addingTimeInterval(TimeInterval(days) * 86_400))
    }

    /// Still worth opening at `now`: a well-formed token (22 base64url characters) that hasn't
    /// run out.
    public func live(at now: Date) -> Bool {
        token.utf8.count == 22
            && token.utf8.allSatisfy { ("A"..."Z").contains(Character(UnicodeScalar($0))) || ("a"..."z").contains(Character(UnicodeScalar($0))) || ("0"..."9").contains(Character(UnicodeScalar($0))) || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_") }
            && now <= until
    }
}

/// Where a TV keeps its board token. Async: the real one is the Keychain (docs/main-thread.md).
public protocol BoardKeeping: Sendable {
    func load() async -> KeptBoard?
    /// Keeps `board`, or forgets the one kept (nil).
    func keep(_ board: KeptBoard?) async
}

/// The board token in the Keychain, on this device only.
public actor KeychainBoardKeep: BoardKeeping {
    private let item: KeychainItem

    public init(item: KeychainItem = KeychainItem(service: "com.conleychaos.play.tv", account: "board")) {
        self.item = item
    }

    public func load() async -> KeptBoard? {
        guard let data = await item.load() else { return nil }
        return try? JSONDecoder().decode(KeptBoard.self, from: data)
    }

    public func keep(_ board: KeptBoard?) async {
        guard let board, let data = try? JSONEncoder().encode(board) else {
            await item.delete()
            return
        }
        await item.save(data)
    }
}

/// Keeps the board token for the process only (tests, demos).
public actor MemoryBoardKeep: BoardKeeping {
    private var kept: KeptBoard?

    public init(_ kept: KeptBoard? = nil) { self.kept = kept }

    public func load() -> KeptBoard? { kept }
    public func keep(_ board: KeptBoard?) { kept = board }
}
