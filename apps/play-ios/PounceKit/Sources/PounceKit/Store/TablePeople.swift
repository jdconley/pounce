/// Who you're playing with at a table, for its Home card: everyone at the table but you, your
/// own people first.
public enum TablePeople {
    /// One name on a card. `close` is someone in your circle: a connection (a streak partner) or
    /// a person who shares this phone. They are listed first and drawn on a name pill.
    public struct Face: Equatable, Sendable {
        public var name: String
        public var cat: Int
        public var close: Bool

        public init(name: String, cat: Int, close: Bool) {
            self.name = name
            self.cat = cat
            self.close = close
        }
    }

    /// The names a card shows, and how many more sit there unnamed (the card's "+N").
    public struct Line: Equatable, Sendable {
        public var faces: [Face]
        /// People at the table whose names this phone leaves off (a kitten's, see `faces`).
        public var unnamed: Int

        public init(faces: [Face], unnamed: Int = 0) {
            self.faces = faces
            self.unnamed = unnamed
        }

        public var isEmpty: Bool { faces.isEmpty && unnamed == 0 }

        /// Ways to draw the line, widest first: every name, then one name fewer at a time with
        /// the rest counted ("+2"). The card shows the first that fits; the last one, a single
        /// name, truncates. A line with no names is just its count.
        public var variants: [(faces: [Face], more: Int)] {
            guard !faces.isEmpty else { return [([], unnamed)] }
            return (1...faces.count).reversed().map { n in (Array(faces.prefix(n)), faces.count - n + unnamed) }
        }
    }

    /// Everyone at the table but you. You are your own seat: one with the phone owner's id, or a
    /// seat of yours that isn't someone else who shares this phone (an older cache has no ids).
    /// Your own people come first, in seat order: the others on this phone, then connections
    /// (matched as pounces are: by the partner's name and cat, or by name at a table the pair
    /// shares). Then everyone else, then bots under the bot's name, numbered when there are
    /// several, as the table does.
    ///
    /// A kitten's phone (spec §14.1) names only its own people and bots; anyone else at the
    /// table is counted, not named. The table itself still shows every seat's name.
    public static func line(
        seats: [CachedSeat], code: String, owner: String?, household: [Person], pairs: [StreakView], band: AgeBand?,
        bot: String, botCat: Int
    ) -> Line {
        let homeIDs = Set(household.map(\.id))
        var mine: [Face] = []
        var others: [Face] = []
        var bots: [Face] = []
        var unnamed = 0
        let botCount = seats.filter { $0.kind == .bot }.count
        for seat in seats {
            switch seat.kind {
            case .open, .closed:
                continue
            case .bot:
                let number = bots.count + 1
                bots.append(Face(name: botCount > 1 && number > 1 ? "\(bot) \(number)" : bot, cat: botCat, close: false))
            case .human:
                if let owner, seat.person == owner { continue }
                let onThisPhone = seat.person.map(homeIDs.contains) ?? false
                if seat.yours && !onThisPhone { continue }
                guard let name = seat.name, !name.isEmpty else {
                    unnamed += 1
                    continue
                }
                let cat = seat.cat ?? botCat
                if onThisPhone || isConnection(name: name, cat: cat, code: code, pairs: pairs) {
                    mine.append(Face(name: name, cat: cat, close: true))
                } else if band == .kitten {
                    unnamed += 1
                } else {
                    others.append(Face(name: name, cat: cat, close: false))
                }
            }
        }
        return Line(faces: mine + others + bots, unnamed: unnamed)
    }

    private static func isConnection(name: String, cat: Int, code: String, pairs: [StreakView]) -> Bool {
        pairs.contains { pair in
            pair.partner.name == name
                && (pair.partner.cat == cat || pair.myMove.contains(code) || pair.theirMove.contains(code))
        }
    }
}
