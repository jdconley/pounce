import PounceKit
import SwiftUI

/// The first-game coach on the table: a ring around the thing that matters right now and a
/// speech bubble from the player's own cat, beside it. Only the bubble takes touches: the table
/// under and around it keeps playing. "Got it" closes the tip; "No more tips" stops them for
/// the rest of this game.
struct CoachMark: View {
    let tip: CoachTip
    let coach: TableCoach
    let onOK: () -> Void
    let onOff: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private enum Placement { case above, below, beside }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let fullHeight = geo.size.height + insets.top + insets.bottom
            // Scene space (y up from the bottom of the whole screen) to this view's space.
            let local: (CGRect) -> CGRect = { r in
                CGRect(x: r.minX - insets.leading, y: fullHeight - r.maxY - insets.top, width: r.width, height: r.height)
            }
            let (ring, aim, placement) = target
            // Grown a little, but kept on screen (a card at the end of the fan sits on the edge).
            let ringRect = local(ring).insetBy(dx: -6, dy: -6)
                .intersection(CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: -insets.top))
            let aimRect = local(aim)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.ink, lineWidth: 8)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.lime, lineWidth: 4).padding(2))
                    .frame(width: ringRect.width, height: ringRect.height)
                    .scaleEffect(pulse ? 1.05 : 1)
                    .offset(x: ringRect.minX, y: ringRect.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                bubble(placement: placement, aim: aimRect, in: geo.size)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).paced) { pulse = true }
        }
    }

    /// What the ring goes around, what the bubble points at, and which side of it the bubble sits.
    private var target: (ring: CGRect, aim: CGRect, Placement) {
        let a = coach.anchors
        switch tip {
        case .goal: return (a.tower, a.tower, .above)
        case .draw: return (a.deck.union(a.discard), a.deck.union(a.discard), .below)
        case .phase, .run, .coat: return (a.trays, a.trays, .above)
        case .layDown: return (a.layDown ?? a.trays, a.layDown ?? a.trays, .above)
        case .discard: return (a.discard, a.discard, .below)
        case .hit: return (a.laid ?? a.hand, a.hand, .above)
        case .goOut: return (a.hand, a.hand, .above)
        case .cucumber: return (a.cucumber ?? a.hand, a.cucumber ?? a.hand, .above)
        case .yarn: return (a.yarn ?? a.hand, a.yarn ?? a.hand, .above)
        case .scores: return (a.openTower ?? a.tower, a.openTower ?? a.tower, .beside)
        case .cats: return (a.cats ?? a.hand, a.cats ?? a.hand, a.cats == nil ? .above : .below)
        case .swipeHome: return (a.edge, a.edge, .beside)
        }
    }

    private static let gap: CGFloat = 14
    private static let side: CGFloat = 16

    private func bubble(placement: Placement, aim: CGRect, in size: CGSize) -> some View {
        let beside = placement == .beside
        let width = beside
            ? max(min(size.width - aim.maxX - Self.gap - Self.side, 340), 220)
            : min(size.width - 2 * Self.side, 360)
        let x = beside
            ? aim.maxX + Self.gap
            : min(max(aim.midX - width / 2, Self.side), size.width - Self.side - width)
        // Where the arrow meets the bubble, along its edge.
        let arrowAt = beside ? 34 : min(max(aim.midX - x, 30), width - 30)
        return card(width: width, placement: placement, arrowAt: arrowAt)
            .frame(width: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement == .above ? .bottomLeading : .topLeading)
            .padding(.leading, x)
            .padding(.top, placement == .above ? 0 : max(top(placement, aim: aim), 4))
            .padding(.bottom, placement == .above ? max(size.height - aim.minY + Self.gap, 4) : 0)
    }

    /// The bubble's top below its target, or beside it: beside the tall tower it sits low,
    /// between the piles and the trays, so it covers neither.
    private func top(_ placement: Placement, aim: CGRect) -> CGFloat {
        placement == .below ? aim.maxY + Self.gap : aim.minY + aim.height * 0.55
    }

    private func card(width: CGFloat, placement: Placement, arrowAt: CGFloat) -> some View {
        let words = CoachCopy.words(tip, coach)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(ArtName.cat(coach.person.cat, .awake))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(words.title)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.violet)
                    Text(words.body)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coach.tip")
                .accessibilityValue(Text(verbatim: tip.rawValue))
            }
            HStack {
                Button {
                    Haptics.shared.tick()
                    onOff()
                } label: {
                    Text("No more tips", comment: "Coach bubble: stop the tips for the rest of this game")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .underline()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.off")
                Spacer(minLength: 8)
                PillButton(
                    icon: ArtName.iconCheck, color: Palette.lime, size: .small, width: 124,
                    title: String(localized: "Got it", comment: "Coach bubble: close this tip"),
                    accessibilityLabel: "Got it", action: onOK)
                    .accessibilityIdentifier("coach.ok")
            }
        }
        .padding(14)
        .background {
            BubbleShape(edge: placement, arrowAt: arrowAt)
                .fill(.white)
                .overlay(BubbleShape(edge: placement, arrowAt: arrowAt).stroke(Palette.ink, lineWidth: 4))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach")
    }

    /// A rounded box with a little arrow on the edge facing the target.
    private struct BubbleShape: Shape {
        let edge: Placement
        let arrowAt: CGFloat

        func path(in r: CGRect) -> Path {
            var p = Path(roundedRect: r, cornerRadius: 22)
            let a: CGFloat = 12
            switch edge {
            case .above:
                p.move(to: CGPoint(x: arrowAt - a, y: r.maxY - 1))
                p.addLine(to: CGPoint(x: arrowAt, y: r.maxY + a))
                p.addLine(to: CGPoint(x: arrowAt + a, y: r.maxY - 1))
            case .below:
                p.move(to: CGPoint(x: arrowAt - a, y: r.minY + 1))
                p.addLine(to: CGPoint(x: arrowAt, y: r.minY - a))
                p.addLine(to: CGPoint(x: arrowAt + a, y: r.minY + 1))
            case .beside:
                p.move(to: CGPoint(x: r.minX + 1, y: arrowAt - a))
                p.addLine(to: CGPoint(x: r.minX - a, y: arrowAt))
                p.addLine(to: CGPoint(x: r.minX + 1, y: arrowAt + a))
            }
            return p
        }
    }
}

