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
        return botName
    }

    static var botName: String { String(localized: "House Cat", comment: "The bot player's name") }

    /// Every seat's name as the table shows it (bots numbered when there are several).
    static func names(_ room: RoomView) -> [String] {
        SeatNames.names(room.seats, bot: botName)
    }

    /// Seat `seat`'s shown name, "" for an empty seat.
    static func name(_ room: RoomView, _ seat: Seat) -> String {
        names(room)[safe: seat] ?? ""
    }

    /// "Mia, 6 cards, phase 3, laid down, asleep" (what the cat's two chips say, in words).
    static func label(_ view: SeatView?, name: String? = nil, cards: Int?, phase: PhaseMark?) -> String {
        var parts = [name ?? self.name(view)]
        if let cards {
            parts.append(String(localized: "\(cards) cards", comment: "VoiceOver: a player's card count"))
        }
        if let phase {
            if let number = phase.number {
                parts.append(String(localized: "level \(number)", comment: "VoiceOver: a player's level, 1 to 10"))
            } else {
                parts.append(String(
                    localized: "all \(Rules.phases.count) levels done",
                    comment: "VoiceOver: a player who finished every level"))
            }
            if phase.laid {
                parts.append(String(localized: "laid down", comment: "VoiceOver: a player laid this round's level down"))
            }
        }
        switch view?.kind == .bot ? nil : view?.presence {
        case .awake: parts.append(String(localized: "awake", comment: "VoiceOver: presence"))
        case .away: parts.append(String(localized: "away", comment: "VoiceOver: presence"))
        case .asleep: parts.append(String(localized: "asleep", comment: "VoiceOver: presence"))
        case nil: if view?.kind == .bot { parts.append(String(localized: "bot", comment: "VoiceOver: a bot player")) }
        }
        // VoiceOver hears "Weak signal" in full; the tag on screen is one word.
        if let link = LinkWords.seat(view?.link) { parts.append(link.level == .weak ? LinkWords.weak() : link.text) }
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
        var hint: String? = nil
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
            e.accessibilityHint = item.hint
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

extension TableScene {
    /// Posts a short VoiceOver announcement for a turn change or a big event (spec §13).
    func announce(_ announcement: TableAnnouncement) {
        guard let model else { return }
        let text = Self.sentence(announcement, seats: model.room.seats)
        #if DEBUG
        timelineLog("announce \(text)")
        #endif
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func sentence(_ announcement: TableAnnouncement, seats: [SeatView]) -> String {
        let names = SeatNames.names(seats, bot: SeatInfo.botName)
        func name(_ seat: Seat) -> String { names[safe: seat] ?? SeatInfo.botName }
        switch announcement {
        case .yourTurn(let seat, let multiSeat):
            return multiSeat
                ? String(localized: "\(name(seat)), your turn", comment: "VoiceOver announcement: a pass-and-play seat's turn came")
                : String(localized: "Your turn", comment: "VoiceOver announcement: this phone's turn came")
        case .roundOver(let mine):
            switch mine.count {
            case 0:
                return String(localized: "Round over", comment: "VoiceOver announcement: the round ended")
            case 1:
                return String(
                    localized: "Round over. You took \(mine[0].points) points",
                    comment: "VoiceOver announcement: the round ended and the points this phone's player took")
            default:
                let each = mine.map {
                    String(localized: "\(name($0.seat)) \($0.points) points", comment: "VoiceOver: one seat's points in the round-over announcement")
                }
                return String(
                    localized: "Round over. \(each.formatted(.list(type: .and)))",
                    comment: "VoiceOver announcement: the round ended, with each of this phone's players' points")
            }
        case .gameOver(let winners):
            let names = winners.map(name).formatted(.list(type: .and))
            return winners.count > 1
                ? String(localized: "\(names) win", comment: "VoiceOver announcement: the game ended in a tie")
                : String(localized: "\(names) wins", comment: "VoiceOver announcement: the game ended; who won")
        case .forfeited(let seat, let mine):
            // A shared phone names the seat; a phone with one seat says "you".
            return mine && seats.filter(\.yours).count == 1
                ? String(localized: "You forfeited", comment: "VoiceOver announcement: this phone's player forfeited")
                : String(localized: "\(name(seat)) forfeited", comment: "VoiceOver announcement: a player forfeited")
        }
    }
}
