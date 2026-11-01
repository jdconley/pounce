#if DEBUG
import Foundation
import PounceKit

/// DEBUG launch argument `-demo <lobby|table|celebrate|curtain>`: opens a room fed by a fake
/// socket that sends one `DemoFixtures` snapshot, so the real screens render with no server.
/// `other` is the table on another seat's turn (ring glow + paw marker, dimmed hand).
/// `celebrate` (Task 18) and `curtain` (Task 19) show their table until those land.
enum DemoMode: String {
    case lobby, table, other, celebrate, curtain

    static func from(arguments: [String] = CommandLine.arguments) -> DemoMode? {
        guard let i = arguments.firstIndex(of: "-demo"), arguments.indices.contains(i + 1) else { return nil }
        return DemoMode(rawValue: arguments[i + 1])
    }

    var room: RoomView {
        switch self {
        case .lobby: return DemoFixtures.lobby()
        case .table: return DemoFixtures.table(seats: 4, mySeat: 0, phase: 2)
        case .other:
            var room = DemoFixtures.table(seats: 4, mySeat: 0, phase: 2)
            room.game?.turn = 2
            return room
        case .celebrate: return DemoFixtures.table(seats: 4, mySeat: 0, phase: 9)
        case .curtain: return DemoFixtures.curtain()
        }
    }
}

/// A room socket that connects at once, sends one snapshot and ignores everything sent to it.
actor DemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let room: RoomView

    init(room: RoomView) {
        self.room = room
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
    }

    func send(_ m: ClientMessage) async throws {}

    func reconnectNow() async {}

    func stop() async {
        continuation.finish()
    }
}
#endif