/// The coach's words, and the rules sheet's names for phases.
enum CoachCopy {
    static func words(_ tip: CoachTip, _ coach: TableCoach) -> (title: String, body: String) {
        let reqs = coach.context.phase
        switch tip {
        case .goal:
            return (
                String(localized: "Hi, \(coach.person.name)!", comment: "Coach: the first tip's title, with the player's name"),
                String(
                    localized: "Lay down your level each round to climb. First to finish all ten wins.",
                    comment: "Coach: the goal of Cat Tower, pointing at the tower"))
        case .draw:
            return (
                String(localized: "Your turn", comment: "Coach: draw tip title"),
                String(
                    localized: "Take a card from the deck or the discard pile.",
                    comment: "Coach: how to draw, pointing at the two piles"))
        case .phase:
            let kinds = Set(reqs.map(\.kind))
            var body = String(
                localized: "This round: \(phase(reqs)). Drag cards into the trays.",
                comment: "Coach: the current level, e.g. 'two sets of 3', pointing at the trays")
            if kinds.contains(.set) {
                body += " " + String(localized: "Set: all one number.", comment: "Coach: what a set is")
            }
            if kinds.contains(.run) {
                body += " " + String(localized: "Run: numbers in a row.", comment: "Coach: what a run is")
            }
            if kinds.contains(.coat) {
                body += " " + String(localized: "One coat: the same cat on every card.", comment: "Coach: what a coat group is")
            }
            return (String(localized: "Your level", comment: "Coach: level tip title"), body)
        case .run:
            return (
                String(localized: "Runs", comment: "Coach: run tip title"),
                String(
                    localized: "Numbers in a row, like 4 5 6 7. Any coats.",
                    comment: "Coach: explains runs when a level first asks for one"))
        case .coat:
            let size = reqs.first { $0.kind == .coat }?.size ?? 7
            return (
                String(localized: "One coat", comment: "Coach: coat tip title"),
                String(
                    localized: "\(size) cards with the same cat. Any numbers.",
                    comment: "Coach: explains a coat group when a level first asks for one"))
        case .layDown:
            return (
                String(localized: "Ready!", comment: "Coach: lay-down tip title"),
                String(
                    localized: "Tap the paw to lay down your level.",
                    comment: "Coach: pointing at the lay-down paw above the trays"))
        case .discard:
            return (
                String(localized: "End your turn", comment: "Coach: discard tip title"),
                String(
                    localized: "Drag one card to the discard pile.",
                    comment: "Coach: how to end a turn, pointing at the discard pile"))
        case .hit:
            return (
                String(localized: "Add to the table", comment: "Coach: hit tip title"),
                String(
                    localized: "Drop cards on any laid group they fit.",
                    comment: "Coach: hitting, pointing at the laid-down groups"))
        case .goOut:
            return (
                String(localized: "Almost out", comment: "Coach: going-out tip title"),
                String(
                    localized: "Play or discard your last card to end the round.",
                    comment: "Coach: going out, pointing at the hand"))
        case .cucumber:
            return (
                String(localized: "Cucumber!", comment: "Coach: Cucumber tip title"),
                String(
                    localized: "Drop it on a cat to skip their next turn.",
                    comment: "Coach: the Cucumber skip card, pointing at it in the hand"))
        case .yarn:
            return (
                String(localized: "Yarn is wild", comment: "Coach: Yarn tip title"),
                String(
                    localized: "Yarn stands in for any number.",
                    comment: "Coach: the Yarn wild card, pointing at it in the hand"))
        case .scores:
            return (
                String(localized: "Scores", comment: "Coach: scoreboard tip title"),
                String(
                    localized: "Tap the tower again for scores and levels.",
                    comment: "Coach: the open tower's second tap, pointing at the open tower"))
        case .cats:
            return (
                String(localized: "Tap a cat", comment: "Coach: player card tip title"),
                String(
                    localized: "See how they're doing, or nudge them.",
                    comment: "Coach: tapping a player in the top bar opens their card, with Nudge"))
        case .swipeHome:
            return (
                String(localized: "Going Home", comment: "Coach: swipe home tip title"),
                String(
                    localized: "Swipe in from the left edge. Your game is saved.",
                    comment: "Coach: the left-edge swipe that leaves the table"))
        }
    }

