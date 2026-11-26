import Foundation
import PounceKit

// MARK: Birdwatch
//
//   pounce-e2e birdwatch host [--rules official|tucker|friesen] [--seats 4] [--guests 1]
//                             [--name Grandma] [--cat 4] [--timeout 1800]
//       (makes a Birdwatch table, prints "room <CODE>", sits in seat 0, sets the rules, leaves
//        `--guests` seats open and fills the rest to `--seats` with House Cats; once the guests
//        have sat down it starts the game and plays seat 0 to game over)
//   pounce-e2e birdwatch join <CODE> [--rules official|tucker|friesen] [--name Remote] [--cat 4] [--timeout 1800]
//       (takes the first open seat of a Birdwatch table, else a House Cat's; as the table's host,
//        as the first phone at a TV's table is, it sets `--rules`; otherwise `--rules` is what it
//        expects the dealt game to play, and any other rule set fails the run)
//
// It plays only from what the server sends: `bidRange` to bid or pass, `fromNest` and its hand to
// put cards back, its hand to name trump, `partnerChoices` to call a partner, and `playable` to
// play. One line per hand result ("hand <n> ...") and one at game over ("birdwatch over ...").
// Any error the server sends fails the run.

/// The games header a 1.3 app sends: without it the server keeps Birdwatch from this device.
func birdwatchConfig(_ base: APIConfig) -> APIConfig {
    var headers = base.headers
    headers[ClientHeaders.gamesHeader] = ClientHeaders.drawable
    return APIConfig(baseURL: base.baseURL, headers: headers)
}

enum BirdStrategy {
    /// The move for `seat` from what the view offers it, or nil when it has nothing to do.
    /// `bid`: bid the least it may (else pass).
    static func next(_ view: BirdView, seat: Seat, bid: Bool) -> BirdAction? {
        guard view.status == .playing, view.turn == seat else { return nil }
        let hand = view.hands[seat] ?? []
        switch view.phase {
        case .bidding:
            guard let range = view.bidRange else { return nil }
            return bid && range.min <= range.max ? .bid(range.min) : .pass
        case .nest:
            guard let nest = view.fromNest, !nest.isEmpty else { return nil }
            return .nest(putBack(hand: hand, count: nest.count))
        case .trump:
            return .trump(trump(hand: hand))
        case .partner:
            guard let choices = view.partnerChoices, !choices.isEmpty else { return nil }
            return .partner(partner(choices: choices, trump: view.trump))
        case .play:
            guard let playable = view.playable, !playable.isEmpty else { return nil }
            // Lead high, follow low.
            let byOrder = playable.sorted { order($0) < order($1) }
            return .play(view.trick.isEmpty ? byOrder.last! : byOrder.first!)
        case .between, .over:
            return nil
        }
    }

    static func order(_ id: BirdCardID) -> Int { BirdCard(id: id)?.order ?? 0 }

    /// `count` cards to put back: pointless low cards first, the Bird last of all.
    static func putBack(hand: [BirdCardID], count: Int) -> [BirdCardID] {
        let ranked = hand.sorted { a, b in
            let (ca, cb) = (BirdCard(id: a), BirdCard(id: b))
            let ka = (ca == .bird ? 2 : (ca?.points ?? 0) > 0 ? 1 : 0, ca?.order ?? 0, a)
            let kb = (cb == .bird ? 2 : (cb?.points ?? 0) > 0 ? 1 : 0, cb?.order ?? 0, b)
            return ka < kb
        }
        return Array(ranked.prefix(count))
    }

    /// The suit it holds most of (ties to the server's suit order).
    static func trump(hand: [BirdCardID]) -> BirdSuit {
        let counts = BirdSuit.allCases.map { suit in hand.filter { BirdCard(id: $0)?.suit == suit }.count }
        let best = counts.max() ?? 0
        return BirdSuit.allCases[counts.firstIndex(of: best) ?? 0]
    }

    /// The Bird if it may call it, else the highest trump it doesn't hold, else the highest card offered.
    static func partner(choices: [BirdCardID], trump: BirdSuit?) -> BirdCardID {
        if choices.contains(BirdCard.birdID) { return BirdCard.birdID }
        let trumps = choices.filter { BirdCard(id: $0)?.suit == trump }
        return (trumps.isEmpty ? choices : trumps).max { order($0) < order($1) }!
    }
}

struct BirdSummary {
    var hands = 0
    var bids = 0
    var wonBids = 0
    var nests = 0
    var trumps = 0
    var partners = 0
    var plays = 0
    var passes = 0
}

func describe(_ result: BirdHandResult) -> String {
    "hand \(result.hand) bidder=\(result.bidder) bid=\(result.bid) trump=\(result.trump.rawValue) partner=\(result.partner.map(String.init) ?? "-") made=\(result.made) taken=\(result.taken) change=\(result.change) totals=\(result.totals)"
}

