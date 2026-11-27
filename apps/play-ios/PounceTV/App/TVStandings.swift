import PounceKit

/// Game over on the TV, worked out from the room: who placed where and what they finished on.
/// The web TV's `standings` and `overTitle` (`apps/play-web/src/ui/tv/tv-model.ts`).
enum TVStandings {
    struct Row: Equatable, Identifiable {
        let seat: Seat
        let won: Bool
        /// Left the game before it ended.
        let out: Bool
        /// "Level 7 · 120" in Cat Tower, "+12" in Tuna Tiles, "Left" for a forfeit.
        let detail: String

        var id: Seat { seat }
    }

    /// Everyone who played, best first: winners, then by level and fewest points (Cat Tower) or
    /// most points (Tuna Tiles), and anyone who left last.
    static func rows(_ room: RoomView) -> [Row] {
        if let model = BirdTableModel(room: room) { return birdRows(model) }
        if let tumble = room.tumble { return tumbleRows(room, tumble) }
        let game = room.game
        let tiles = room.tiles
        let winners = game?.winners ?? tiles?.winners ?? []
        let forfeited = game?.forfeited ?? tiles?.forfeited ?? []
        let seats = room.seats.indices.filter { room.seats[$0].kind == .human || room.seats[$0].kind == .bot }
        func out(_ seat: Seat) -> Bool { forfeited.indices.contains(seat) && forfeited[seat] }
        let ranked = seats.sorted { a, b in
            let wa = winners.contains(a), wb = winners.contains(b)
            if wa != wb { return wa }
            if out(a) != out(b) { return !out(a) }
            if let game {
                let pa = game.phase[safe: a] ?? 0, pb = game.phase[safe: b] ?? 0
                if pa != pb { return pa > pb }
                return (game.scores[safe: a] ?? 0) < (game.scores[safe: b] ?? 0)
            }
            return (tiles?.scores[safe: a] ?? 0) > (tiles?.scores[safe: b] ?? 0)
        }
        return ranked.map { seat in
            let detail: String
            if out(seat) {
                detail = String(localized: "Left", comment: "TV game over: a player who left the game before it ended")
            } else if let game {
                let level = min((game.phase[safe: seat] ?? 0) + 1, Rules.phases.count)
                let score = game.scores[safe: seat] ?? 0
                detail = String(
                    localized: "Level \(level) · \(score)",
                    comment: "TV game over: a Cat Tower player's last level (1 to 10) and their points")
            } else {
                let points = tiles?.scores[safe: seat] ?? 0
                detail = points > 0 ? "+\(points)" : "\(points)"
            }
            return Row(seat: seat, won: winners.contains(seat), out: out(seat), detail: detail)
        }
    }

    /// Birdwatch: every seat by its side's place, its side's total beside it (teammates match).
    static func birdRows(_ model: BirdTableModel) -> [Row] {
        model.standings.flatMap { side in
            side.seats.map { seat in
                Row(seat: seat, won: model.view.winners.contains(seat), out: false, detail: "\(side.score)")
            }
        }
    }

    /// Toy Tumble: most round wins first; a seat that left is last.
    static func tumbleRows(_ room: RoomView, _ t: TumbleView) -> [Row] {
        let seats = (0..<t.seats).sorted { a, b in
            let la = t.left[safe: a] ?? false, lb = t.left[safe: b] ?? false
            if la != lb { return !la }
            return (t.wins[safe: a] ?? 0) > (t.wins[safe: b] ?? 0)
        }
        return seats.map { s in
            let left = t.left[safe: s] ?? false
            return Row(
                seat: s, won: t.status == .over && t.winner == s, out: left,
                detail: left ? String(localized: "Left", comment: "TV game over: a player who left the game before it ended") : "\(t.wins[safe: s] ?? 0)")
        }
    }

    /// "<Name> wins", "A tie" or "Game over".
    static func title(_ room: RoomView) -> String {
        if let t = room.tumble {
            guard let w = t.winner else { return String(localized: "Game over", comment: "TV game over: the title when nobody won") }
            let name = SeatInfo.name(room, w)
            return String(localized: "\(name) wins", comment: "TV game over: the title, the one winner's name")
        }
        if let bird = room.birdwatch, bird.winners.count > 1 {
            let names = bird.winners.map { SeatInfo.name(room, $0) }.formatted(.list(type: .and))
            return String(localized: "\(names) win", comment: "TV game over (Birdwatch): the winning side's names")
        }
        let winners = room.game?.winners ?? room.tiles?.winners ?? room.birdwatch?.winners ?? []
        if winners.count == 1 {
            let name = SeatInfo.name(room, winners[0])
            return String(localized: "\(name) wins", comment: "TV game over: the title, the one winner's name")
        }
        return winners.count > 1
            ? String(localized: "A tie", comment: "TV game over: the title when several players win")
            : String(localized: "Game over", comment: "TV game over: the title when nobody won")
    }
}
