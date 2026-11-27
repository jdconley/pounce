import Foundation
import Testing
@testable import PounceKit

/// Toy Tumble's golden vectors (`apps/play-api/fixtures/tumble/*.json`, spec §9.1): every step of
/// every file, run through the Swift engine, must give exactly the box and result the TypeScript
/// engine wrote, cell for cell.
@Suite struct TumbleFixtureTests {
    static let files: [String] = {
        let dir = Fixtures.url("tumble")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted()
    }()

    private func load(_ file: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Fixtures.url("tumble/\(file)"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func thereAreVectors() {
        #expect(Self.files.count >= 17)
        #expect(Self.files.contains("every-hit.json"))
    }

    @Test(arguments: files) func replays(_ file: String) throws {
        let v = try load(file)
        let roundSeed = try seed(v["roundSeed"])
        let trickSeed = try seed(v["trickSeed"])
        let queue = try #require(v["queue"] as? [String])
        for (n, id) in queue.enumerated() {
            #expect(TumbleQueue.toyAt(roundSeed, n).rawValue == id, "\(file): queue[\(n)]")
        }
        var box = try (v["start"] as? [String: Any]).map(boxFrom) ?? TumbleBox(trickSeed: trickSeed)
        let steps = try #require(v["steps"] as? [[String: Any]])
        for (i, step) in steps.enumerated() {
            let op = try #require(step["do"] as? [Any])
            let expect = try #require(step["expect"] as? [String: Any])
            let label = "\(file) step \(i) \(op.first ?? "")"
            box = try run(box, roundSeed: roundSeed, op: op, expect: expect, label: label)
        }
    }

    // MARK: running one step

    private func run(_ box: TumbleBox, roundSeed: [UInt32], op: [Any], expect: [String: Any], label: String) throws -> TumbleBox {
        let kind = try #require(op.first as? String)
        switch kind {
        case "setDown":
            let landed = try #require(op[5] as? [Int])
            let r = Tumble.setDown(box, roundSeed: roundSeed, n: try int(op[1]), rot: try int(op[2]), x: try int(op[3]), y: try int(op[4]), landed: landed)
            switch r {
            case .failure(let error):
                #expect(expect["error"] as? String == error.rawValue, "\(label)")
                return box
            case .success(let done):
                #expect(expect["error"] == nil, "\(label): expected \(expect["error"] ?? "")")
                #expect(done.cleared == (expect["cleared"] as? Int), "\(label) cleared")
                #expect(done.sent == (expect["sent"] as? Int), "\(label) sent")
                let blocked = (expect["blocked"] as? [[String: Int]] ?? []).map { TumbleBlocked(id: $0["id"] ?? -1, rows: $0["rows"] ?? -1) }
                #expect(done.blocked == blocked, "\(label) blocked")
                #expect(done.pocketed.map(\.rawValue) == (expect["pocketed"] as? [String]), "\(label) pocketed")
                #expect(done.out == (expect["out"] as? Bool), "\(label) out")
                try check(done.box, expect["box"], label)
                return done.box
            }
        case "junk":
            let w = try #require(op[1] as? [String: Int])
            let b = Tumble.receiveJunk(box, TumbleWaiting(id: w["id"] ?? 0, rows: w["rows"] ?? 0, gap: w["gap"] ?? 0))
            try check(b, expect["box"], label)
            return b
        case "hit":
            let rawHit = try #require(op[1] as? [String: Any])
            let hit = try hitFrom(rawHit)
            let r = Tumble.applyHit(box, hit)
            #expect(r.pocketed.map(\.rawValue) == (expect["pocketed"] as? [String]), "\(label) pocketed")
            try check(r.box, expect["box"], label)
            return r.box
        case "use":
            guard let r = Tumble.useTrick(box, slot: try int(op[1])) else {
                #expect(expect["error"] as? String == "no_trick", "\(label)")
                return box
            }
            #expect(r.trick.rawValue == (expect["trick"] as? String), "\(label) trick")
            try check(r.box, expect["box"], label)
            return r.box
        case "turn":
            let toyName = op[1] as? String ?? ""
            let toy = try #require(TumbleToy(rawValue: toyName))
            let t = Tumble.turn(box, toy: toy, rot: try int(op[2]), x: try int(op[3]), y: try int(op[4]), dir: try int(op[5]))
            if let to = expect["to"] as? [Int] {
                #expect(t.map { [$0.rot, $0.x, $0.y] } == to, "\(label)")
            } else {
                #expect(t == nil, "\(label)")
            }
            return box
        default:
            Issue.record("\(label): unknown op")
            return box
        }
    }

    private func check(_ box: TumbleBox, _ raw: Any?, _ label: String) throws {
        let rawBox = try #require(raw as? [String: Any])
        let want = try boxFrom(rawBox)
        let text = TumbleText.of(box)
        let wantText = TumbleText.of(want)
        #expect(text.cells == wantText.cells, "\(label) cells")
        #expect(text.tricks == wantText.tricks, "\(label) tricks")
        #expect(box.held == want.held, "\(label) held")
        #expect(box.next == want.next, "\(label) next")
        #expect(box.waiting == want.waiting, "\(label) waiting")
        #expect(box.rng == want.rng, "\(label) rng")
        #expect(box.out == want.out, "\(label) out")
        #expect(box.rows == want.rows, "\(label) rows")
        #expect(box == want, "\(label) box")
    }

    // MARK: reading the JSON

    private func int(_ v: Any) throws -> Int { try #require(v as? Int) }

    private func seed(_ v: Any?) throws -> [UInt32] {
        try #require(v as? [Int]).map { UInt32($0) }
    }

    private func boxFrom(_ o: [String: Any]) throws -> TumbleBox {
        let cells = try #require(o["cells"] as? [String])
        let tricks = try #require(o["tricks"] as? [String])
        var box = try TumbleText.box(cells: cells, tricks: tricks)
        let held = try #require(o["held"] as? [String])
        box.held = held.compactMap { TumbleTrick(rawValue: $0) }
        #expect(box.held.count == held.count)
        box.next = try int(o["next"] as Any)
        box.waiting = try #require(o["waiting"] as? [[String: Int]]).map { TumbleWaiting(id: $0["id"] ?? 0, rows: $0["rows"] ?? 0, gap: $0["gap"] ?? 0) }
        box.rng = try seed(o["rng"])
        box.out = try #require(o["out"] as? Bool)
        box.rows = try int(o["rows"] as Any)
        return box
    }

    private func hitFrom(_ o: [String: Any]) throws -> TumbleHit {
        switch try #require(o["k"] as? String) {
        case "hairball": return .hairball(gap: try int(o["gap"] as Any))
        case "swipe": return .swipe(shifts: try #require(o["shifts"] as? [Int]))
        case "catnip": return .catnip
        case "nap": return .nap
        case "scoop": return .scoop
        case "settle": return .settle
        case "bath": return .bath
        case "swap":
            let cells = try #require(o["cells"] as? [String])
            let tricks = try #require(o["tricks"] as? [String])
            let b = try TumbleText.box(cells: cells, tricks: tricks)
            return .swap(cells: b.cells, tricks: b.tricks)
        default: throw Fixtures.FixtureError.malformed("hit \(o)")
        }
    }
}

@Suite struct TumbleBasicsTests {
    /// The generator is pinned bit for bit by the vectors (every queue and every `rng`); this is
    /// the play-api basics test's turn and spawn table.
    @Test func turnsAndSpawnsMatchTheServersTable() {
        #expect(TumbleToys.cells(.t4, rot: 0) == [TumbleCell(0, 1), TumbleCell(1, 1), TumbleCell(2, 1), TumbleCell(1, 2)])
        #expect(TumbleToys.cells(.t4, rot: 1) == [TumbleCell(1, 2), TumbleCell(1, 1), TumbleCell(1, 0), TumbleCell(2, 1)])
        #expect(TumbleToy.allCases.map { TumbleToys.cells($0, rot: 0).count } == [3, 3, 4, 4, 4, 4, 4, 5, 5])
        #expect(TumbleToy.allCases.map(TumbleToys.size) == [3, 2, 4, 2, 3, 3, 3, 3, 3])
        #expect(TumbleToys.spawn(.i4) == TumbleSpot(rot: 0, x: 4, y: 16))
        #expect(TumbleToys.spawn(.v3) == TumbleSpot(rot: 0, x: 5, y: 18))
        #expect(TumbleToys.spawn(.t4) == TumbleSpot(rot: 0, x: 4, y: 17))
        #expect(TumbleToys.spawn(.p5) == TumbleSpot(rot: 0, x: 4, y: 18))
    }

    @Test func toysSpawnCentredWithTheirLowestCellsInRow18() {
        for toy in TumbleToy.allCases {
            let at = TumbleToys.spawn(toy)
            let low = TumbleToys.cells(toy, rot: 0).map(\.y).min() ?? 0
            #expect(at.y + low == 18)
            #expect(at.x == (12 - TumbleToys.size(toy)) / 2)
        }
    }

    /// Bags run 8, 7, 8, 7: the seven small toys each time, and a paw print (bags 0, 4...) or a
    /// bowl (bags 2, 6...) in every other bag.
    @Test func bagsRunEightSevenWithABigToyEveryOtherBag() {
        let seed: [UInt32] = [9, 8, 7, 6]
        var n = 0
        for bag in 0..<8 {
            let size = bag % 2 == 0 ? 8 : 7
            let toys = (0..<size).map { TumbleQueue.toyAt(seed, n + $0) }
            n += size
            #expect(Set(toys).count == size)
            #expect(Set(toys).isSuperset(of: TumbleQueue.small))
            if bag % 2 == 0 { #expect(toys.contains(bag % 4 == 0 ? .p5 : .u5)) }
        }
    }

    /// `clock.ts`: 1000 ms, 15% faster every 30 s, the Zoomies from 2:30, Catnip 4 times, never under 50.
    @Test func gravityFollowsTheSharedClock() {
        #expect(TumbleClock.gravityMs(0) == 1000)
        #expect(TumbleClock.gravityMs(-5) == 1000)
        #expect(TumbleClock.gravityMs(29_999) == 1000)
        #expect(abs(TumbleClock.gravityMs(30_000) - 850) < 1e-9)
        #expect(abs(TumbleClock.gravityMs(149_999) - 1000 * pow(0.85, 4)) < 1e-9)
        #expect(abs(TumbleClock.gravityMs(150_000) - 1000 * pow(0.85, 5) * 0.7) < 1e-9)
        #expect(abs(TumbleClock.gravityMs(165_000) - 1000 * pow(0.85, 5) * 0.49) < 1e-9)
        #expect(TumbleClock.gravityMs(0, catnip: true) == 250)
        #expect(TumbleClock.gravityMs(400_000) == 50)
        #expect(TumbleClock.setDownMs == 500)
        #expect(TumbleClock.setDownResets == 15)
    }

    @Test func restingYDropsFromWhereTheToyAppears() throws {
        let box = try TumbleText.box(cells: ["############", "############"])
        #expect(Tumble.restingY(box, toy: .o4, rot: 0, x: 0) == 2)
        #expect(Tumble.restingY(box, toy: .o4, rot: 0, x: 11) == nil)
    }

    @Test func theCachedQueueMatchesTheFreshOne() {
        let seed: [UInt32] = [3, 1, 4, 1]
        var q = TumbleQueue(roundSeed: seed)
        for n in [0, 9, 3, 40, 17, 100] { #expect(q.toy(n) == TumbleQueue.toyAt(seed, n)) }
    }
}