    /// "two sets of 3", "a set of 3 and a run of 4", "7 cards of one coat".
    static func phase(_ reqs: [Requirement]) -> String {
        var parts: [(req: Requirement, count: Int)] = []
        for req in reqs {
            if let last = parts.last, last.req == req {
                parts[parts.count - 1].count += 1
            } else {
                parts.append((req, 1))
            }
        }
        let words = parts.map { group($0.req, count: $0.count) }
        guard words.count == 2 else { return words.joined(separator: ", ") }
        return String(localized: "\(words[0]) and \(words[1])", comment: "A level of two different groups, e.g. 'a set of 3 and a run of 4'")
    }

    private static func group(_ req: Requirement, count: Int) -> String {
        switch (req.kind, count) {
        case (.set, 1): String(localized: "a set of \(req.size)", comment: "A level group: one set")
        case (.set, _): String(localized: "two sets of \(req.size)", comment: "A level group: two sets of the same size")
        case (.run, 1): String(localized: "a run of \(req.size)", comment: "A level group: one run")
        case (.run, _): String(localized: "two runs of \(req.size)", comment: "A level group: two runs of the same size")
        case (.coat, _): String(localized: "\(req.size) cards of one coat", comment: "A level group: cards of one coat")
        }
    }
}

/// A one-time hint outside the table (Home's "press and hold to archive"): the words on a small
/// bubble with a "Got it" that puts it away for good.
struct HintBubble: View {
    let text: String
    let onOK: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: text)
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(
                icon: nil, color: Palette.lime, size: .small, width: 92,
                title: String(localized: "Got it", comment: "Coach bubble: close this tip"),
                accessibilityLabel: "Got it", action: onOK)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
        .padding(.horizontal, 16)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }
}
