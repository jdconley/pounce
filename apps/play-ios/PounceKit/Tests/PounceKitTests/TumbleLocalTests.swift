import Foundation
import Testing
@testable import PounceKit

/// The local box on the frame clock, and the replay of other boxes (iOS plan, Task 2).
@MainActor @Suite struct TumbleLocalTests {
    final class Outbox {
        var batches: [(at: Double, ev: [TumbleEvent])] = []
        var now: Double = 0
    }

    let seed: [UInt32] = [7, 7, 7, 7]
    let trick: [UInt32] = [1, 2, 3, 4]

    private func local(_ out: Outbox, startsAt: Double = 0) -> TumbleLocal {
        TumbleLocal(r: 1, seat: 0, roundSeed: seed, trickSeed: trick, startsAt: startsAt) { ev in out.batches.append((out.now, ev)) }
    }

    /// Steps from `from` to `until` every `frame` ms.
    private func run(_ box: TumbleLocal, _ out: Outbox, from: Double = 0, until: Double, frame: Double) {
        var i = 0.0
        while from + i * frame <= until {
            out.now = from + i * frame
            box.step(out.now)
            i += 1
        }
    }

    private func lastLand(_ out: Outbox) -> TumbleEvent? {
        out.batches.last?.ev.last { if case .land = $0 { true } else { false } }
    }

    // MARK: Review Focus 4: the frame rate never changes the game's speed

    @Test func gravityIsByWallTimeAt120And60Hz() {
        let a = Outbox(), b = Outbox()
        let fast = local(a), slow = local(b)
        run(fast, a, until: 3010, frame: 1000.0 / 120)
        run(slow, b, until: 3010, frame: 1000.0 / 60)
        #expect(fast.toy?.spot == slow.toy?.spot)
        let spawn = TumbleToys.spawn(TumbleQueue.toyAt(seed, 0)).y
        #expect(fast.toy?.spot.y == spawn - 3)
    }

    @Test func theSetDownWaitIsTheSameWallTimeAt120And60Hz() {
        for frame in [1000.0 / 120, 1000.0 / 60] {
            let out = Outbox()
            let box = local(out)
            out.now = 0
            box.step(0)
            var t = 0.0
            // Fall to rest, then count how long it sits before setting down.
            var restedAt: Double?
            while box.box.next == 0, t < 60_000 {
                t += frame
                out.now = t
                box.step(t)
                if restedAt == nil, let toy = box.toy, box.landing == toy.spot.y { restedAt = t }
            }
            let rested = try! #require(restedAt)
            #expect(abs((t - rested) - TumbleClock.setDownMs) <= frame + 1e-6, "frame \(frame)")
        }
    }

    // MARK: moves, drops and the batch

    @Test func movesAreCoalescedAndADropGoesAtOnce() {
        let out = Outbox()
        let box = local(out)
        out.now = 0
        box.step(0)
        #expect(out.batches.count == 1)  // the first toy's position
        out.now = 10
        box.step(10)
        #expect(box.move(-1))
        #expect(box.move(-1))
        out.now = 20
        box.step(20)
        #expect(out.batches.count == 1, "under 50 ms since the last batch")
        out.now = 60
        box.step(60)
        #expect(out.batches.count == 2)
        let moves = out.batches[1].ev
        #expect(moves.count == 1)
        guard case .move(0, 0, let x, _) = moves[0] else { Issue.record("not a move"); return }
        #expect(x == TumbleToys.spawn(TumbleQueue.toyAt(seed, 0)).x - 2)
        out.now = 100
        box.drop(100)
        let last = out.batches.last!.ev
        #expect(last.contains { if case .land(0, _, _, _, 100, []) = $0 { true } else { false } })
        #expect(box.box.next == 1)
    }

    @Test func nothingIsSentWhileTheToyIsStill() {
        let out = Outbox()
        let box = local(out)
        run(box, out, until: 900, frame: 16)
        #expect(out.batches.count == 1)
    }

