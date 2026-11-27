import Foundation
import Testing
@testable import PounceKit

/// Toy Tumble's wire against play-api's samples (`fixtures/protocol/tumble-*-messages.json`).
@Suite struct TumbleProtocolTests {
    private func server(_ name: String) throws -> TumbleMessage {
        let json = try #require(try Fixtures.tumbleServerMessages().first { $0.name == name }, "no fixture \(name)").json
        guard case .tumble(let m) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed(name) }
        return m
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        let x = try JSONSerialization.jsonObject(with: Data(a.utf8)) as! NSObject
        let y = try JSONSerialization.jsonObject(with: Data(b.utf8)) as! NSObject
        return x.isEqual(y)
    }

    @Test func decodesEveryServerSample() throws {
        let all = try Fixtures.tumbleServerMessages()
        #expect(all.count == 14)
        for (name, json) in all {
            let m = try Codec.decode(json)
            guard case .tumble = m else {
                Issue.record("\(name) is not a tumble message")
                continue
            }
        }
    }

    @Test func aRelayCarriesSeatSequenceAndEvents() throws {
        guard case .relay(let relay) = try server("tumble-relay") else { throw Fixtures.FixtureError.malformed("relay") }
        #expect(relay == TumbleRelay(r: 2, s: 1, q: 88, ev: [.move(n: 14, rot: 1, x: 5, y: 9), .land(n: 14, rot: 1, x: 5, y: 3, ms: 41250, landed: [])]))
    }

    @Test func everyHitKindDecodesToWhatTheEngineApplies() throws {
        guard case .hit(let junk) = try server("hit-junk") else { throw Fixtures.FixtureError.malformed("junk") }
        #expect(junk.k == .junk)
        #expect(junk.junk == TumbleWaiting(id: 31, rows: 2, gap: 7))
        #expect(junk.hit == nil)
        guard case .hit(let hairball) = try server("hit-hairball") else { throw Fixtures.FixtureError.malformed("hairball") }
        #expect(hairball.hit == .hairball(gap: 4))
        #expect(hairball.trick == .hairball)
        guard case .hit(let swipe) = try server("hit-swipe") else { throw Fixtures.FixtureError.malformed("swipe") }
        guard case .swipe(let shifts) = swipe.hit else { throw Fixtures.FixtureError.malformed("swipe payload") }
        #expect(shifts.count == 22)
        #expect(Array(shifts.prefix(5)) == [0, 1, -2, 2, -1])
        guard case .hit(let swap) = try server("hit-swap") else { throw Fixtures.FixtureError.malformed("swap") }
        guard case .swap(let cells, let tricks) = swap.hit else { throw Fixtures.FixtureError.malformed("swap payload") }
        #expect(cells.count == 264)
        #expect(tricks.count == 264)
        #expect(Array(cells.prefix(5)) == [5, 5, 5, 5, 0])
        for (name, want) in [("hit-catnip", TumbleHit.catnip), ("hit-scoop", .scoop), ("hit-settle", .settle), ("hit-nap", .nap), ("hit-bath", .bath)] {
            guard case .hit(let h) = try server(name) else { throw Fixtures.FixtureError.malformed(name) }
            #expect(h.hit == want, "\(name)")
        }
        guard case .hit(let napped) = try server("hit-napped") else { throw Fixtures.FixtureError.malformed("napped") }
        #expect(napped.k == .napped)
        #expect(napped.hit == nil)
        #expect(napped.trick == nil)
    }

    @Test func aSyncCarriesWholeBoxes() throws {
        guard case .sync(let sync) = try server("tumble-sync") else { throw Fixtures.FixtureError.malformed("sync") }
        #expect(sync.r == 2)
        #expect(sync.boxes.map(\.s) == [0, 1])
        let mine = sync.boxes[0]
        #expect(mine.q == 41)
        #expect(mine.waitingLeft == [1250])
        #expect(mine.napLeft == 6400)
        #expect(mine.status == .ok)
        #expect(mine.box.cells.count == 264)
        #expect(mine.box.waiting == [TumbleWaiting(id: 3, rows: 2, gap: 9)])
        #expect(sync.boxes[1].status == .lag)
        #expect(sync.boxes[1].catnipLeft == 3000)
    }

    @Test func seatLinks() throws {
        #expect(try server("tumble-seat-lag") == .seat(TumbleSeat(r: 2, s: 1, st: .lag)))
        #expect(try server("tumble-seat-ok") == .seat(TumbleSeat(r: 2, s: 1, st: .ok)))
    }

    @Test func encodesEveryClientSampleExactly() throws {
        let want: [String: ClientMessage] = [
            "tumble-move": .tumble(r: 2, ev: [.move(n: 14, rot: 1, x: 5, y: 9)]),
            "tumble-set-down": .tumble(r: 2, ev: [.move(n: 14, rot: 1, x: 5, y: 3), .land(n: 14, rot: 1, x: 5, y: 3, ms: 41250, landed: [])]),
            "tumble-set-down-landing": .tumble(r: 2, ev: [.land(n: 15, rot: 0, x: 0, y: 0, ms: 43010, landed: [7, 8])]),
            "tumble-ack": .tumble(r: 2, ev: [.ack(id: 31)]),
            "tumble-use": .tumble(r: 2, ev: [.use(slot: 0, seat: 3)]),
            "tumble-sync-request": .tumble(r: 2, ev: []),
        ]
        let samples = try Fixtures.tumbleClientMessages()
        #expect(samples.count == want.count)
        for (name, json) in samples {
            let message = try #require(want[name], "\(name)")
            #expect(try jsonEqual(try Codec.encode(message), json), "\(name)")
        }
    }

    /// The snapshot's `tumble` field, as `docs/live-protocol.md` shows it.
    @Test func theRoomStateDecodes() throws {
        let json = """
        {"t":"snapshot","protocol":1,"seq":9,"room":{"code":"ABCDEF","status":"playing","youAreHost":true,"seats":[],
        "gameId":"tumble","options":{"cats":"quick"},
        "tumble":{"seats":3,"cats":"quick","wins":[1,0,2],"left":[false,false,false],"away":[false,true,false],
        "status":"playing","r":4,"startsAt":1764200000000,"roundSeed":[1,2,3,4],
        "trickSeeds":[[5,6,7,8],[9,9,9,9],[3,3,3,3]],"outs":[2],"winner":null,"waitingSince":null}}}
        """
        guard case .snapshot(_, _, let room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snapshot") }
        #expect(room.isTumble)
        #expect(room.tumbleCats == .quick)
        let t = try #require(room.tumble)
        #expect(t.status == .playing)
        #expect(t.r == 4)
        #expect(t.startsAt == 1_764_200_000_000)
        #expect(t.roundSeed == [1, 2, 3, 4])
        #expect(t.trickSeeds?[1] == [9, 9, 9, 9])
        #expect(t.wins == [1, 0, 2])
        #expect(t.topWins == 2)
        #expect(t.inRound(0))
        #expect(!t.inRound(1))
        #expect(!t.inRound(2))
    }

    @Test func leaveAndPlayWithoutGoInTheActEnvelope() throws {
        #expect(try jsonEqual(try Codec.encode(.actTumble(seat: 1, action: .leave)), #"{"t":"act","seat":1,"action":{"k":"leave"}}"#))
        #expect(try jsonEqual(try Codec.encode(.actTumble(seat: 0, action: .playWithout)), #"{"t":"act","seat":0,"action":{"k":"playWithout"}}"#))
    }

    @Test func theLobbysOptionsCarryTheCats() throws {
        #expect(try jsonEqual(try Codec.encode(.setOptions(RoomOptions(cats: .quick))), #"{"t":"setOptions","options":{"cats":"quick"}}"#))
        let o = try JSONDecoder().decode(RoomOptions.self, from: Data(#"{"cats":"lazy"}"#.utf8))
        #expect(o.cats == nil)
    }
}