/// Plays every Birdwatch move of the seats `device` holds until the game is over.
func playBirdwatch(_ device: Device, rules expected: BirdRules?, timeout: Double, stallAfter: Double = 120) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    var summary = BirdSummary()
    var seenEvents = 0
    var seenErrors = await device.view.errors.count
    var lastSeq = -1
    var lastChange = Date()
    var announced = false
    while true {
        let v = await device.view
        if let gone = v.gone { throw Failure("\(device.name): room gone (\(gone)) mid-game") }
        if v.errors.count > seenErrors {
            let new = v.errors[seenErrors...].map(\.rawValue).joined(separator: ",")
            throw Failure("\(device.name): unexpected error(s) \(new)")
        }
        seenErrors = v.errors.count
        // Hand results and the end, as the events say them.
        for event in v.events[seenEvents...] {
            switch event {
            case .birdwatch(.handOver(let result, _)):
                summary.hands += 1
                log("[\(device.name)] \(describe(result))")
            case .birdwatch(.bidWon(let seat, let amount)):
                if v.mySeats.contains(seat) {
                    summary.wonBids += 1
                    log("[\(device.name)] won the bid at \(amount) for seat \(seat)")
                }
            case .birdwatch(.gameOver(let winners, let scores, let reason)):
                log("[\(device.name)] gameOver winners=\(winners) scores=\(scores) reason=\(reason.rawValue)")
            case .houseCat(let seat):
                log("[\(device.name)] houseCat seat=\(seat)")
            default:
                break
            }
        }
        seenEvents = v.events.count
        guard let room = v.room else { throw Failure("\(device.name): no room") }
        if let bird = room.birdwatch, !announced {
            announced = true
            log("[\(device.name)] dealt rules=\(bird.rules.rawValue) seats=\(bird.seats) target=\(bird.target) nest=\(bird.nestSize) teams=\(bird.teams) mine=\(v.mySeats)")
            if let expected, bird.rules != expected {
                throw Failure("\(device.name): the table plays \(bird.rules.rawValue), not \(expected.rawValue)")
            }
        }
        if room.birdwatch?.status == .over || room.status == .over {
            let bird = room.birdwatch
            log("birdwatch over rules=\(bird?.rules.rawValue ?? "-") seats=\(bird?.seats ?? 0) hands=\(bird?.history.count ?? summary.hands) winners=\(bird?.winners ?? []) scores=\(bird?.scores ?? []) reason=\(bird?.endReason?.rawValue ?? "-") bids=\(summary.bids) won=\(summary.wonBids) passes=\(summary.passes) nests=\(summary.nests) trumps=\(summary.trumps) partners=\(summary.partners) plays=\(summary.plays)")
            return
        }
        if v.seq != lastSeq {
            lastSeq = v.seq
            lastChange = Date()
        } else if Date().timeIntervalSince(lastChange) > stallAfter {
            throw Failure("\(device.name): stalled at seq \(v.seq) for \(Int(stallAfter)) s (phase \(room.birdwatch?.phase.rawValue ?? "-"), turn \(room.birdwatch?.turn.map(String.init) ?? "-"))")
        }
        if Date() > deadline { throw Failure("\(device.name): Birdwatch not over after \(Int(timeout)) s") }

        // Bid the least until it has won a bid once, so it takes the feeder, names trump and, at
        // five, calls a partner; then pass and let the House Cats bid.
        if v.connected, let bird = room.birdwatch, let turn = bird.turn, v.mySeats.contains(turn),
           let action = BirdStrategy.next(bird, seat: turn, bid: summary.wonBids == 0) {
            if let error = try await request(device, .actBirdwatch(seat: turn, action: action)) {
                throw Failure("\(device.name): seat \(turn) \(action) in \(bird.phase.rawValue) refused with \(error.rawValue)")
            }
            switch action {
            case .bid: summary.bids += 1
            case .pass: summary.passes += 1
            case .nest(let cards): summary.nests += 1; log("[\(device.name)] put back \(cards)")
            case .trump(let suit): summary.trumps += 1; log("[\(device.name)] trump \(suit.rawValue)")
            case .partner(let card): summary.partners += 1; log("[\(device.name)] called \(card)")
            case .play: summary.plays += 1
            case .forfeit: break
            }
            seenErrors = await device.view.errors.count
        } else {
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

func birdRules(_ o: Options) throws -> BirdRules? {
    guard let raw = o.flags["rules"] else { return nil }
    guard let rules = BirdRules(rawValue: raw) else { throw Failure("--rules must be official, tucker or friesen") }
    return rules
}

/// Sets the table's rule set from the host's seat, when it isn't that already.
func setRules(_ device: Device, _ rules: BirdRules) async throws {
    guard let room = await device.view.room else { throw Failure("no room") }
    guard room.youAreHost else { throw Failure("\(device.name): not the host, can't set the rules") }
    if room.birdRules == rules { return }
    if let error = try await request(device, .setOptions(RoomOptions(rules: rules))) {
        throw Failure("\(device.name): setOptions \(rules.rawValue) refused with \(error.rawValue)")
    }
    try await wait(device, "the rules to be \(rules.rawValue)") { $0.room?.birdRules == rules }
    log("rules \(rules.rawValue)")
}

func birdwatchMode(_ plain: APIConfig, _ o: Options) async throws {
    let base = birdwatchConfig(plain)
    let rules = try birdRules(o)
    let timeout = Double(o.int("timeout", 1800))
    switch o.positional.first {
    case "host":
        let seats = o.int("seats", 4)
        let guests = o.int("guests", 1)
        guard (4...6).contains(seats), guests >= 0, guests < seats else { throw Failure("--seats 4 to 6, --guests below it") }
        let host = Device("host", config: base)
        let code = try await host.api.createRoom(game: GameID.birdwatch)
        log("room \(code)")
        _ = try await join(host, code)
        try await claim(host, seat: 0, person(o.string("name", "Grandma"), cat: o.int("cat", 4)))
        if let rules { try await setRules(host, rules) }
        for seat in 1..<6 {
            let kind: ConfigureKind = seat <= guests ? .open : seat < seats ? .bot : .closed
            if await host.view.room?.seats[seat].kind.rawValue != kind.rawValue { try await configure(host, seat: seat, kind) }
        }
        log("waiting for \(guests) guest(s)")
        try await wait(host, "\(guests) guest(s)", timeout: 300) { v in
            (v.room?.seats.filter { $0.kind == .human && !$0.yours }.count ?? 0) >= guests
        }
        // Whatever seat a guest took, every other one is a House Cat or closed by now.
        let room = await host.view.room!
        var playing = room.seats.filter { $0.kind == .human || $0.kind == .bot }.count
        for (seat, s) in room.seats.enumerated() where s.kind == .open {
            try await configure(host, seat: seat, playing < seats ? .bot : .closed)
            if playing < seats { playing += 1 }
        }
        log("guest seated \(room.seats.indices.filter { room.seats[$0].kind == .human && !room.seats[$0].yours })")
        if let error = try await request(host, .start) { throw Failure("host: start refused with \(error.rawValue)") }
        try await wait(host, "the game to start") { $0.room?.status == .playing && $0.room?.birdwatch != nil }
        log("game started; seat \(await host.view.mySeats)")
        try await playBirdwatch(host, rules: rules, timeout: timeout)
        await host.drop()

    case "join":
        guard let code = o.positional.dropFirst().first?.uppercased(), RoomCode.isValid(code) else {
            throw Failure("usage: birdwatch join <CODE> [--rules R] [--name Remote] [--cat 4]")
        }
        let me = person(o.string("name", "Remote"), cat: o.int("cat", 4))
        let remote = Device("remote", config: base)
        _ = try await join(remote, code)
        guard await remote.view.room?.isBirdwatch == true else { throw Failure("\(code) isn't a Birdwatch table") }
        log("joined \(code)")
        var claimed = false
        let claimDeadline = Date().addingTimeInterval(120)
        while !claimed {
            let v = await remote.view
            guard let room = v.room else { throw Failure("no room") }
            if !v.mySeats.isEmpty { break }
            guard room.status == .lobby else { throw Failure("the game started without a seat for \(me.name)") }
            if let open = TableModel(room: room).takeableSeats.first {
                if try await request(remote, .claim(seat: open, person: me)) == nil {
                    log("claimed seat \(open) as \(me.name)")
                    claimed = true
                }
            } else {
                if Date() > claimDeadline { throw Failure("no open seat for \(me.name)") }
                let seen = v.snapshots
                try await wait(remote, "an open seat", timeout: 120) { $0.snapshots > seen }
            }
        }
        // The first phone at a TV's table is its host: it picks the rules.
        if let rules, await remote.view.room?.youAreHost == true { try await setRules(remote, rules) }
        try await wait(remote, "the game to start", timeout: 600) { $0.room?.status == .playing && $0.room?.birdwatch != nil }
        log("game started; seat \(await remote.view.mySeats)")
        try await playBirdwatch(remote, rules: rules, timeout: timeout)
        await remote.drop()

    default:
        throw Failure("usage: birdwatch host|join <CODE> [--rules official|tucker|friesen] …")
    }
}
