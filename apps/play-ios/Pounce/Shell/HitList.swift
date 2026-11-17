import PounceKit
import SwiftUI

/// The action row on Cards (a TV shows the table, this phone just its cards): what can be done
/// with the hand right now, on the trays. Lay down once the trays are ready; with a card picked
/// that can hit, one chip per group it can go on ("Mom's 3s", "Your run"): picking one lights that
/// group on the TV, Hit plays it, Cancel puts the choice back; with a Cucumber picked, one chip per
/// player it can skip ("Skip Leo"), which discards it at them. Nothing when there is nothing to do.
/// The chips wrap onto more lines rather than run off the screen (`FlowRows`); the table measures
/// how tall that makes the row and makes room for it.
struct ControllerActions: View {
    let offer: ControllerOffer
    /// The group picked from the list (it glows on the TV).
    let picked: HitTarget?
    let onPick: (HitTarget) -> Void
    let onHit: () -> Void
    let onCancel: () -> Void
    let onSkip: (Seat) -> Void
    let onLayDown: () -> Void

    var body: some View {
        // Past the lines the table makes room for (many targets at the largest text), it scrolls,
        // and says so with its scroll bar.
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }
                .scrollIndicatorsFlash(onAppear: true)
        }
    }

    @ViewBuilder var content: some View {
        if let hit = offer.hit {
            HitList(hit: hit, picked: picked, onPick: onPick, onHit: onHit, onCancel: onCancel)
        } else if let skip = offer.skip {
            FlowRows {
                ForEach(skip.seats, id: \.self) { seat in
                    ActionPill(
                        title: String(
                            localized: "Skip \(SeatInfo.name(skip.model.room, seat))",
                            comment: "Action row on Cards: discard the picked Cucumber at a player, who misses a turn"),
                        style: .chip) { onSkip(seat) }
                        .accessibilityIdentifier("skip.target.\(seat)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("skip.list")
        } else if offer.layDown {
            FlowRows {
                ActionPill(
                    title: String(localized: "Lay down", comment: "Table on Cards: lay the ready trays down"),
                    style: .go, action: onLayDown)
                    .accessibilityIdentifier("table.laydown.row")
            }
        }
    }
}

/// The picked card's legal targets as chips, or, once one is picked, Cancel, that chip and Hit.
struct HitList: View {
    let hit: ControllerOffer.Hit
    let picked: HitTarget?
    let onPick: (HitTarget) -> Void
    let onHit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        FlowRows {
            if let picked, let choice = hit.choices.first(where: { $0.target == picked }) {
                ActionPill(
                    title: String(localized: "Cancel", comment: "Hit list on Cards: put the picked group back"),
                    style: .quiet, action: onCancel)
                    .accessibilityIdentifier("hit.cancel")
                chip(choice, on: true)
                ActionPill(
                    title: String(localized: "Hit", comment: "Hit list on Cards: play the picked card on the picked group"),
                    style: .go, action: onHit)
                    .accessibilityIdentifier("hit.confirm")
            } else {
                ForEach(hit.choices, id: \.target) { choice in chip(choice, on: false) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hit.list")
    }

    private func chip(_ choice: HitChoice, on: Bool) -> some View {
        ActionPill(title: Self.label(choice, in: hit.model), style: on ? .picked : .chip) {
            if !on { onPick(choice.target) }
        }
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("hit.target.\(choice.target.seat).\(choice.target.group)")
    }

    /// "Mom's 3s", "Your run", "Ava's run of 7s", "Leo's tabbies"; a number after it when two
    /// would still read the same.
    static func label(_ choice: HitChoice, in model: TableModel) -> String {
        let name = SeatInfo.name(model.room, choice.target.seat)
        let base: String
        switch (choice.kind, choice.mine) {
        case (.set(let value), true):
            base = String(localized: "Your \(value)s", comment: "Hit list chip: your own set of a number, e.g. 'Your 9s'")
        case (.set(let value), false):
            base = String(localized: "\(name)'s \(value)s", comment: "Hit list chip: a player's set of a number, e.g. 'Mom's 3s'")
        case (.run(let start), true):
            base = choice.detail == .plain
                ? String(localized: "Your run", comment: "Hit list chip: your own run")
                : String(localized: "Your run of \(start)s", comment: "Hit list chip: one of your runs, by its lowest number")
        case (.run(let start), false):
            base = choice.detail == .plain
                ? String(localized: "\(name)'s run", comment: "Hit list chip: a player's run")
                : String(localized: "\(name)'s run of \(start)s", comment: "Hit list chip: one of a player's runs, by its lowest number, e.g. 'Ava's run of 7s'")
        case (.coat(let coat), let mine):
            base = coatLabel(coat, owner: mine ? nil : name)
        }
        if case .ordinal(let n) = choice.detail { return "\(base) \(n)" }
        return base
    }

    private static func coatLabel(_ coat: Coat, owner name: String?) -> String {
        guard let name else {
            return switch coat {
            case .tabby: String(localized: "Your tabbies", comment: "Hit list chip: your own group of tabby cards")
            case .tuxedo: String(localized: "Your tuxedos", comment: "Hit list chip: your own group of tuxedo cards")
            case .calico: String(localized: "Your calicos", comment: "Hit list chip: your own group of calico cards")
            case .gray: String(localized: "Your grays", comment: "Hit list chip: your own group of gray cards")
            }
        }
        return switch coat {
        case .tabby: String(localized: "\(name)'s tabbies", comment: "Hit list chip: a player's group of tabby cards")
        case .tuxedo: String(localized: "\(name)'s tuxedos", comment: "Hit list chip: a player's group of tuxedo cards")
        case .calico: String(localized: "\(name)'s calicos", comment: "Hit list chip: a player's group of calico cards")
        case .gray: String(localized: "\(name)'s grays", comment: "Hit list chip: a player's group of gray cards")
        }
    }
}

/// One candy pill of the action row: a word in rounded black on a colored capsule with an ink
/// outline and a lip. It grows with the text size (`ChromeType`), and the table's layout measures it.
struct ActionPill: View {
    enum Style {
        /// A target to pick.
        case chip
        /// The picked target.
        case picked
        /// The move itself (Hit, Lay down).
        case go
        /// Backing out (Cancel).
        case quiet
    }

    let title: String
    let style: Style
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var type
    private var letters: CGFloat { 17 * ChromeType.scale(type, upTo: 1.5) }
    private var face: CGFloat { 40 * ChromeType.scale(type, upTo: 1.5) }
    private static let lip: CGFloat = 4

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            Text(verbatim: title)
                .font(.system(size: letters, weight: .black, design: .rounded))
                .foregroundStyle(style == .quiet ? .white : Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
                .padding(.horizontal, face * 0.3)
                .frame(minWidth: 64, minHeight: face)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                .compositingGroup()
                .shadow(color: Palette.ink.opacity(0.7), radius: 0, x: 0, y: Self.lip)
                .padding(.bottom, Self.lip)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        switch style {
        case .chip: .white
        case .picked: Palette.yellow
        case .go: Palette.lime
        case .quiet: Palette.night
        }
    }
}

/// Pills in centred lines, as many to a line as fit the width, wrapping onto the next line rather
/// than running off the edge (a pill wider than a line is cut to it, its words truncated).
struct FlowRows: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = lines(subviews, width: bounds.width)
        let total = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        var y = bounds.midY - total / 2
        for line in lines {
            var x = bounds.midX - line.width / 2
            for (index, size) in line.items {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (index, subview) in subviews.enumerated() {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, needed > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append((index, size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
