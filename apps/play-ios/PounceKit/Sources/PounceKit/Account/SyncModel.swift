import Foundation

/// Any JSON value, as the server stores a synced setting.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            // Whole numbers go out without a fraction (epoch ms, cat indexes).
            if n.rounded() == n, abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
}

/// One synced value and when a device last wrote it (epoch ms on that device's clock).
public struct SyncEntry: Codable, Equatable, Sendable {
    public var v: JSONValue
    public var at: Int64

    public init(v: JSONValue, at: Int64) {
        self.v = v
        self.at = at
    }
}

public typealias SyncSection = [String: SyncEntry]

/// The synced sections of `/v1/me/state` (spec §13.1, "what syncs").
public enum SyncSectionName: String, CaseIterable, Codable, Sendable {
    case settings, tutorial, archive
}

/// A `PATCH /v1/me/state` body: only the sections present are sent.
public struct StatePatch: Codable, Equatable, Sendable {
    public var settings: SyncSection?
    public var tutorial: SyncSection?
    public var archive: SyncSection?

    public init(settings: SyncSection? = nil, tutorial: SyncSection? = nil, archive: SyncSection? = nil) {
        self.settings = settings
        self.tutorial = tutorial
        self.archive = archive
    }

    public subscript(name: SyncSectionName) -> SyncSection? {
        get {
            switch name {
            case .settings: settings
            case .tutorial: tutorial
            case .archive: archive
            }
        }
        set {
            switch name {
            case .settings: settings = newValue
            case .tutorial: tutorial = newValue
            case .archive: archive = newValue
            }
        }
    }

    public var isEmpty: Bool { SyncSectionName.allCases.allSatisfy { (self[$0] ?? [:]).isEmpty } }
}

/// A pass-and-play person another of the account's devices lists (spec §13.1, household).
public struct HouseholdPerson: Codable, Equatable, Hashable, Sendable {
    public var personId: String
    public var playerId: String
    public var name: String
    public var cat: Int

    public init(personId: String, playerId: String, name: String, cat: Int) {
        self.personId = personId
        self.playerId = playerId
        self.name = name
        self.cat = cat
    }
}

/// The player's own name and cat, and when a device last changed them.
public struct RemoteProfile: Codable, Equatable, Sendable {
    public var name: String
    public var cat: Int
    public var at: Int64

    public init(name: String, cat: Int, at: Int64) {
        self.name = name
        self.cat = cat
        self.at = at
    }
}

/// `GET /v1/me/state`.
public struct MeState: Codable, Equatable, Sendable {
    public var settings: SyncSection
    public var tutorial: SyncSection
    public var archive: SyncSection
    public var people: [HouseholdPerson]
    public var profile: RemoteProfile?

    public init(
        settings: SyncSection = [:], tutorial: SyncSection = [:], archive: SyncSection = [:],
        people: [HouseholdPerson] = [], profile: RemoteProfile? = nil
    ) {
        self.settings = settings
        self.tutorial = tutorial
        self.archive = archive
        self.people = people
        self.profile = profile
    }

    public subscript(name: SyncSectionName) -> SyncSection {
        switch name {
        case .settings: settings
        case .tutorial: tutorial
        case .archive: archive
        }
    }
}

/// Last writer wins per key, the server's rule (`mergeSection` in play-api).
public enum SyncMerge {
    /// What to send up (local is newer, or the server lacks the key) and what to take in (the
    /// server is newer, or only it has the key). A tie changes nothing on either side.
    public static func reconcile(local: SyncSection, remote: SyncSection) -> (push: SyncSection, apply: SyncSection) {
        var push: SyncSection = [:]
        var apply: SyncSection = [:]
        for (key, mine) in local {
            if let theirs = remote[key] {
                if mine.at > theirs.at { push[key] = mine } else if theirs.at > mine.at { apply[key] = theirs }
            } else {
                push[key] = mine
            }
        }
        for (key, theirs) in remote where local[key] == nil { apply[key] = theirs }
        return (push, apply)
    }

    /// Splits a patch into bodies the server takes: at most `maxKeys` keys per section and
    /// `maxBytes` of JSON each (the server caps a section at 64 keys and the body at 8 KB).
    public static func chunks(_ patch: StatePatch, maxKeys: Int = 64, maxBytes: Int = 7_500) -> [StatePatch] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func size(_ p: StatePatch) -> Int { (try? encoder.encode(p).count) ?? .max }

        var out: [StatePatch] = []
        var current = StatePatch()
        for name in SyncSectionName.allCases {
            for (key, entry) in (patch[name] ?? [:]).sorted(by: { $0.key < $1.key }) {
                var next = current
                next[name, default: [:]][key] = entry
                if (next[name]?.count ?? 0) > maxKeys || size(next) > maxBytes, !current.isEmpty {
                    out.append(current)
                    next = StatePatch()
                    next[name] = [key: entry]
                }
                current = next
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

extension StatePatch {
    fileprivate subscript(name: SyncSectionName, default fallback: SyncSection) -> SyncSection {
        get { self[name] ?? fallback }
        set { self[name] = newValue }
    }
}
