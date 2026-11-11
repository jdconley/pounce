import DeclaredAgeRange
import PounceKit
import UIKit

/// What asking Declared Age Range came back with.
enum AgeAnswer: Equatable {
    case band(AgeBand)
    /// The person chose not to share.
    case declined
    /// No answer (no Apple Account, the API missing, an error).
    case unavailable
}

/// Asks the system for the phone owner's age range, split at 13 and 18 (spec §14.1).
@MainActor
protocol AgeRangeAsking {
    func ask() async -> AgeAnswer
    /// Screen Time's Communication Limits are on for this person (Family Sharing): then Apple's
    /// PermissionKit approves who a kitten may hear from (consent design D3). False when unknown.
    func communicationLimits() async -> Bool
}

/// Apple's Declared Age Range. The system shows its own sheet the first time; later calls
/// answer from what the person already chose.
struct LiveAgeRange: AgeRangeAsking {
    func ask() async -> AgeAnswer {
        guard let presenter = UIApplication.shared.topViewController else { return .unavailable }
        do {
            switch try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 18, in: presenter) {
            case .declinedSharing:
                return .declined
            case .sharing(let range):
                return AgeBand.from(lowerBound: range.lowerBound, upperBound: range.upperBound).map(AgeAnswer.band)
                    ?? .unavailable
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    /// Asked again: the system answers from what the person already chose, with no sheet.
    func communicationLimits() async -> Bool {
        guard let presenter = UIApplication.shared.topViewController else { return false }
        guard case .sharing(let range)? = try? await AgeRangeService.shared.requestAgeRange(ageGates: 13, 18, in: presenter) else {
            return false
        }
        return range.activeParentalControls.contains(.communicationLimits)
    }
}

#if DEBUG
/// `-age-range <kitten|teen|adult|declined|unavailable>`: a canned answer, for tests and screenshots.
/// `-communication-limits` reports Screen Time's Communication Limits on. `-age-range-later
/// <answer>` answers that from the second ask on (the age screen's "Check with Apple").
final class StubAgeRange: AgeRangeAsking {
    let answer: AgeAnswer
    var later: AgeAnswer?
    var limits = CommandLine.arguments.contains("-communication-limits")
    private var asked = 0

    init(answer: AgeAnswer) { self.answer = answer }

    func communicationLimits() async -> Bool { limits }

    init?(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "-age-range"), let raw = arguments[safe: i + 1],
              let first = Self.parse(raw) else { return nil }
        answer = first
        if let j = arguments.firstIndex(of: "-age-range-later"), let raw = arguments[safe: j + 1] { later = Self.parse(raw) }
    }

    private static func parse(_ raw: String) -> AgeAnswer? {
        switch raw {
        case "declined": .declined
        case "unavailable": .unavailable
        default: AgeBand(rawValue: raw).map(AgeAnswer.band)
        }
    }

    func ask() async -> AgeAnswer {
        asked += 1
        return asked > 1 ? later ?? answer : answer
    }
}
#endif

extension UIApplication {
    /// The view controller on top of the key window, to present a system sheet from.
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
