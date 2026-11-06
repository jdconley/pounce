import Testing
@testable import PounceKit

/// The trophy room's model (trophy room design §3, D4).
@Suite struct TrophyRoomTests {
    private func trophies(
        earned: Trophies.Earned = .init(toys: [], backs: [], rugs: [], condoStage: 0), catalog: [Trophies.Item] = [],
        connections: [StreakView] = []
    ) -> Trophies {
        Trophies(
            own: OwnStreak(count: 4, best: 9, lifetimeKept: 30, perfectWeeks: 2),
            records: .init(current: 4, best: 9, longestPair: 128, totalDays: 30, perfectWeeks: 2),
            earned: earned, catalog: catalog, connections: connections)
    }

    @Test func recordsInOrder() {
        let room = TrophyRoom(trophies())
        #expect(room.records.map(\.kind) == [.current, .best, .longestPair, .totalDays, .perfectWeeks])
        #expect(room.records.map(\.value) == [4, 9, 128, 30, 2])
    }

    @Test func theShelfHasTheCondoThenRugsBacksAndToysGoldenFirst() {
        let earned = Trophies.Earned(
            toys: ["toy-mouse", "toy-disco-ball", "toy-golden-fish", "toy-cork"], backs: ["back-yarn-swirl", "back-crown"],
            rugs: ["rug-night-sky"], condoStage: 6)
        let room = TrophyRoom(trophies(earned: earned))
        #expect(room.shelf.map(\.id) == [
            "condo-6", "rug-night-sky", "back-yarn-swirl", "back-crown", "toy-golden-fish", "toy-disco-ball", "toy-mouse", "toy-cork",
        ])
        #expect(room.shelf.first?.kind == .condo)
    }

    @Test func anEmptyShelfHasNoCondo() {
        #expect(TrophyRoom(trophies()).shelf.isEmpty)
    }

    @Test func lockedIsEverythingNotEarnedNearestFirstThenCatalogOrder() {
        let catalog: [Trophies.Item] = [
            .init(id: "condo-1", kind: .condo, at: 1, progress: 1),
            .init(id: "condo-2", kind: .condo, at: 3, progress: 0.66),
            .init(id: "condo-3", kind: .condo, at: 7, progress: 0.28),
            .init(id: "back-crown", kind: .back, at: 7, progress: 1),
            .init(id: "rug-night-sky", kind: .rug, at: 7, progress: 0.28),
            .init(id: "toy-mouse", kind: .toy, at: 1, progress: 0),
            .init(id: "toy-cork", kind: .toy, at: 1, progress: 1),
        ]
        let earned = Trophies.Earned(toys: ["toy-cork"], backs: ["back-crown"], rugs: [], condoStage: 1)
        let room = TrophyRoom(trophies(earned: earned, catalog: catalog))
        #expect(room.locked.map(\.id) == ["condo-2", "condo-3", "rug-night-sky", "toy-mouse"])
        #expect(room.locked.first?.at == 3)
    }

    @Test func connectionsPassThrough() {
        let mia = streakView("pr_mia", count: 128)
        #expect(TrophyRoom(trophies(connections: [mia])).connections == [mia])
    }

    @Test func ringsNeverDrawEmptyOrOverfull() {
        #expect(TrophyRoom.ring(0) == 0.06)
        #expect(TrophyRoom.ring(0.5) == 0.5)
        #expect(TrophyRoom.ring(4) == 1)
    }
}
