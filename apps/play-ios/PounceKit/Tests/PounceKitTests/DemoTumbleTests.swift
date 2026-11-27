#if DEBUG
import Foundation
import Testing
@testable import PounceKit

/// The demo room plays whole rounds against this device's table model, with junk and tricks both
/// ways, and every replayed box stays the room's own, cell for cell.
@MainActor @Suite struct DemoTumbleTests {
    final class Wire {
        var toRoom: [ClientMessage] = []
    }

    @Test func roundsPlayToTheEndAndEveryReplayedBoxMatches() {
        var options = TumbleDemoRoom.Options()
        options.seats = 4
        options.held = [.hairball, .swipe]
        options.think = 300...600
        options.sloppy = 0.1
        options.stack = 4
        var now = 1_000_000.0
        let room = TumbleDemoRoom(options, now: now)
        let wire = Wire()
        let table = TumbleTable { wire.toRoom.append($0) }
        func deliver(_ messages: [ServerMessage]) {
            for m in messages {
                switch m {
                case .snapshot(_, _, let r): table.update(room: r, now: now)
                case .tumble(let live): table.receive(live, now: now)
                default: break
                }
            }
        }
        deliver(room.connect())
        var rounds = Set<Int>()
        var syncs = 0
        var used = false
        var inputs = 0
        var plan: (r: Int, n: Int, spot: TumbleSpot)?
        for frame in 0..<(60 * 240) {
            now += 1000.0 / 60
            deliver(room.tick(now: now))
            table.step(now: now)
            if let local = table.local, let toy = local.toy, frame % 4 == 0 {
                if plan?.n != toy.n || plan?.r != local.r { plan = TumblePlanner.best(local).map { (local.r, toy.n, $0) } }
                guard let target = plan?.spot else { continue }
                inputs += 1
                switch TumblePlanner.next(local, toward: target) {
                case .turn: local.turn(1)
                case .move(let dx): local.move(dx)
                case .drop: local.drop(now)
                case nil: break
                }
                if !used, !local.box.held.isEmpty {
                    used = local.use(slot: 0, on: 1, now: now) != nil
                }
            }
            let out = wire.toRoom
            wire.toRoom.removeAll()
            for m in out {
                if case .tumble(_, let ev) = m, ev.isEmpty { syncs += 1 }
                deliver(room.receive(m, now: now))
            }
            if let t = room.room.tumble, t.status == .between || t.status == .over { rounds.insert(t.r) }
            if room.room.tumble?.status == .over { break }
            // Every replayed box is the room's.
            if frame % 120 == 0, let replay = table.replay, replay.r == room.room.tumble?.r {
                for s in 1..<4 where replay.box(s) != room.box(s) { Issue.record("seat \(s) frame \(frame) r \(replay.r)\n\(TumbleText.of(replay.box(s)!).cells.joined(separator: "\n"))\nroom\n\(TumbleText.of(room.box(s)).cells.joined(separator: "\n"))"); return }
                if table.local?.isQuiet == true { #expect(table.local?.box == room.box(0), "own box frame \(frame)") }
            }
        }
        #expect(rounds.count >= 2, "rounds ended: \(rounds)")
        #expect(used)
        #expect(syncs == 0, "no box split from the room's")
        #expect(inputs > 100)
    }
}
#endif
