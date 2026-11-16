#if DEBUG
import Foundation

extension DemoFixtures {
    /// The Us screen with no server (`-demo-streaks`): a long pinned streak with Mia (a big condo,
    /// most toys, a gift waiting, today half done, a nap and a held day this week), a win-back with
    /// Kiki (whose pounce waits on you), a pause with Nova (your bell resting), and the ghosted cat
    /// of a streak left with Leo. Pair ids look like
    /// the server's; the week ends today.
    public static func streaks(today: Date = .now) -> StreakList {
        let days = week(ending: today)
        func dots(_ states: [WeekState]) -> [WeekDot] { zip(days, states).map { WeekDot(day: $0, state: $1) } }
        let mia = StreakView(
            pair: "pr_demoMiaAAAAAAAAAAAAAAA", partner: .init(name: castName(1, "Mia"), cat: 2), count: 128, me: true, them: false,
            kept: false, naps: 1, best: 128, lifetimeKept: 141, perfectWeeks: 14,
            week: dots([.kept, .kept, .nap, .kept, .held, .kept, .live]), next: 150, condoStage: 7,
            toys: Array(StreakCatalog.commonToys.prefix(12)) + Array(StreakCatalog.shinyToys.prefix(4)) + [StreakCatalog.goldenToys[0]],
            unlocked: .init(backs: ["back-violet-paw", "back-yarn-swirl", "back-moonlit-fish", "back-crown"],
                            rugs: ["rug-classic", "rug-night-sky", "rug-candy-stripe"]),
            gifts: [.init(id: "g7", milestone: 100, item: "rug-fish-pond")],
            myMove: [], theirMove: [code], pinned: true)
        let kiki = StreakView(
            pair: "pr_demoKikiAAAAAAAAAAAAAA", partner: .init(name: castName(2, "Kiki"), cat: 6), count: 9, me: false, them: true,
            naps: 0, winback: .init(kept: 1), best: 23, lifetimeKept: 31, perfectWeeks: 1,
            week: dots([.kept, .kept, .kept, .none, .kept, .kept, .live]), next: 14, condoStage: 5,
            toys: Array(StreakCatalog.commonToys.suffix(6)) + [StreakCatalog.shinyToys[5]],
            unlocked: .init(backs: ["back-violet-paw", "back-cucumber-chaos"], rugs: ["rug-classic"]),
            myMove: ["K9PQR"],
            pounce: PounceState(waiting: .init(id: "pc_demoKikiAAAAAAAAAAAAAA", target: .table("K9PQR"))))
        let nova = StreakView(
            pair: "pr_demoNovaAAAAAAAAAAAAAA", partner: .init(name: castName(3, "Nova"), cat: 5), count: 41, naps: 2,
            pausedUntil: days[6], best: 41, lifetimeKept: 58, perfectWeeks: 4,
            week: dots([.kept, .kept, .kept, .kept, .paused, .paused, .paused]), next: 50, condoStage: 6,
            toys: Array(StreakCatalog.commonToys.prefix(5)),
            unlocked: .init(backs: ["back-violet-paw", "back-heart-paws"], rugs: ["rug-classic", "rug-royal-violet"]),
            pounce: PounceState(resting: true))
        // Your own streak: twelve days, a cat nap covered yesterday.
        let own = OwnStreak(
            count: 12, best: 30, kept: false, naps: 1, lifetimeKept: 96, perfectWeeks: 6,
            week: dots([.kept, .kept, .kept, .kept, .kept, .nap, .live]))
        return StreakList(
            own: own,
            pairs: [mia, kiki, nova],
            left: [LeftPair(pair: "pr_demoLeoAAAAAAAAAAAAAAA", partner: .init(name: castName(4, "Leo"), cat: 1))])
    }

    /// `-demo-streaks empty`: the trophy room is on but nobody is connected yet (Home's big plus).
    public static func emptyStreaks(today: Date = .now) -> StreakList {
        let days = week(ending: today)
        let states: [WeekState] = [.none, .none, .none, .none, .none, .none, .live]
        return StreakList(own: OwnStreak(count: 0, week: zip(days, states).map { WeekDot(day: $0, state: $1) }))
    }

    /// The seven day keys ending `today` (`YYYY-MM-DD`, the 04:00 rollover ignored).
    static func week(ending today: Date) -> [String] {
        let format = Date.ISO8601FormatStyle().year().month().day()
        return (0..<7).map { format.format(today.addingTimeInterval(Double($0 - 6) * 86_400)) }
    }
}

/// `-demo-streaks`: the streak routes in memory, acting on `DemoFixtures.streaks()` the way the
/// server would (gifts open into unlocks, pause, pin, leave and the ghosted cat's rejoin).
public actor DemoStreakService: StreakService {
    private var list: StreakList

    public init(_ list: StreakList = DemoFixtures.streaks()) {
        self.list = list
    }

    public func streaks(person: String?) async throws -> StreakList { list }

    private func update(_ pair: String, _ change: (inout StreakView) -> Void) {
        if let i = list.pairs.firstIndex(where: { $0.pair == pair }) { change(&list.pairs[i]) }
    }

    /// Changes one pair's view in place (the demo pounce routes).
    public func edit(_ pair: String, _ change: @Sendable (inout StreakView) -> Void) { update(pair, change) }

    /// The pair whose view matches, if any.
    public func first(where match: @Sendable (StreakView) -> Bool) -> StreakView? {
        list.pairs.first(where: match)
    }

    public func pause(pair: String, days: Int, person: String?) async throws {
        let until = DemoFixtures.week(ending: .now.addingTimeInterval(Double(days - 1) * 86_400)).last
        update(pair) { $0.pausedUntil = until }
    }

    public func unpause(pair: String, person: String?) async throws {
        update(pair) { $0.pausedUntil = nil }
    }

    public func openGift(pair: String, gift: String, person: String?) async throws {
        update(pair) { v in
            guard let g = v.gifts.first(where: { $0.id == gift }) else { return }
            v.gifts.removeAll { $0.id == gift }
            if g.item.hasPrefix("rug-") { v.unlocked.rugs.append(g.item) }
            if g.item.hasPrefix("back-") { v.unlocked.backs.append(g.item) }
            if g.item.hasPrefix("toy-") { v.toys.append(g.item) }
        }
    }

    public func pin(pair: String, person: String?) async throws {
        for i in list.pairs.indices { list.pairs[i].pinned = list.pairs[i].pair == pair }
        list.pairs.sort { ($0.pinned ? 1 : 0, $0.count) > ($1.pinned ? 1 : 0, $1.count) }
    }

    public func leave(pair: String, person: String?) async throws {
        guard let gone = list.pairs.first(where: { $0.pair == pair }) else { return }
        list.pairs.removeAll { $0.pair == pair }
        list.left.append(LeftPair(pair: pair, partner: gone.partner))
    }

    public func rejoin(pair: String, person: String?) async throws {
        guard let ghost = list.left.first(where: { $0.pair == pair }) else { return }
        list.left.removeAll { $0.pair == pair }
        list.pairs.append(StreakView(
            pair: pair + "x", partner: ghost.partner, count: 0,
            unlocked: .init(backs: [StreakCatalog.defaultBack], rugs: [StreakCatalog.defaultRug])))
    }
}
#endif
