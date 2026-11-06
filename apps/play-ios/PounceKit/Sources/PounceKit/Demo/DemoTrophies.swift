#if DEBUG
import Foundation

/// `-demo-streaks`: the trophy room from the demo pairs, with the server's rules (play-api
/// `src/streaks/trophies.ts`) roughly mirrored: fixtures to draw, not the logic.
public final class DemoTrophyService: TrophyService, Sendable {
    private let streaks: DemoStreakService

    public init(streaks: DemoStreakService) {
        self.streaks = streaks
    }

    public convenience init(_ list: StreakList = DemoFixtures.streaks()) {
        self.init(streaks: DemoStreakService(list))
    }

    public func trophies(person: String?) async throws -> Trophies {
        let list = try await streaks.streaks(person: person)
        let own = list.own ?? OwnStreak(count: 0)
        let pairs = list.pairs
        let toys = Set(pairs.flatMap(\.toys))
        let backs = Set(pairs.flatMap(\.unlocked.backs))
        let rugs = Set(pairs.flatMap(\.unlocked.rugs))
        let stage = pairs.map(\.condoStage).max() ?? 0
        let days = pairs.map(\.lifetimeKept).max() ?? 0
        let count = pairs.map(\.count).max() ?? 0
        let earned = Trophies.Earned(
            toys: StreakCatalog.toys.filter(toys.contains),
            backs: StreakCatalog.backs.filter { $0 != StreakCatalog.defaultBack && backs.contains($0) },
            rugs: StreakCatalog.rugs.filter { $0 != StreakCatalog.defaultRug && rugs.contains($0) },
            condoStage: stage)
        let next = StreakCatalog.nextMilestone(after: count)
        func ratio(_ m: Int, _ at: Int) -> Double { min(1, Double(m) / Double(max(at, 1))) }
        var catalog: [Trophies.Item] = StreakCatalog.condoThresholds.enumerated().map { i, at in
            Trophies.Item(id: "condo-\(i + 1)", kind: .condo, at: at, progress: i < stage ? 1 : ratio(days, at))
        }
        catalog += StreakCatalog.backs.dropFirst().map { id in
            Trophies.Item(id: id, kind: .back, at: next, progress: earned.backs.contains(id) ? 1 : ratio(count, next))
        }
        catalog += StreakCatalog.rugs.dropFirst().map { id in
            Trophies.Item(id: id, kind: .rug, at: next, progress: earned.rugs.contains(id) ? 1 : ratio(count, next))
        }
        catalog += StreakCatalog.toys.map { id in
            let at = [StreakCatalog.Rarity.common: 1, .shiny: 7, .golden: 30][StreakCatalog.rarity(id)] ?? 1
            return Trophies.Item(id: id, kind: .toy, at: at, progress: earned.toys.contains(id) ? 1 : (at == 1 ? 0 : 3.0 / Double(at)))
        }
        return Trophies(
            own: own,
            records: .init(
                current: own.count, best: own.best, longestPair: pairs.map(\.best).max() ?? 0,
                totalDays: own.lifetimeKept, perfectWeeks: own.perfectWeeks),
            earned: earned, catalog: catalog, connections: pairs)
    }
}
#endif