    @Test func aTrickUsedGoesAtOnce() throws {
        let out = Outbox()
        let box = local(out)
        box.step(0)
        // Give the box a held trick through a sync, as the server would.
        var b = TumbleBox(trickSeed: trick)
        b.held = [.hairball, .nap]
        box.sync(TumbleBoxSync(s: 0, box: b, q: 3), now: 100)
        out.now = 200
        #expect(box.use(slot: 1, on: 0, now: 200) == .nap)
        #expect(box.box.held == [.hairball])
        #expect(out.batches.last?.ev.last == .use(slot: 1, seat: 0))
    }

    // MARK: junk

    @Test func junkWaitsTwoSecondsFromItsAckAndLandsOnTheNextSetDownThatClearsNothing() {
        let out = Outbox()
        let box = local(out)
        out.now = 0
        box.step(0)
        out.now = 500
        box.hit(TumbleHitWire(r: 1, id: 9, from: 1, to: 0, k: .junk, junk: TumbleWaiting(id: 9, rows: 2, gap: 3)), now: 500)
        #expect(out.batches.last?.ev.last == .ack(id: 9))
        #expect(box.box.waiting == [TumbleWaiting(id: 9, rows: 2, gap: 3)])
        #expect(box.drainEffects().contains(.junkWaiting(rows: 2)))
        out.now = 1500
        box.drop(1500)
        #expect(box.box.waiting.count == 1, "not yet: 1 s of its 2")
        guard case .land(_, _, _, _, _, let early) = lastLand(out) else { Issue.record("no land"); return }
        #expect(early.isEmpty)
        out.now = 2600
        box.drop(2600)
        guard case .land(_, _, _, _, _, let landed) = lastLand(out) else { Issue.record("no land"); return }
        #expect(landed == [9])
        #expect(box.box.waiting.isEmpty)
        #expect(box.box.cell(3, 0) == 0)
        #expect(box.box.cell(0, 0) == Tumble.junk)
        #expect(box.drainEffects().contains(.junkLanded(rows: 2)))
    }

    @Test func aTrickHitAppliesAndAcksAtOnceAndAHitTwiceAppliesOnce() {
        let out = Outbox()
        let box = local(out)
        box.step(0)
        let h = TumbleHitWire(r: 1, id: 4, from: 2, to: 0, k: .hairball, hit: .hairball(gap: 5))
        box.hit(h, now: 10)
        box.hit(h, now: 20)
        #expect(box.box.cell(0, 0) == Tumble.junk)
        #expect(box.box.cell(0, 1) == 0)
        #expect(box.drainEffects() == [.hit(.hairball, from: 2)])
        box.hit(TumbleHitWire(r: 1, id: 5, from: 2, to: 0, k: .catnip, hit: .catnip), now: 40)
        #expect(box.catnipUntil == 40 + TumbleClock.effectLength)
        // Another round's hit is not this one's.
        box.hit(TumbleHitWire(r: 2, id: 6, from: 2, to: 0, k: .bath, hit: .bath), now: 50)
        #expect(box.box.cell(0, 0) == Tumble.junk)
    }

    // MARK: Review Focus 1: back from the background

    @Test func aReturnFromTheBackgroundAsksForASyncBeforeAnyStep() {
        let out = Outbox()
        let box = local(out)
        run(box, out, until: 2000, frame: 16)
        box.suspend()
        let before = out.batches.count
        out.now = 9000
        box.resume(9000)
        #expect(out.batches.count == before + 1)
        #expect(out.batches.last?.ev == [])
        run(box, out, from: 9016, until: 10_000, frame: 16)
        #expect(box.toy == nil, "nothing steps until the sync")
        #expect(out.batches.count == before + 1)
        var b = TumbleBox(trickSeed: trick)
        b.next = 3
        b.waiting = [TumbleWaiting(id: 2, rows: 1, gap: 0)]
        box.sync(TumbleBoxSync(s: 0, box: b, q: 9, waitingLeft: [500]), now: 10_000)
        #expect(box.toy?.n == 3)
        #expect(box.toy?.spot == TumbleToys.spawn(TumbleQueue.toyAt(seed, 3)))
        #expect(box.waiting(at: 10_000).first?.leftMs == 500)
    }

