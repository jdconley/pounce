import Foundation
import PounceKit

// MARK: Purrtrait
//
//   pounce-e2e purrtrait tv [--timeout 900]
//       (a TV: makes a Purrtrait table as its screen, prints "near <link> <code>" for every new key,
//        and watches it: one line per event, "ink <n> points=<p>" as the drawing grows, and at game
//        over "purrtrait over inkMessages=<n> points=<p> syncs=<s>". Fails if any snapshot carries a
//        word or choices before the reveal.)
//   pounce-e2e purrtrait join <CODE> --near <KEY or 8-char code> [--name Remote] [--cat 4]
//                            [--draw 3] [--expect-refused] [--timeout 900]
//       (a phone that came from the TV's QR: sits down, and on its own turns picks the Easy word,
//        draws `--draw` strokes and gives up. With --expect-refused, passes only when the room
//        refuses the key: an old QR.)

func purrtraitMode(_ plain: APIConfig, _ o: Options) async throws {
    let base = birdwatchConfig(plain)
    let timeout = Double(o.int("timeout", 900))
    switch o.positional.first {
    case "tv":
        let tv = Device("tv", config: base)
        let code = try await tv.api.createRoom(game: GameID.purrtrait, screen: true)
        log("room \(code)")
        let before = await tv.view.snapshots
        await tv.connect(code, role: .screen)
        try await wait(tv, "the screen's snapshot") { $0.snapshots > before }
        try await watchPurrtrait(tv, code: code, base: plain, timeout: timeout)
        await tv.drop()

    case "join":
        guard let code = o.positional.dropFirst().first?.uppercased(), RoomCode.isValid(code) else {
            throw Failure("usage: purrtrait join <CODE> --near <KEY> [--name Remote]")
        }
        let near = o.string("near", "")
        let me = person(o.string("name", "Remote"), cat: o.int("cat", 4))
        let phone = Device("phone", config: base)
        await phone.connect(code, near: near.isEmpty ? nil : near)
        if o.flags["expect-refused"] != nil {
            let v = try await wait(phone, "a refusal or a snapshot", timeout: 30) { $0.gone != nil || $0.snapshots > 0 }
            guard case .forbidden(let why)? = v.gone else { throw Failure("the room took a stale key (\(String(describing: v.gone)))") }
            log("refused \(why.rawValue)")
            return
        }
        try await wait(phone, "snapshot of \(code)") { $0.connected && $0.snapshots > 0 || $0.gone != nil }
        if let gone = await phone.view.gone { throw Failure("refused: \(gone)") }
        guard await phone.view.room?.isPurrtrait == true else { throw Failure("\(code) isn't a Purrtrait table") }
        if let open = await phone.view.room.map({ TableModel(room: $0).takeableSeats.first }) ?? nil {
            try await claim(phone, seat: open, me)
            log("claimed seat \(open) as \(me.name)")
        }
        try await playPurrtrait(phone, strokes: o.int("draw", 3), timeout: timeout)
        await phone.drop()

    default:
        throw Failure("usage: purrtrait tv | join <CODE> --near <KEY> …")
    }
}

/// The TV: prints each key's link, follows the drawing, and fails on a word it should never get.
func watchPurrtrait(_ tv: Device, code: String, base: APIConfig, timeout: Double) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    var key: String?
    var seenEvents = 0
    var seenInk = 0
    var lastPoints = 0
    while Date() < deadline {
        let v = await tv.view
        if let gone = v.gone { throw Failure("tv: room gone (\(gone))") }
        if let near = v.room?.near, near.key != key {
            key = near.key
            log("near \(base.endpoint("/e/\(code)", query: [URLQueryItem(name: "near", value: near.key)]).absoluteString) \(near.code)")
        }
        if let view = v.room?.purrtrait, view.word != nil || view.choices != nil || view.youDraw {
            throw Failure("tv: the screen's view carries a word: \(view)")
        }
        for event in v.events[seenEvents...] {
            if case .purrtrait(let e) = event { log("event \(e)") }
        }
        seenEvents = v.events.count
        if v.inkMessages.count > seenInk {
            seenInk = v.inkMessages.count
            let points = InkDrawing(ops: (v.inkSync ?? []) + v.inkMessages.flatMap { $0 }).points
            if points != lastPoints {
                lastPoints = points
                log("ink \(seenInk) points=\(points)")
            }
        }
        if v.room?.status == .over || v.room?.purrtrait?.phase == .over {
            log("purrtrait over inkMessages=\(v.inkMessages.count) points=\(lastPoints) syncs=\(v.inkSync == nil ? 0 : 1) winners=\(v.room?.purrtrait?.winners ?? [])")
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw Failure("tv: timed out")
}

/// A phone's turns: pick Easy, draw a few strokes as a finger would (50 ms batches), give up.
func playPurrtrait(_ phone: Device, strokes: Int, timeout: Double) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    var drewTurn: String?
    while Date() < deadline {
        let v = await phone.view
        if let gone = v.gone { throw Failure("phone: room gone (\(gone))") }
        guard let room = v.room else { try await Task.sleep(for: .milliseconds(50)); continue }
        if room.status == .over || room.purrtrait?.phase == .over {
            log("purrtrait over scores=\(room.purrtrait?.scores ?? [])")
            return
        }
        if let view = room.purrtrait, let drawer = view.drawer, v.mySeats.contains(drawer) {
            if view.phase == .choosing, view.choices != nil {
                try await phone.send(.actPurrtrait(seat: drawer, action: .choose(.easy)))
                log("picked easy")
                try await Task.sleep(for: .milliseconds(300))
                continue
            }
            if view.phase == .drawing, view.youDraw, drewTurn != view.turn {
                drewTurn = view.turn
                log("drawing \(view.word ?? "?")")
                var pen = InkPen()
                var clock = Duration.zero
                for s in 0..<strokes {
                    pen.color = s % 8
                    pen.down(InkPoint(100 + s * 60, 200))
                    for step in 1...20 {
                        pen.move([InkPoint(100 + s * 60 + step * 10, 200 + step * 25)])
                        clock += .milliseconds(16)
                        if let ops = pen.take(now: clock) { try await phone.send(.ink(seat: drawer, turn: view.turn, ops: ops)) }
                        try await Task.sleep(for: .milliseconds(16))
                    }
                    pen.up()
                    clock += .milliseconds(60)
                    if let ops = pen.take(now: clock) { try await phone.send(.ink(seat: drawer, turn: view.turn, ops: ops)) }
                }
                try await Task.sleep(for: .seconds(1))
                try await phone.send(.actPurrtrait(seat: drawer, action: .giveUp))
                log("gave up")
            }
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw Failure("phone: timed out")
}
