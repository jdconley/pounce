import Foundation

/// Shared protocol fixtures committed by the play-api package
/// (`apps/play-api/fixtures/`). Each protocol file is a JSON array of
/// `{ "name": String, "message": Object }`.
enum Fixtures {
    enum FixtureError: Error { case malformed(String) }

    /// Resolves `relative` under `apps/play-api/fixtures/`, walking up from this file:
    /// PounceKitTests -> Tests -> PounceKit -> play-ios -> apps.
    static func url(_ relative: String) -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { dir.deleteLastPathComponent() }
        return dir
            .appendingPathComponent("play-api")
            .appendingPathComponent("fixtures")
            .appendingPathComponent(relative)
    }

    static func serverMessages() throws -> [(name: String, json: String)] {
        try messages(in: "protocol/server-messages.json")
    }

    static func clientMessages() throws -> [(name: String, json: String)] {
        try messages(in: "protocol/client-messages.json")
    }

    /// The streak protocol samples PR 3 kept apart, so the counts above stay as they were.
    static func streakServerMessages() throws -> [(name: String, json: String)] {
        try messages(in: "protocol/streaks-server-messages.json")
    }

    static func streakClientMessages() throws -> [(name: String, json: String)] {
        try messages(in: "protocol/streaks-client-messages.json")
    }

    private static func messages(in relative: String) throws -> [(name: String, json: String)] {
        let data = try Data(contentsOf: url(relative))
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FixtureError.malformed(relative)
        }
        return try entries.map { entry in
            guard let name = entry["name"] as? String, let message = entry["message"] else {
                throw FixtureError.malformed("\(relative): entry without name/message")
            }
            let raw = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
            guard let json = String(data: raw, encoding: .utf8) else {
                throw FixtureError.malformed("\(relative): \(name) is not UTF-8")
            }
            return (name, json)
        }
    }
}
