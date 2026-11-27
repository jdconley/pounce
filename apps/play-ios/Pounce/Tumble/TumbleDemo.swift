#if DEBUG
import Foundation
import PounceKit

/// Toy Tumble's DEBUG demos (`-demo tumble-<name>`), on `TumbleDemoSocket`: a round against House
/// Cat boxes run by `TumbleDemoRoom` on the socket's own actor, so the real table plays with no
/// server.
/// - `tumble-play`: four seats, mid-round, two tricks in hand.
/// - `tumble-six`: six seats (five cats), for the busiest phone screen and the frame gate.
/// - `tumble-two`: one cat.
/// - `tumble-tv`: a TV shows the table: the minis are chips.
/// - `tumble-countdown`: the 3-2-1 before a round.
/// - `tumble-lobby`: the lobby, three seats, with the Cats pills.
/// - `tumble-junk`: boxes start four rows deep, so clears and junk come at once (the screenshots).
/// `-tumble-autoplay` makes this phone's box play itself through the scene's own input calls.
enum TumbleDemo {
    static func options(_ mode: DemoMode) -> TumbleDemoRoom.Options {
        var o = TumbleDemoRoom.Options()
        o.held = [.hairball, .scoop]
        switch mode {
        case .tumbleSix: o.seats = 6
        case .tumbleTwo: o.seats = 2
        case .tumbleCountdown: o.playing = false
        case .tumbleSheet:
            o.sheet = true
            o.held = TumbleTrick.allCases.prefix(6).map { $0 }
        case .tumbleJunk:
            o.stack = 4
            o.held = [.hairball, .swipe, .nap, .bath]
        default: break
        }
        // UI tests and the frame gate: a cat thinks fast so things happen.
        if CommandLine.arguments.contains("-tumble-busy") {
            o.think = 500...900
            o.sloppy = 0.15
        }
        return o
    }

    static func room(_ mode: DemoMode) -> RoomView {
        if mode == .tumbleLobby { return lobby() }
        var room = TumbleDemoRoom(options(mode), now: TumbleTable.now()).room
        if mode == .tumbleTV { room.screen = true }
        return room
    }

    static func lobby() -> RoomView {
        RoomView(
            code: "TUMBLE", name: "Toy night", status: .lobby, youAreHost: true,
            seats: [
                SeatView(kind: .human, person: Person(id: "p0", name: "Sam", cat: 0), yours: true, presence: .awake),
                SeatView(kind: .human, person: Person(id: "p1", name: "Mia", cat: 2), presence: .awake),
                SeatView(kind: .bot), SeatView(kind: .open), SeatView(kind: .closed), SeatView(kind: .closed),
            ],
            gameId: GameID.tumble, options: RoomOptions(cats: .easy))
    }

    static func socket(_ mode: DemoMode) -> any RoomSocketing {
        if mode == .tumbleLobby { return DemoSocket(room: mode.room) }
        return TumbleDemoSocket(options: options(mode), tv: mode == .tumbleTV)
    }
}

#endif
