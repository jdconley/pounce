import Foundation
import Testing
@testable import PounceKit

/// A TV table, read by the app as shipped today: its snapshots say `screen: true`, a field the app
/// doesn't know, and the server relays `aim` messages, a kind it doesn't know. The first is
/// ignored, the second skipped. No PounceKit source changes with these tests: they pin the decoder
/// as it was before the TV. The samples are the play-api's `fixtures/protocol/screen-server-messages.json`.
@Suite struct ScreenProtocolTests {
    private func samples() throws -> [String: Any] {
        let data = try Data(contentsOf: Fixtures.url("protocol/screen-server-messages.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A sample as the wire has it, with `edit` applied to its top level first.
    private func json(_ name: String, edit: (inout [String: Any]) -> Void = { _ in }) throws -> String {
        var message = try #require(try samples()[name] as? [String: Any], "no sample \(name)")
        edit(&message)
        return try String(data: JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func withoutScreen(_ name: String) throws -> String {
        try json(name) { message in
            var room = message["room"] as! [String: Any]
            #expect(room.removeValue(forKey: "screen") as? Bool == true, "\(name) says screen: true")
            message["room"] = room
        }
    }

    private func room(_ text: String) throws -> RoomView {
        guard case .snapshot(_, _, let room) = try Codec.decode(text) else { throw Fixtures.FixtureError.malformed("not a snapshot") }
        return room
    }

    @Test func snapshotWithScreenDecodesAsBefore() throws {
        for name in ["snapshot", "tilesSnapshot"] {
            let withScreen = try room(try json(name))
            #expect(try withScreen == room(try withoutScreen(name)), "\(name)")
            #expect(withScreen.status == .playing, "\(name)")
        }
        #expect(try room(try json("snapshot")).gameId != GameID.tiles)
        #expect(try room(try json("tilesSnapshot")).gameId == GameID.tiles)
    }

    @Test func aimIsNotAMessageTheDecoderKnows() throws {
        for name in ["aim", "tilesAim", "aimClear"] {
            let text = try json(name)
            #expect(text.contains(#""t":"aim""#), "\(name)")
            #expect(throws: (any Error).self, "\(name)") { _ = try Codec.decode(text) }
        }
    }

    @Test(.timeLimit(.minutes(1))) func socketSkipsAim() async throws {
        let first = try json("snapshot")
        let last = try json("tilesSnapshot")
        let conn = FakeConnection(frames: [first, try json("aim"), try json("tilesAim"), try json("aimClear"), last])
        let connector = FakeConnector([.connection(conn)])
        let credential = DeviceCredential(deviceId: "dev-1", token: "tok-1")
        let clock = FakeClock()
        let sleeper = FakeSleeper()
        let socket = RoomSocket(
            code: "BCDFG", config: APIConfig(baseURL: URL(string: "http://localhost:8787")!), credential: { credential },
            connector: connector, tick: sleeper.pingInterval, clock: { clock.now }, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)

        await socket.start()

        // Two snapshots and nothing between them: no event for an aim, no disconnect, no second connect.
        #expect(await reader.next(4) == [.connecting, .connected, .message(try Codec.decode(first)), .message(try Codec.decode(last))])
        #expect(!conn.isClosed)
        #expect(connector.calls.count == 1)
        await socket.stop()
    }
}
