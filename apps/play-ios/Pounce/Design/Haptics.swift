import CoreHaptics
import Foundation

/// The app's haptic patterns. `Haptics.shared` is the real one, or under a UI test
/// (`Pace.underTest`) a silent stand-in that never starts the Taptic Engine.
@MainActor
protocol HapticPlaying: AnyObject {
    /// Wakes the Taptic Engine without blocking (a finger went down), so the ticks of a drag
    /// that follows don't wait for it to start.
    func prepare()
    /// Light UI tap.
    func tick()
    /// A card landing.
    func drop()
    /// A good move.
    func success()
    /// A heavy hit (a pounce, a bad move).
    func thump()
    /// Round or game won: a rolling burst.
    func celebrate()
    /// Your turn came: a knock-knock with a soft swell, unlike any move's feedback.
    func turn()
}

@MainActor
enum Haptics {
    static let shared: any HapticPlaying = Pace.underTest ? SilentHaptics() : EngineHaptics()
}

/// Core Haptics patterns. Every call is a silent no-op when the setting is off, the device has
/// no haptic hardware (the simulator), or the engine fails to start.
@MainActor
final class EngineHaptics: HapticPlaying {
    private let settings: Settings
    private let supported: Bool
    private var engine: CHHapticEngine?
    /// The engine is started (it stops by itself when idle, and says so).
    private var running = false
    /// The tick's player, made once per engine: a drag ticks on every target it crosses.
    private var tickPlayer: CHHapticPatternPlayer?

    init(settings: Settings = .shared) {
        self.settings = settings
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func prepare() {
        guard supported, settings.hapticsOn, !running, let engine = try? engine ?? makeEngine() else { return }
        engine.start { [weak self] error in
            Task { @MainActor in if error == nil { self?.running = true } }
        }
    }

    func tick() {
        guard supported, settings.hapticsOn else { return }
        do {
            let engine = try readyEngine()
            let player = try tickPlayer ?? engine.makePlayer(
                with: CHHapticPattern(events: [transient(0, intensity: 0.5, sharpness: 0.7)], parameters: []))
            tickPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            reset()
        }
    }

    func drop() {
        play([transient(0, intensity: 0.8, sharpness: 0.4), transient(0.07, intensity: 0.4, sharpness: 0.3)])
    }

    func success() {
        play([transient(0, intensity: 0.6, sharpness: 0.8), transient(0.1, intensity: 1, sharpness: 0.8)])
    }

    func thump() {
        play([
            transient(0, intensity: 1, sharpness: 0.2),
            continuous(0.02, duration: 0.15, intensity: 0.6, sharpness: 0.1),
        ])
    }

    func celebrate() {
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            let t = Double(i) * 0.09
            events.append(transient(t, intensity: 0.5 + Double(i) * 0.1, sharpness: 0.9))
        }
        events.append(continuous(0.6, duration: 0.3, intensity: 0.8, sharpness: 0.3))
        play(events)
    }

    func turn() {
        play([
            transient(0, intensity: 0.9, sharpness: 0.6),
            transient(0.14, intensity: 1, sharpness: 0.6),
            continuous(0.2, duration: 0.18, intensity: 0.45, sharpness: 0.2),
        ])
    }

    // MARK: engine

    private func transient(_ time: TimeInterval, intensity: Double, sharpness: Double) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
            ],
            relativeTime: time)
    }

    private func continuous(
        _ time: TimeInterval, duration: TimeInterval, intensity: Double, sharpness: Double
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
            ],
            relativeTime: time, duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard supported, settings.hapticsOn else { return }
        do {
            let engine = try readyEngine()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            reset()
        }
    }

    /// The engine, started. `start()` blocks, so it runs only when the engine has stopped
    /// (idle shutdown, or never started), not on every pattern.
    private func readyEngine() throws -> CHHapticEngine {
        let ready = try engine ?? makeEngine()
        if !running {
            try ready.start()
            running = true
        }
        return ready
    }

    private func makeEngine() throws -> CHHapticEngine {
        let made = try CHHapticEngine()
        made.isAutoShutdownEnabled = true
        made.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.running = false }
        }
        made.resetHandler = { [weak self] in
            Task { @MainActor in self?.reset() }
        }
        engine = made
        return made
    }

    /// Something failed or the haptic server restarted: rebuild everything on the next call.
    private func reset() {
        engine = nil
        tickPlayer = nil
        running = false
    }
}

/// Under a UI test: counts what would have played and plays nothing.
@MainActor
final class SilentHaptics: HapticPlaying {
    private(set) var played = 0

    func prepare() {}
    func tick() { played += 1 }
    func drop() { played += 1 }
    func success() { played += 1 }
    func thump() { played += 1 }
    func celebrate() { played += 1 }
    func turn() { played += 1 }
}
