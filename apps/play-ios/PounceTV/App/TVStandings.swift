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

    /// "<Name> wins", "A tie" or "Game over".
    static func title(_ room: RoomView) -> String {
        let winners = room.game?.winners ?? room.tiles?.winners ?? []
        if winners.count == 1 {
            let name = SeatInfo.name(room, winners[0])
            return String(localized: "\(name) wins", comment: "TV game over: the title, the one winner's name")
        }
        return winners.count > 1
            ? String(localized: "A tie", comment: "TV game over: the title when several players win")
            : String(localized: "Game over", comment: "TV game over: the title when nobody won")
    }
}
