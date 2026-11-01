import Testing
@testable import PounceKit

@Suite struct RenderGateTests {
    /// Frames at 60 fps from `start` for `seconds`.
    private func run(_ gate: inout RenderGate, from start: Double, seconds: Double) -> (expired: [Int], paused: Bool, end: Double) {
        var expired: [Int] = []
        var paused = false
        var t = start
        let step = 1.0 / 60
        while t <= start + seconds + 1e-9 {
            let r = gate.frame(t)
            expired += r.expired
            paused = paused || r.pause
            t += step
        }
        return (expired, paused, t)
    }

    @Test func pausesOnlyAfterIdleDelayOfFrames() {
        var gate = RenderGate()
        gate.wake()
        let r1 = gate.frame(0)
        #expect(r1.pause == false)
        let r2 = gate.frame(0.05)
        #expect(r2.pause == false)
        let r3 = gate.frame(0.1)
        #expect(r3.pause == true)
    }

    @Test func runningActionOrTouchKeepsRendering() {
        var gate = RenderGate()
        let token = gate.begin(duration: 0.3)
        let r12 = run(&gate, from: 0, seconds: 0.25)
        #expect(!r12.paused)
        let r4 = gate.end(token)
        #expect(r4)
        let again = gate.end(token)
        #expect(!again, "ending twice is a no-op")
        gate.touchBegan()
        let r13 = run(&gate, from: 1, seconds: 0.5)
        #expect(!r13.paused)
        gate.touchEnded()
        gate.touchEnded()  // never goes negative
        #expect(gate.isIdle)
        let r10 = run(&gate, from: 2, seconds: 0.2)
        #expect(r10.paused)
    }

    @Test func expiresAfterDurationPlusGraceOfRenderedTime() {
        var gate = RenderGate()
        let token = gate.begin(duration: 0.3)
        let early = run(&gate, from: 0, seconds: 0.3 + RenderGate.grace - 0.05)
        #expect(early.expired.isEmpty)
        let late = run(&gate, from: early.end, seconds: 0.1)
        #expect(late.expired == [token])
        #expect(gate.isIdle)
    }

    /// The view paused (app inactive, Control Center): wall-clock time jumps but the timeout
    /// only counts rendered frames, so the action is never released mid-flight.
    @Test func timeoutDoesNotRunWhilePaused() {
        var gate = RenderGate()
        let token = gate.begin(duration: 0.3)
        _ = run(&gate, from: 0, seconds: 0.1)
        // Resumed by the system without a wake: one frame after a 60 s gap counts as one step.
        let r5 = gate.frame(60)
        #expect(r5.expired.isEmpty)
        // Resumed through wake(): the gap counts for nothing.
        gate.wake()
        let r6 = gate.frame(600)
        #expect(r6.expired.isEmpty)
        #expect(gate.running.keys.contains(token))
        let rest = run(&gate, from: 600, seconds: 0.3 + RenderGate.grace)
        #expect(rest.expired == [token])
    }

    @Test func badDurationsBecomeZero() {
        #expect(RenderGate.sanitize(.infinity) == 0)
        #expect(RenderGate.sanitize(.nan) == 0)
        #expect(RenderGate.sanitize(-1) == 0)
        #expect(RenderGate.sanitize(0.25) == 0.25)
        var gate = RenderGate()
        let token = gate.begin(duration: .infinity)
        let r11 = run(&gate, from: 0, seconds: RenderGate.grace + 0.05)
        #expect(r11.expired == [token])
    }

    @Test func graceCanBeZeroForEmitters() {
        var gate = RenderGate()
        let token = gate.begin(duration: 0.2, grace: 0)
        let r = run(&gate, from: 0, seconds: 0.25)
        #expect(r.expired == [token])
    }

    @Test func wakeRestartsTheIdleCountdown() {
        var gate = RenderGate()
        _ = gate.frame(0)
        _ = gate.frame(0.09)
        gate.wake()
        let r7 = gate.frame(0.1)
        #expect(r7.pause == false)
        let r8 = gate.frame(0.15)
        #expect(r8.pause == false)
        let r9 = gate.frame(0.2)
        #expect(r9.pause == true)
    }

    @Test func cancelAllReleasesEveryRunningTokenOnce() {
        var gate = RenderGate()
        let a = gate.begin(duration: 0.3)
        let b = gate.begin(duration: 10)
        let c = gate.begin(duration: 0, grace: 0)
        gate.touchBegan()
        let released = gate.cancelAll()
        #expect(released == [a, b, c])
        #expect(gate.isIdle)
        let again = gate.cancelAll()
        #expect(again.isEmpty)
        let ended = gate.end(b)
        #expect(!ended, "a cancelled token is already gone")
        // Nothing comes back as expired later, and the gate pauses as usual.
        let r = run(&gate, from: 0, seconds: 12)
        #expect(r.expired.isEmpty)
        #expect(r.paused)
    }

    @Test func particleBudgetCapsAndReturns() {
        var gate = RenderGate()
        let first = gate.reserveParticles(40)
        let second = gate.reserveParticles(40)
        let third = gate.reserveParticles(5)
        #expect([first, second, third] == [40, 20, 0])
        #expect(gate.particles == RenderGate.maxParticles)
        gate.releaseParticles(40)
        let negative = gate.reserveParticles(-3)
        let fourth = gate.reserveParticles(10)
        #expect([negative, fourth] == [0, 10])
        gate.releaseParticles(1000)
        #expect(gate.particles == 0)
    }
}
