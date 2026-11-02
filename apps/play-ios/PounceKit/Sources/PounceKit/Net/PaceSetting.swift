import Foundation

/// Reads the app's DEBUG speed knob from the launch arguments and environment (the app applies
/// it, as `Pace`, only in Debug builds).
///
/// `-anim-speed <n>` (launch argument) wins over `POUNCE_ANIM_SPEED` (environment). Either one
/// also marks the run as a test run (`underTest`), even at 1. Without them, `-slowmo <f>` (demo
/// screenshots) slows the app down and only down: a factor above 1 is ignored there. Garbage
/// and non-positive values fall back to 1; usable values are clamped to `range`.
public enum PaceSetting {
    public static let argument = "-anim-speed"
    public static let envKey = "POUNCE_ANIM_SPEED"
    public static let slowmoArgument = "-slowmo"
    public static let range: ClosedRange<Double> = 0.05...100

    public struct Resolved: Equatable, Sendable {
        public var factor: Double
        public var underTest: Bool
    }

    public static func resolve(arguments: [String], env: [String: String]) -> Resolved {
        if let raw = value(after: argument, in: arguments) ?? env[envKey] {
            return Resolved(factor: parse(raw) ?? 1, underTest: true)
        }
        if let raw = value(after: slowmoArgument, in: arguments), let f = parse(raw) {
            return Resolved(factor: min(f, 1), underTest: false)
        }
        return Resolved(factor: 1, underTest: false)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }

    private static func parse(_ raw: String) -> Double? {
        guard let f = Double(raw.trimmingCharacters(in: .whitespaces)), f.isFinite, f > 0 else { return nil }
        return min(max(f, range.lowerBound), range.upperBound)
    }
}
