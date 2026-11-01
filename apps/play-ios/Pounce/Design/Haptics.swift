import CoreHaptics
import Foundation

/// Core Haptics patterns. Every call is a silent no-op when the setting is off, the device has
/// no haptic hardware (the simulator), or the engine fails to start.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let settings: Settings
    private let supported: Bool
    private var engine: CHHapticEngine?

    init(settings: Settings = .shared) {
        self.settings = settings
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Light UI tap.
    func tick() {
        play([transient(0, intensity: 0.5, sharpness: 0.7)])
    }

    /// A card landing.
    func drop() {
        play([transient(0, intensity: 0.8, sharpness: 0.4), transient(0.07, intensity: 0.4, sharpness: 0.3)])
    }

    /// A good move.
    func success() {
        play([transient(0, intensity: 0.6, sharpness: 0.8), transient(0.1, intensity: 1, sharpness: 0.8)])
    }

    /// A heavy hit (a pounce, a bad move).
    func thump() {
        play([
            transient(0, intensity: 1, sharpness: 0.2),
            continuous(0.02, duration: 0.15, intensity: 0.6, sharpness: 0.1),
        ])
    }

    /// Round or game won: a rolling burst.
    func celebrate() {
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            let t = Double(i) * 0.09
            events.append(transient(t, intensity: 0.5 + Double(i) * 0.1, sharpness: 0.9))
        }
        events.append(continuous(0.6, duration: 0.3, intensity: 0.8, sharpness: 0.3))
        play(events)
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
            engine = nil  // rebuild on the next call
        }
    }

    private func readyEngine() throws -> CHHapticEngine {
        let ready: CHHapticEngine
        if let engine {
            ready = engine
        } else {
            ready = try CHHapticEngine()
            ready.isAutoShutdownEnabled = true
            engine = ready
        }
        try ready.start()  // no-op while running; wakes an engine that auto-shut down
        return ready
    }
}
