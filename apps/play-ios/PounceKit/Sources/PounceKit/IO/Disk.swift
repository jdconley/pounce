import Foundation

// PounceKit's IO layer (docs/main-thread.md). The only code in the app, its extensions and
// PounceKit that may touch the disk or the Keychain. Everything here is `@concurrent` or on an
// actor, so the compiler never lets it run on the main actor; `scripts/main-thread-lint.swift`
// keeps every blocking call in this folder and checks its shape.

/// Whole-file reads and atomic writes, always off the caller's actor.
public enum Disk {
    /// The file's bytes; nil when it is missing or unreadable.
    @concurrent
    public static func read(_ url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }

    /// Writes `data` atomically, making the directory first. False when it couldn't.
    @discardableResult
    @concurrent
    public static func write(_ data: Data, to url: URL) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @concurrent
    public static func remove(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent
    public static func exists(_ url: URL) async -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The App Group's container, or nil where the group isn't available (an unsigned build, tests).
    @concurrent
    public static func appGroupDirectory(_ group: String) async -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    /// A bundled file's bytes (a How to play poster, a sound), read off the caller's actor.
    @concurrent
    public static func resource(_ name: String, ofType type: String, in bundle: Bundle = .main) async -> Data? {
        guard let url = bundle.url(forResource: name, withExtension: type) else { return nil }
        return try? Data(contentsOf: url)
    }
}
