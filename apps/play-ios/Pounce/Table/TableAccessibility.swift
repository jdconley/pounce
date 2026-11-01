import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// Who sits in a seat, for drawing and speaking.
enum SeatInfo {
    /// The House Cat bot uses the gray cat (ruling B).
    static let botCat = 3

    static func catIndex(_ seat: SeatView?) -> Int {
        guard let seat else { return botCat }
        if seat.kind == .bot { return botCat }
        return seat.person?.cat ?? botCat
    }

    static func ringColor(_ seat: Seat) -> Color {
        Palette.playerRings[((seat % Palette.playerRings.count) + Palette.playerRings.count) % Palette.playerRings.count]
    }

    static func name(_ seat: SeatView?) -> String {
        if let name = seat?.person?.name { return name }
        return String(localized: "House Cat", comment: "VoiceOver: the bot player's name")
    }

    /// "Mia, 6 cards, phase 3, asleep".
    static func label(_ view: SeatView?, cards: Int?, phase: Int?) -> String {
        var parts = [name(view)]
        if let cards {
            parts.append(String(localized: "\(cards) cards", comment: "VoiceOver: a player's card count"))
        }
        if let phase {
            parts.append(String(localized: "phase \(min(phase + 1, 10))", comment: "VoiceOver: a player's phase, 1 to 10"))
        }
        switch view?.kind == .bot ? nil : view?.presence {
        case .awake: parts.append(String(localized: "awake", comment: "VoiceOver: presence"))
        case .away: parts.append(String(localized: "away", comment: "VoiceOver: presence"))
        case .asleep: parts.append(String(localized: "asleep", comment: "VoiceOver: presence"))
        case nil: if view?.kind == .bot { parts.append(String(localized: "bot", comment: "VoiceOver: a bot player")) }
        }
        return parts.joined(separator: ", ")
    }
}

/// An accessibility element whose value is read live (the frame counter changes while the
/// element list stays put).
final class TableElement: UIAccessibilityElement {
    var liveValue: (@MainActor () -> String?)?

    override var accessibilityValue: String? {
        get { MainActor.assumeIsolated { liveValue?() } ?? super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }
}

/// Builds the table's accessibility elements from the scene's nodes. SpriteKit nodes aren't
/// views, so each interactive node gets a `UIAccessibilityElement` with a frame converted from
/// scene space; the SKView returns this list as its `accessibilityElements`.
@MainActor
enum TableAccessibility {
    struct Item {
        var id: String
        var label: String
        var value: String? = nil
        var frame: CGRect  // scene space
        var traits: UIAccessibilityTraits = .button
        var live: (@MainActor () -> String?)? = nil
        /// VoiceOver custom actions ("Discard", "Put in tray 1", "Add to group", "Draw").
        var actions: [UIAccessibilityCustomAction] = []
    }

    static func elements(_ items: [Item], scene: SKScene, view: SKView) -> [UIAccessibilityElement] {
        items.map { item in
            let e = TableElement(accessibilityContainer: view)
            e.accessibilityIdentifier = item.id
            e.accessibilityLabel = item.label
            e.accessibilityValue = item.value
            e.accessibilityTraits = item.traits
            e.liveValue = item.live
            e.accessibilityCustomActions = item.actions.isEmpty ? nil : item.actions
            e.accessibilityFrameInContainerSpace = viewRect(item.frame, scene: scene, view: view)
            return e
        }
    }

    /// Scene rect (y up) to view rect (y down).
    static func viewRect(_ r: CGRect, scene: SKScene, view: SKView) -> CGRect {
        let a = scene.convertPoint(toView: CGPoint(x: r.minX, y: r.maxY))
        let b = scene.convertPoint(toView: CGPoint(x: r.maxX, y: r.minY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
