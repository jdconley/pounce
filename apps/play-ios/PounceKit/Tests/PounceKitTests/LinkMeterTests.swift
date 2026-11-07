import Testing
@testable import PounceKit

/// The connection-quality state machine behind the bad connection indicator.
@Suite struct LinkMeterTests {
    private let config = LinkMeter.Config()

    @Test func startsGoodAndPingsAtOnceThenEveryThreeSeconds() {
        var meter = LinkMeter(now: .zero)
        #expect(meter.quality == .good)
        #expect(meter.shouldPing(now: .zero))
        meter.pingSent(now: .zero)
        // Never two out at once.
        #expect(!meter.shouldPing(now: .seconds(5)))
        meter.pong(now: .milliseconds(80))
        #expect(meter.lastRoundTrip == .milliseconds(80))
        #expect(!meter.shouldPing(now: .milliseconds(2999)))
        #expect(meter.shouldPing(now: .seconds(3)))
    }

    @Test func aSlowPongMakesItWeak() {
        var meter = LinkMeter(now: .zero)
        meter.pingSent(now: .zero)
        meter.pong(now: .milliseconds(1500))
        #expect(meter.quality == .weak)
    }

    @Test func aLatePingMakesItWeakBeforeAnyPong() {
        var meter = LinkMeter(now: .zero)
        meter.pingSent(now: .zero)
        #expect(meter.tick(now: .milliseconds(1499)) == .alive)
        #expect(meter.quality == .good)
        #expect(meter.tick(now: .milliseconds(1500)) == .alive)
        #expect(meter.quality == .weak)
    }

    @Test func twoQuickPongsInARowMakeItGoodAgain() {
        var meter = LinkMeter(now: .zero)
        meter.pingSent(now: .zero)
        meter.pong(now: .seconds(4))
        #expect(meter.quality == .weak)

        meter.pingSent(now: .seconds(7))
        meter.pong(now: .seconds(7) + .milliseconds(200))
        #expect(meter.quality == .weak)  // one is not enough
        // A middling one (between 1 and 1.5 s) keeps it weak and starts the count over.
        meter.pingSent(now: .seconds(10))
        meter.pong(now: .seconds(11) + .milliseconds(200))
        #expect(meter.quality == .weak)
        meter.pingSent(now: .seconds(14))
        meter.pong(now: .seconds(14) + .milliseconds(100))
        #expect(meter.quality == .weak)
        meter.pingSent(now: .seconds(17))
        meter.pong(now: .seconds(17) + .milliseconds(100))
        #expect(meter.quality == .good)
    }

    @Test func aMiddlingPongLeavesAGoodLinkGood() {
        var meter = LinkMeter(now: .zero)
        meter.pingSent(now: .zero)
        meter.pong(now: .milliseconds(1200))
        #expect(meter.quality == .good)
    }

    @Test func aPongWithNoPingOutChangesNothing() {
        var meter = LinkMeter(now: .zero)
        meter.pong(now: .seconds(9))
        #expect(meter.quality == .good)
        #expect(meter.lastRoundTrip == nil)
    }

    @Test func tenSecondsWithNothingBackIsDead() {
        var meter = LinkMeter(now: .zero)
        #expect(meter.tick(now: .seconds(60)) == .alive)  // no ping out: nothing to judge
        meter.pingSent(now: .seconds(60))
        #expect(meter.tick(now: .seconds(69)) == .alive)
        #expect(meter.tick(now: .seconds(70)) == .dead)
    }

    @Test func framesStillArrivingKeepItAliveButWeak() {
        var meter = LinkMeter(now: .zero)
        meter.pingSent(now: .zero)
        meter.heard(now: .seconds(6))
        #expect(meter.tick(now: .seconds(10)) == .alive)
        #expect(meter.quality == .weak)
        #expect(meter.tick(now: .seconds(16)) == .dead)
    }

    /// The playtest: a move that took 20 seconds. Pongs every 3 s go slow, then stop; the meter
    /// says weak within 1.5 s of the first slow one and reconnects 10 s after the last sign of life.
    @Test func twentySecondStallIsWeakFastThenReconnects() {
        var meter = LinkMeter(config: config, now: .zero)
        var now: Duration = .zero
        var verdicts: [(Duration, LinkQuality, LinkVerdict)] = []
        let step: Duration = .milliseconds(500)
        // Healthy for 6 s: pongs 50 ms after each ping.
        var pongAt: Duration?
        while now < .seconds(26) {
            if let at = pongAt, now >= at { meter.pong(now: at); pongAt = nil }
            if meter.shouldPing(now: now) {
                meter.pingSent(now: now)
                // After 6 s the link stalls: no pongs at all.
                if now < .seconds(6) { pongAt = now + .milliseconds(50) }
            }
            let verdict = meter.tick(now: now)
            verdicts.append((now, meter.quality, verdict))
            if verdict == .dead { break }
            now += step
        }
        let firstWeak = verdicts.first { $0.1 == .weak }?.0
        let dead = verdicts.first { $0.2 == .dead }?.0
        #expect(firstWeak == .milliseconds(7500))  // the 6 s ping is 1.5 s late
        #expect(dead == .seconds(16))
    }
}
