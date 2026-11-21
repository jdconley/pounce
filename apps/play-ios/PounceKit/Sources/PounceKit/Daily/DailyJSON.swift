import Foundation

/// A piece of JSON the Dish's host carries without knowing its shape: a game's public puzzle, its
/// public state, a move, a reveal. Each game decodes its own types from it (`decoded(as:)`), off
/// the main thread (the run session decodes before it hands anything to a game).
public enum DailyJSON: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([DailyJSON])
    case object([String: DailyJSON])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([DailyJSON].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: DailyJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Any `Encodable` as JSON (a game's move).
    public init(_ value: some Encodable) throws {
        self = try JSONDecoder().decode(DailyJSON.self, from: JSONEncoder().encode(value))
    }

    /// This JSON as a game's own type.
    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    /// The value under `key`, for an object.
    public subscript(key: String) -> DailyJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}
