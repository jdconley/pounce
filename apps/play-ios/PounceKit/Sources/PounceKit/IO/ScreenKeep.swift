import Foundation

/// What a TV keeps between launches: the table it shows, so it goes straight back to it, and
/// its own sound setting. Nothing else about a TV persists but its device credential (Keychain).
public struct ScreenKept: Equatable, Sendable {
    public var room: String?
    public var soundOn: Bool

    public init(room: String? = nil, soundOn: Bool = true) {
        self.room = room
        self.soundOn = soundOn
    }
}

/// Where a TV keeps `ScreenKept`. Async: the real one is `UserDefaults`, read and written off the
/// main thread (docs/main-thread.md).
public protocol ScreenKeeping: Sendable {
    func load() async -> ScreenKept
    func keep(room: String?) async
    func keep(soundOn: Bool) async
}

/// A TV's kept values in `UserDefaults`, on this actor: never on the main thread.
public actor DefaultsScreenKeep: ScreenKeeping {
    private enum Key {
        static let room = "tv.room"
        static let soundOn = "tv.soundOn"
    }

    private let defaults: UserDefaults

    /// `suite` nil is the app's standard defaults.
    public init(suite: String? = nil) {
        defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> ScreenKept {
        let room = defaults.string(forKey: Key.room).flatMap { RoomCode.isValid($0) ? $0 : nil }
        return ScreenKept(room: room, soundOn: defaults.object(forKey: Key.soundOn) as? Bool ?? true)
    }

    public func keep(room: String?) {
        if let room, RoomCode.isValid(room) {
            defaults.set(room, forKey: Key.room)
        } else {
            defaults.removeObject(forKey: Key.room)
        }
    }

    public func keep(soundOn: Bool) {
        defaults.set(soundOn, forKey: Key.soundOn)
    }
}

/// Keeps nothing past the process (tests, previews).
public actor MemoryScreenKeep: ScreenKeeping {
    private var kept: ScreenKept

    public init(_ kept: ScreenKept = ScreenKept()) { self.kept = kept }

    public func load() -> ScreenKept { kept }
    public func keep(room: String?) { kept.room = room }
    public func keep(soundOn: Bool) { kept.soundOn = soundOn }
}
