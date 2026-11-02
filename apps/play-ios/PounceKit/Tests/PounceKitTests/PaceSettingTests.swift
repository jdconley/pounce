import Testing
@testable import PounceKit

@Suite struct PaceSettingTests {
    private func resolve(_ args: [String], _ env: [String: String] = [:]) -> PaceSetting.Resolved {
        PaceSetting.resolve(arguments: ["Pounce"] + args, env: env)
    }

    @Test func normalWithoutSettings() {
        #expect(resolve([]) == .init(factor: 1, underTest: false))
    }

    @Test func argumentSetsSpeedAndTestRun() {
        #expect(resolve(["-anim-speed", "10"]) == .init(factor: 10, underTest: true))
        #expect(resolve(["-anim-speed", "1"]) == .init(factor: 1, underTest: true))
    }

    @Test func envWorksAndArgumentWins() {
        #expect(resolve([], ["POUNCE_ANIM_SPEED": "20"]) == .init(factor: 20, underTest: true))
        #expect(resolve(["-anim-speed", "5"], ["POUNCE_ANIM_SPEED": "20"]).factor == 5)
    }

    @Test func badValuesFallBackToOneButStillTest() {
        #expect(resolve(["-anim-speed", "fast"]) == .init(factor: 1, underTest: true))
        #expect(resolve(["-anim-speed", "0"]).factor == 1)
        #expect(resolve(["-anim-speed", "-3"]).factor == 1)
        #expect(resolve(["-anim-speed", "inf"]).factor == 1)
        #expect(resolve(["-anim-speed"]) == .init(factor: 1, underTest: false))
    }

    @Test func clamped() {
        #expect(resolve(["-anim-speed", "5000"]).factor == 100)
        #expect(resolve(["-anim-speed", "0.001"]).factor == 0.05)
    }

    @Test func slowmoOnlySlowsDown() {
        #expect(resolve(["-slowmo", "0.25"]) == .init(factor: 0.25, underTest: false))
        #expect(resolve(["-slowmo", "4"]).factor == 1)
        #expect(resolve(["-slowmo", "0.25", "-anim-speed", "10"]).factor == 10)
    }
}
