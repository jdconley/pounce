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

    /// Resolves `relative` under this test target's own `Fixtures/` folder.
    static func localURL(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(relative)
    }

    /// The tile game's protocol fixtures (`Fixtures/tiles/tiles-*-messages.json`): copies of the
    /// server's `apps/play-api/fixtures/protocol/tiles-server-messages.json` and
    /// `tiles-client-messages.json` as of commit 2bb0cee on `claude/tiles-rooms` (the server's
    /// rooms and wire for the game, PR 64), generated there from a real room. Once that branch is
    /// on main these two read the shared files (`url("protocol/tiles-…")`) and the copies go.
    static func tilesServerMessages() throws -> [(name: String, json: String)] {
        try messages(at: localURL("tiles/tiles-server-messages.json"))
    }

    static func tilesClientMessages() throws -> [(name: String, json: String)] {
        try messages(at: localURL("tiles/tiles-client-messages.json"))
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

    /// The APNs bodies play-api sends (`fixtures/push/payloads.json`, PR 5): each entry is
    /// `{ "name", "collapseId", "priority", "body" }`, the body as `userInfo` would hold it.
    static func pushPayloads() throws -> [(name: String, collapseId: String, body: [String: Any])] {
        let relative = "push/payloads.json"
        let data = try Data(contentsOf: url(relative))
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FixtureError.malformed(relative)
        }
        return try entries.map { entry in
            guard let name = entry["name"] as? String, let collapse = entry["collapseId"] as? String,
                  let body = entry["body"] as? [String: Any]
            else { throw FixtureError.malformed("\(relative): entry without name/collapseId/body") }
            return (name, collapse, body)
        }
    }

    private static func messages(in relative: String) throws -> [(name: String, json: String)] {
        try messages(at: url(relative))
    }

    private static func messages(at file: URL) throws -> [(name: String, json: String)] {
        let relative = file.lastPathComponent
        let data = try Data(contentsOf: file)
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
