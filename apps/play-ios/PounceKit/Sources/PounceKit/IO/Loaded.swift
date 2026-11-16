import Foundation

/// A file and what it held when it was read, off the caller's actor. The launch reads every
/// store's file at once this way, then the stores are built on the main actor from the values
/// (docs/main-thread.md: load once, before the first screen).
public struct Loaded<Value: Codable & Sendable>: Sendable {
    public let file: JSONFile<Value>
    public let value: Value?

    public init(file: JSONFile<Value>, value: Value?) {
        self.file = file
        self.value = value
    }

    @concurrent
    public static func read(_ file: JSONFile<Value>) async -> Loaded {
        Loaded(file: file, value: await file.read())
    }
}
