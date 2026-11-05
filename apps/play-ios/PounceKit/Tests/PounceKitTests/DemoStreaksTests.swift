import Testing
@testable import PounceKit

@Suite struct DemoStreaksTests {
    @Test func fixtureShowsEveryState() {
        let list = DemoFixtures.streaks()
        #expect(list.pairs.count == 3)
        let mia = list.pairs[0]
        #expect(mia.pinned && mia.count >= 100 && mia.condoStage >= 7 && mia.toys.count >= 12)
        #expect(mia.gifts.count == 1 && mia.me && !mia.them && !mia.kept)
        #expect(mia.week.count == 7 && mia.week.contains { $0.state == .nap } && mia.week.contains { $0.state == .held })
        #expect(list.pairs.contains { $0.winback != nil })
        #expect(list.pairs.contains { $0.pausedUntil != nil })
        #expect(list.left.count == 1)
        #expect(Set(mia.toys).isSubset(of: Set(StreakCatalog.toys)))
        for pair in list.pairs {
            #expect(Set(pair.unlocked.backs).isSubset(of: Set(StreakCatalog.backs)))
            #expect(Set(pair.unlocked.rugs).isSubset(of: Set(StreakCatalog.rugs)))
        }
    }

    @Test func serviceActsLikeTheServer() async throws {
        let service = DemoStreakService()
        let start = try await service.streaks(person: "me")
        let mia = start.pairs[0]
        let gift = try #require(mia.gifts.first)
        try await service.openGift(pair: mia.pair, gift: gift.id, person: "me")
        var now = try await service.streaks(person: "me")
        #expect(now.pairs[0].gifts.isEmpty)
        #expect(now.pairs[0].unlocked.rugs.contains(gift.item) || now.pairs[0].unlocked.backs.contains(gift.item)
                || now.pairs[0].toys.contains(gift.item))

        try await service.pause(pair: mia.pair, days: 3, person: "me")
        now = try await service.streaks(person: "me")
        #expect(now.pairs.first { $0.pair == mia.pair }?.pausedUntil != nil)
        try await service.unpause(pair: mia.pair, person: "me")
        now = try await service.streaks(person: "me")
        #expect(now.pairs.first { $0.pair == mia.pair }?.pausedUntil == nil)

        let second = now.pairs[1].pair
        try await service.pin(pair: second, person: "me")
        now = try await service.streaks(person: "me")
        #expect(now.pairs[0].pair == second && now.pairs[0].pinned)

        try await service.leave(pair: mia.pair, person: "me")
        now = try await service.streaks(person: "me")
        #expect(!now.pairs.contains { $0.pair == mia.pair })
        #expect(now.left.contains { $0.pair == mia.pair && $0.partner.name == "Mia" })

        try await service.rejoin(pair: mia.pair, person: "me")
        now = try await service.streaks(person: "me")
        #expect(!now.left.contains { $0.pair == mia.pair })
        #expect(now.pairs.contains { $0.partner.name == "Mia" && $0.count == 0 })
    }
}