    @Test func anUnansweredSyncRequestIsAskedAgain() {
        let out = Outbox()
        let box = local(out)
        box.suspend()
        out.now = 100
        box.resume(100)
        run(box, out, from: 116, until: 3200, frame: 16)
        #expect(out.batches.filter { $0.ev.isEmpty }.count == 2)
    }

    @Test func nothingFallsBeforeTheRoundStarts() {
        let out = Outbox()
        let box = local(out, startsAt: 3000)
        run(box, out, until: 2990, frame: 16)
        #expect(box.toy == nil)
        #expect(out.batches.isEmpty)
        box.step(3000)
        #expect(box.toy != nil)
    }
}

@Suite struct TumbleReplayTests {
    /// A vector file's steps as the server would relay them: each set-down an `l`, each junk and
    /// trick a `tumbleHit` acked by the box, each trick used a `u`. Refusals never reach a replayer.
    @Test(arguments: TumbleFixtureTests.files.filter { $0.hasPrefix("random") }) func replaysTheVectorsStreams(_ file: String) throws {
        let data = try Data(contentsOf: Fixtures.url("tumble/\(file)"))
        let v = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let roundSeed = (v["roundSeed"] as! [Int]).map(UInt32.init)
        let trickSeed = (v["trickSeed"] as! [Int]).map(UInt32.init)
        let replay = TumbleReplay(r: 1, roundSeed: roundSeed, trickSeeds: [[0, 0, 0, 1], trickSeed], skip: 0)
        var engine = TumbleBox(trickSeed: trickSeed)
        var q = 0
        var hitId = 10_000
        func relay(_ ev: [TumbleEvent]) {
            q += 1
            replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: q, ev: ev)), now: Double(q))
        }
        for step in v["steps"] as! [[String: Any]] {
            let op = step["do"] as! [Any]
            let expect = step["expect"] as! [String: Any]
            if expect["error"] != nil { continue }
            switch op[0] as! String {
            case "setDown":
                let (n, rot, x, y, landed) = (op[1] as! Int, op[2] as! Int, op[3] as! Int, op[4] as! Int, op[5] as! [Int])
                guard case .success(let done) = Tumble.setDown(engine, roundSeed: roundSeed, n: n, rot: rot, x: x, y: y, landed: landed) else {
                    Issue.record("engine refused")
                    return
                }
                engine = done.box
                relay([.move(n: n, rot: rot, x: x, y: y + 2), .land(n: n, rot: rot, x: x, y: y, ms: q, landed: landed)])
            case "junk":
                let w = op[1] as! [String: Int]
                let junk = TumbleWaiting(id: w["id"]!, rows: w["rows"]!, gap: w["gap"]!)
                engine = Tumble.receiveJunk(engine, junk)
                replay.apply(.hit(TumbleHitWire(r: 1, id: junk.id, from: 0, to: 1, k: .junk, junk: junk)), now: 0)
                relay([.ack(id: junk.id)])
            case "hit":
                let o = op[1] as! [String: Any]
                let hit: TumbleHit
                let k = TumbleHitKind(rawValue: o["k"] as! String)!
                switch k {
                case .hairball: hit = .hairball(gap: o["gap"] as! Int)
                case .swipe: hit = .swipe(shifts: o["shifts"] as! [Int])
                case .swap:
                    let b = try TumbleText.box(cells: o["cells"] as! [String], tricks: o["tricks"] as! [String])
                    hit = .swap(cells: b.cells, tricks: b.tricks)
                case .catnip: hit = .catnip
                case .nap: hit = .nap
                case .scoop: hit = .scoop
                case .settle: hit = .settle
                case .bath: hit = .bath
                default: continue
                }
                engine = Tumble.applyHit(engine, hit).box
                hitId += 1
                replay.apply(.hit(TumbleHitWire(r: 1, id: hitId, from: 0, to: 1, k: k, hit: hit)), now: 0)
                relay([.ack(id: hitId)])
            case "use":
                let slot = op[1] as! Int
                engine = try #require(Tumble.useTrick(engine, slot: slot)).box
                relay([.use(slot: slot, seat: 0)])
            default:
                continue
            }
            #expect(replay.box(1) == engine, "\(file) after relay \(q)")
            if replay.box(1) != engine { return }
        }
        #expect(!replay.needsSync)
    }

    @Test func aGapInQAsksForASyncAndNothingReplaysOutOfOrder() throws {
        let replay = TumbleReplay(r: 1, roundSeed: [7, 7, 7, 7], trickSeeds: [[1, 1, 1, 1], [2, 2, 2, 2]], skip: 0)
        let toy = TumbleQueue.toyAt([7, 7, 7, 7], 0)
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 1, ev: [.move(n: 0, rot: 0, x: 2, y: 10)])), now: 0)
        #expect(!replay.needsSync)
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 3, ev: [.move(n: 0, rot: 0, x: 3, y: 9)])), now: 0)
        #expect(replay.takeSyncRequest())
        #expect(!replay.takeSyncRequest(), "asked once")
        #expect(replay.seats[1]?.toy?.spot.x == 2, "the relay after the gap was not replayed")
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 2, ev: [.move(n: 0, rot: 0, x: 4, y: 9)])), now: 0)
        #expect(replay.seats[1]?.toy?.spot.x == 2, "nor a late one, until the sync")
        var b = TumbleBox(trickSeed: [2, 2, 2, 2])
        b.next = 5
        replay.apply(.sync(TumbleSync(r: 1, boxes: [TumbleBoxSync(s: 1, box: b, q: 7)])), now: 0)
        #expect(replay.box(1) == b)
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 8, ev: [.move(n: 5, rot: 1, x: 6, y: 12)])), now: 0)
        #expect(replay.seats[1]?.toy?.spot == TumbleSpot(rot: 1, x: 6, y: 12))
        #expect(toy == TumbleQueue.toyAt([7, 7, 7, 7], 0))
    }

    @Test func hitsApplyWhenTheTargetAcksThem() {
        let replay = TumbleReplay(r: 1, roundSeed: [7, 7, 7, 7], trickSeeds: [[1, 1, 1, 1], [2, 2, 2, 2]], skip: 0)
        replay.apply(.hit(TumbleHitWire(r: 1, id: 3, from: 0, to: 1, k: .hairball, hit: .hairball(gap: 0))), now: 0)
        #expect(replay.box(1)?.cell(1, 0) == 0, "not before the ack")
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 1, ev: [.ack(id: 3)])), now: 0)
        #expect(replay.box(1)?.cell(1, 0) == Tumble.junk)
        #expect(replay.drainEffects() == [.hit(seat: 1, kind: .hairball, from: 0)])
    }

    @Test func aLaggingBoxsToyHangsStillAndAnOkOneGlides() {
        let replay = TumbleReplay(r: 1, roundSeed: [7, 7, 7, 7], trickSeeds: [[1, 1, 1, 1], [2, 2, 2, 2]], skip: 0)
        replay.apply(.relay(TumbleRelay(r: 1, s: 1, q: 1, ev: [.move(n: 0, rot: 0, x: 4, y: 12)])), now: 1000)
        #expect(replay.glide(1, now: 1500, roundMs: 0)?.y == 11.5)
        #expect(replay.glide(1, now: 9000, roundMs: 0)?.y == 11, "never more than a row ahead")
        replay.apply(.seat(TumbleSeat(r: 1, s: 1, st: .lag)), now: 1500)
        #expect(replay.glide(1, now: 1600, roundMs: 0)?.y == 12)
    }
}
