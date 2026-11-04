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
}

#if DEBUG
/// `-age-range <kitten|teen|adult|declined|unavailable>`: a canned answer, for tests and screenshots.
struct StubAgeRange: AgeRangeAsking {
    let answer: AgeAnswer

    init(answer: AgeAnswer) { self.answer = answer }

    init?(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "-age-range"), let raw = arguments[safe: i + 1] else { return nil }
        switch raw {
        case "declined": answer = .declined
        case "unavailable": answer = .unavailable
        default:
            guard let band = AgeBand(rawValue: raw) else { return nil }
            answer = .band(band)
        }
    }

    func ask() async -> AgeAnswer { answer }
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
