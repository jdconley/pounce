import Foundation

/// Home's streak strip (trophy room design §1): your own streak, then one chip per connection in
/// top-pair order. Invite has its own pill in Home's dock, beside Join.
public enum StreakStrip {
    public enum Chip: Equatable, Sendable, Identifiable {
        case own(OwnStreak)
        case pair(StreakView)

        public var id: String {
            switch self {
            case .own: "own"
            case .pair(let view): view.pair
            }
        }
    }

    /// `own` is nil while the server has no trophy room; `pairs` come in the server's order.
    public static func chips(own: OwnStreak?, pairs: [StreakView]) -> [Chip] {
        (own.map { [Chip.own($0)] } ?? []) + pairs.map(Chip.pair)
    }

    /// Invite bounces while nobody is connected, except for a teen: no nudges to share links (§14.1).
    public static func inviteBounces(connected: Bool, band: AgeBand?) -> Bool {
        !connected && band != .teen
    }

    /// Your own streak's mark, by the pair badge's rules: the bandage, the fresh sparkle, the nap blanket.
    public static func mode(_ own: OwnStreak) -> StreakBadge.Mode {
        if let winback = own.winback { return .winback(kept: winback.kept) }
        if own.count == 0 && own.best > 0 { return .fresh }
        if !own.kept, own.week.count >= 2, own.week[own.week.count - 2].state == .nap { return .napped }
        return .normal
    }
}
