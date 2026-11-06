import Foundation

/// The buttons on a notification (spec §12.5). The raw values are the `UNNotificationAction`
/// identifiers the app registers.
public enum NotifyAction: String, CaseIterable, Sendable {
    /// Opens the app (the table, a new game, or the pick sheet).
    case play = "PLAY"
    /// "Your move" and reminders: the same notification again in an hour, on this phone only.
    case inAnHour = "IN_AN_HOUR"
    /// Pounce: "In a bit", answered in the background.
    case later = "LATER"
    /// Pounce: "Not now", answered in the background.
    case notNow = "NOT_NOW"
    /// Parent consent's confirmation: take it back, in the background (consent design D6).
    case revoke = "REVOKE"

    /// Only Play brings the app forward; the others run in the background.
    public var foreground: Bool { self == .play }
    /// Revoke is drawn red and asks for the device to be unlocked.
    public var destructive: Bool { self == .revoke }
}

/// What the app does with a tap or a button on a notification.
public enum NotifyOutcome: Equatable, Sendable {
    /// Open this table.
    case open(String)
    /// Answer this pounce; Play also opens the app at the table the answer names.
    case answer(id: String, PounceAnswer, opensApp: Bool)
    /// A "you pick" pounce: the app opens the pick sheet for it.
    case pick(id: String, target: PounceTarget, from: PushFace?)
    /// Post the same notification again after this many seconds.
    case snooze(Int)
    /// Open the Kittens panel on this kitten.
    case kittens(String)
    /// Revoke this kitten's consent.
    case revokeConsent(String)
    case none
}

public enum NotifyActions {
    public static let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"
    /// "In an hour".
    public static let snoozeSeconds = 3600

    public static func actions(for category: PushCategory) -> [NotifyAction] {
        switch category {
        case .yourMove, .reminder: [.play, .inAnHour]
        case .pounce: [.play, .later, .notNow]
        case .consent: [.revoke]
        case .status: []
        }
    }

    /// `action` is the response's action identifier (the default one for a tap on the body).
    public static func outcome(action: String, payload: PushPayload) -> NotifyOutcome {
        let tapped = action == defaultAction
        let chosen = NotifyAction(rawValue: action)
        guard tapped || chosen != nil else { return .none }
        if payload.kind == .consent || payload.category == .consent {
            guard let kitten = payload.kitten else { return .none }
            if tapped { return .kittens(kitten) }
            return chosen == .revoke ? .revokeConsent(kitten) : .none
        }
        if chosen == .revoke { return .none }
        if payload.kind == .pounce || payload.category == .pounce, let pounce = payload.pounce {
            switch chosen {
            case .later: return .answer(id: pounce.id, .later, opensApp: false)
            case .notNow: return .answer(id: pounce.id, .no, opensApp: false)
            case .inAnHour, .revoke: return .none
            case .play, nil:
                // A tap is Play (§12.4: opening it lands on the table they picked, or the pick sheet).
                if pounce.target == .pick || pounce.target == nil {
                    return .pick(id: pounce.id, target: pounce.target ?? .pick, from: payload.from)
                }
                return .answer(id: pounce.id, .play, opensApp: true)
            }
        }
        if chosen == .inAnHour { return .snooze(snoozeSeconds) }
        if chosen == .later || chosen == .notNow { return .none }
        return payload.code.map(NotifyOutcome.open) ?? .none
    }
}

/// How a push from a person becomes a communication notification (spec §12.5): the sender with
/// their cat as the avatar. The group name is the push's own title, so the title stays the name
/// of the person the push is for (§12.2, shared phones) and the sender shows beside it.
public struct CommunicationPlan: Equatable, Sendable {
    public var sender: PushFace
    public var groupName: String?
    public var conversation: String

    public init(sender: PushFace, groupName: String?, conversation: String) {
        self.sender = sender
        self.groupName = groupName
        self.conversation = conversation
    }

    /// Pushes a person sent: your move, a pounce, Play again and a pounce's answer.
    static let kinds: Set<PushKind> = [.yourMove, .pounce, .playAgain, .pounceAnswered]
    static let catCount = 8

    public static func make(_ payload: PushPayload) -> CommunicationPlan? {
        guard kinds.contains(payload.kind), var from = payload.from, !from.name.isEmpty else { return nil }
        if !(0..<catCount).contains(from.cat) { from.cat = 0 }
        let conversation = payload.threadId ?? payload.code ?? payload.pounce?.id ?? "pounce"
        return CommunicationPlan(sender: from, groupName: payload.title, conversation: conversation)
    }
}
