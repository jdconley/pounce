import PounceKit
import SpriteKit
import UIKit

/// A VoiceOver element over a scene node that does something when activated.
final class BirdElement: UIAccessibilityElement {
    var onActivate: (@MainActor () -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        MainActor.assumeIsolated { onActivate() }
        return true
    }
}

/// Birdwatch's table for VoiceOver (design §3.3): the menu, each seat ("Mia, 7 cards, bid 85,
/// orange team, dealer, on the move"), the trick on the sill, trump, the score strip and every
/// card in the shown hand ("10, fish, 10 points", "Bird, 20 points, top trump"), dimmed ones
/// marked "can't play".
extension BirdScene {
    func accessibilityElements(in view: SKView) -> [UIAccessibilityElement] {
        if let cache = accessibilityCache, cache.version == accessibilityVersion { return cache.elements }
        guard let model, let layout else { return [] }
        var out: [UIAccessibilityElement] = []
        func element(_ id: String, _ label: String, frame: CGRect, hint: String? = nil, traits: UIAccessibilityTraits = .staticText,
                     action: (@MainActor () -> Void)? = nil) {
            let e = BirdElement(accessibilityContainer: view)
            e.accessibilityIdentifier = id
            e.accessibilityLabel = label
            e.accessibilityHint = hint
            e.accessibilityTraits = traits
            e.onActivate = action
            e.accessibilityFrameInContainerSpace = TableAccessibility.viewRect(frame, scene: self, view: view)
            out.append(e)
        }
        let names = SeatInfo.names(model.room)
        if !menuButton.isHidden {
            element("bird.menu", String(localized: "Menu", comment: "Birdwatch VoiceOver: the paw menu"), frame: menuButton.frame.insetBy(dx: -10, dy: -10),
                    traits: .button) { [weak self] in self?.onMenu() }
        }
        for seat in barSeats {
            guard let node = seatNodes[seat] else { continue }
            var parts = [names[safe: seat] ?? ""]
            if node.seat == seat, let count = model.view.handCounts[safe: seat] {
                parts.append(String(localized: "\(count) cards", comment: "Birdwatch VoiceOver: a seat's card count"))
            }
            switch model.sign(seat) {
            case .bid(let n): parts.append(String(localized: "bid \(n)", comment: "Birdwatch VoiceOver: a seat's bid"))
            case .pass: parts.append(String(localized: "passed", comment: "Birdwatch VoiceOver: a seat passed"))
            case .made(let n): parts.append(String(localized: "made \(n)", comment: "Birdwatch VoiceOver: a seat made its bid"))
            case .missed(let n): parts.append(String(localized: "missed \(n)", comment: "Birdwatch VoiceOver: a seat missed its bid"))
            case nil: break
            }
            if let ribbon = model.ribbon(of: seat) { parts.append(Self.teamWords(ribbon)) }
            if model.view.dealer == seat { parts.append(String(localized: "dealer", comment: "Birdwatch VoiceOver: the seat dealt")) }
            if model.currentSeat == seat { parts.append(String(localized: "on the move", comment: "Birdwatch VoiceOver: the seat to act")) }
            if model.room.seats[safe: seat]?.isTakenOver == true {
                parts.append(String(localized: "left, a House Cat plays", comment: "Birdwatch VoiceOver: a seat a House Cat took over"))
            }
            if !isScreen, model.partnerMark(for: seat, revealed: shownSeat) {
                parts.append(String(localized: "partner", comment: "Birdwatch VoiceOver: the partner's own mark"))
            }
            let side = node.side
            element("bird.seat.\(seat)", parts.joined(separator: ", "),
                    frame: CGRect(x: node.position.x - side / 2, y: node.position.y - side * 0.8, width: side, height: side * 1.3))
        }
        if layout.mode != .handOnly {
            let trick = model.view.trick.map { played in
                String(localized: "\(BirdTableModel.label(played.card)) from \(names[safe: played.seat] ?? "")",
                       comment: "Birdwatch VoiceOver: one card on the sill and who played it")
            }
            let sill = trick.isEmpty
                ? String(localized: "Sill, empty", comment: "Birdwatch VoiceOver: no cards played this trick")
                : String(localized: "Sill: \(trick.joined(separator: "; "))", comment: "Birdwatch VoiceOver: the cards on the sill")
            element("bird.sill", sill, frame: layout.sill.insetBy(dx: layout.sill.width * 0.2, dy: layout.sill.height * 0.25))
            if let trump = model.view.trump {
                element("bird.trump", String(localized: "Trump: \(BirdTableModel.suitName(trump))", comment: "Birdwatch VoiceOver: the trump badge"),
                        frame: CGRect(x: layout.trumpBadge.x - 24, y: layout.trumpBadge.y - 24, width: 48, height: 48))
            }
        }
        if !stripFrames.isEmpty, let first = stripFrames.first, let last = stripFrames.last {
            let scores = model.sides.map { side in
                let who = side.ribbon.map(Self.teamWords) ?? (names[safe: side.seats.first ?? 0] ?? "")
                return String(localized: "\(who) \(side.score)", comment: "Birdwatch VoiceOver: one side's score")
            }
            element("bird.scores", String(localized: "Scores: \(scores.joined(separator: ", "))", comment: "Birdwatch VoiceOver: the score strip"),
                    frame: first.union(last), hint: String(localized: "Opens the score sheet", comment: "Birdwatch VoiceOver hint"),
                    traits: .button) { [weak self] in self?.onScores() }
        }
        if let seat = shownSeat, !isScreen, model.partnerMark(for: seat, revealed: shownSeat) {
            let w: CGFloat = 220
            let frame = layout.mode == .handOnly
                ? CGRect(x: layout.hand.midX - w / 2, y: layout.hand.maxY, width: w, height: 30)
                : CGRect(x: layout.sill.midX - w / 2, y: layout.sill.maxY - 34, width: w, height: 30)
            element("bird.partner.mark", String(localized: "You're the partner", comment: "Birdwatch: over the partner's own hand (five players)"),
                    frame: frame)
        }
        if let seat = shownSeat {
            let playable = model.playable(seat)
            let myPlay = model.view.phase == .play && model.currentSeat == seat
            let nest = model.view.phase == .nest && model.currentSeat == seat
            for (i, card) in handShown.enumerated() {
                guard let node = handNodes[card], !node.isHidden else { continue }
                var label = BirdTableModel.label(card)
                if myPlay, !playable.contains(card) {
                    label += String(localized: ", can't play", comment: "Birdwatch VoiceOver: a dimmed card")
                }
                if nest, putBack.contains(card) {
                    label += String(localized: ", putting back", comment: "Birdwatch VoiceOver: a card marked to put back")
                }
                // Each card's own part: what shows of it under the next card in its row, and above
                // the front row when it sits in the back one.
                var frame = node.frame
                if i + 1 < handShown.count, let next = handNodes[handShown[i + 1]], abs(next.position.y - node.position.y) < 2 {
                    frame.size.width = max(next.frame.minX - frame.minX, 20)
                }
                let front = handShown[(i + 1)...].compactMap { handNodes[$0] }
                    .filter { $0.position.y < node.position.y - 2 && $0.frame.intersects(frame) }
                if let top = front.map(\.frame.maxY).max(), top < frame.maxY - 16 {
                    frame = CGRect(x: frame.minX, y: top, width: frame.width, height: frame.maxY - top)
                }
                let hint: String? = if myPlay, playable.contains(card) {
                    String(localized: "Double tap to play", comment: "Birdwatch VoiceOver hint: a playable card")
                } else if nest {
                    String(localized: "Double tap to put back or keep", comment: "Birdwatch VoiceOver hint: a card in the put-back")
                } else { nil }
                element("bird.card.\(card)", label, frame: frame, hint: hint, traits: hint == nil ? .staticText : .button) { [weak self] in
                    guard let self, let model = self.model, let seat = self.shownSeat else { return }
                    if model.view.phase == .play { self.play(card) } else { self.tap(card, model: model, seat: seat) }
                }
            }
        }
        #if DEBUG
        // Hand cards that popped to another size between two frames: "<blips>|<the last few>".
        let sizes = TableElement(accessibilityContainer: view)
        sizes.accessibilityIdentifier = "bird.sizes"
        sizes.accessibilityLabel = "sizes"
        sizes.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: 2, height: 2)
        sizes.liveValue = { [weak self] in self?.sizeWatch.probe }
        out.append(sizes)
        #endif
        accessibilityCache = (accessibilityVersion, out)
        return out
    }

    static func teamWords(_ ribbon: BirdTableModel.Ribbon) -> String {
        switch ribbon {
        case .orange: String(localized: "orange team", comment: "Birdwatch VoiceOver: a team by its ribbon")
        case .teal: String(localized: "teal team", comment: "Birdwatch VoiceOver: a team by its ribbon")
        case .magenta: String(localized: "pink team", comment: "Birdwatch VoiceOver: a team by its ribbon")
        case .gold: String(localized: "bidding side", comment: "Birdwatch VoiceOver: the bid winner and partner in five")
        }
    }
}

/// How a side is named on screen: its players' names ("Mia & Leo"), a lone player's own.
enum BirdWords {
    static func side(_ side: BirdTableModel.Side, room: RoomView) -> String {
        side.seats.map { SeatInfo.name(room, $0) }.joined(separator: " & ")
    }

    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    static func rules(_ rules: BirdRules) -> String {
        switch rules {
        case .official: String(localized: "Official", comment: "Birdwatch rule set name")
        case .tucker: String(localized: "Tucker", comment: "Birdwatch rule set name (a family's house rules)")
        case .friesen: String(localized: "Friesen", comment: "Birdwatch rule set name (a family's house rules)")
        }
    }

    /// The one line under a rule set's pill (design §5.1).
    static func rulesLine(_ rules: BirdRules) -> String {
        switch rules {
        case .official: String(localized: "1s out, Bird wild.", comment: "Birdwatch lobby: the Official rule set in one line")
        case .tucker: String(localized: "1s high, worth 15.", comment: "Birdwatch lobby: the Tucker rule set in one line")
        case .friesen: String(localized: "1s high, Bird follows suit.", comment: "Birdwatch lobby: the Friesen rule set in one line")
        }
    }
}

