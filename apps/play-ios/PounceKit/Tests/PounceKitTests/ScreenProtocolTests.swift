import Foundation
import Testing
@testable import PounceKit

/// A TV table, read by the app: its snapshots say `screen: true` and the server relays `aim`
/// messages. The samples are the play-api's `fixtures/protocol/screen-server-messages.json`. An app
/// as shipped before the TV still skips what it doesn't know: an unknown message type fails to
/// decode (the socket skips that frame) and unknown snapshot keys are ignored.
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

    @Test func snapshotsCarryScreen() throws {
        for name in ["snapshot", "tilesSnapshot"] {
            let withScreen = try room(try json(name))
            #expect(withScreen.screen == true, "\(name)")
            #expect(withScreen.status == .playing, "\(name)")
            var without = withScreen
            without.screen = nil
            #expect(try room(try withoutScreen(name)) == without, "\(name): screen is the only difference")
        }
        #expect(try room(try json("snapshot")).gameId != GameID.tiles)
        #expect(try room(try json("tilesSnapshot")).gameId == GameID.tiles)
    }

    @Test func aimsDecode() throws {
        #expect(try Codec.decode(try json("aim")) == .aim(seat: 0, aim: .target(seat: 1, group: 0)))
        #expect(try Codec.decode(try json("tilesAim")) == .aim(seat: 0, aim: .table([[82, 45, 87]])))
        #expect(try Codec.decode(try json("aimClear")) == .aim(seat: 0, aim: nil))
    }

    @Test func aMessageOfAnUnknownTypeStillFailsToDecode() throws {
        let text = try json("aim") { $0["t"] = "futureThing" }
        #expect(throws: (any Error).self) { _ = try Codec.decode(text) }
    }

    @Test func unknownSnapshotKeysAreStillIgnored() throws {
        let plain = try json("snapshot")
        let extra = try json("snapshot") { message in
            var room = message["room"] as! [String: Any]
            room["somethingNew"] = ["a": 1]
            message["room"] = room
        }
        #expect(try room(extra) == room(plain))
    }

    @Test func aimEncodesAsTheContractSays() throws {
        func wire(_ message: ClientMessage) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return String(data: try encoder.encode(message), encoding: .utf8)!
        }
        #expect(try wire(.aim(seat: 1, aim: .target(seat: 0, group: 1))) == #"{"aim":{"target":{"group":1,"seat":0}},"seat":1,"t":"aim"}"#)
        #expect(try wire(.aim(seat: 1, aim: .table([[12, 13, 14], [40, 41, 42, 43]]))) == #"{"aim":{"table":[[12,13,14],[40,41,42,43]]},"seat":1,"t":"aim"}"#)
        #expect(try wire(.aim(seat: 1, aim: nil)) == #"{"seat":1,"t":"aim"}"#)
    }

    @Test(.timeLimit(.minutes(1))) func socketSkipsAMessageItDoesNotKnow() async throws {
        let first = try json("snapshot")
        let last = try json("tilesSnapshot")
        let unknown = try json("aim") { $0["t"] = "futureThing" }
        let conn = FakeConnection(frames: [first, unknown, unknown, last])
        let connector = FakeConnector([.connection(conn)])
        let credential = DeviceCredential(deviceId: "dev-1", token: "tok-1")
        let clock = FakeClock()
        let sleeper = FakeSleeper()
        let socket = RoomSocket(
            code: "BCDFG", config: APIConfig(baseURL: URL(string: "http://localhost:8787")!), credential: { credential },
            connector: connector, tick: sleeper.pingInterval, clock: { clock.now }, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)

        await socket.start()

        // Two snapshots and nothing between them: no event for the unknown type, no disconnect, no second connect.
        #expect(await reader.next(4) == [.connecting, .connected, .message(try Codec.decode(first)), .message(try Codec.decode(last))])
        #expect(!conn.isClosed)
        #expect(connector.calls.count == 1)
        await socket.stop()
    }
}
