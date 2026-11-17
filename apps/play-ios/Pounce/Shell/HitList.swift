import PounceKit
import SwiftUI

/// The action row on Cards (a TV shows the table, this phone just its cards): what can be done
/// with the hand right now, in one row between the piles and the trays. Lay down once the trays
/// are ready; with a card picked that can hit, one chip per group it can go on ("Mom's 3s",
/// "Your run"). Picking a chip lights that group on the TV; Hit plays it, Cancel puts the
/// choice back. Nothing at all when there is nothing to do.
struct ControllerActions: View {
    let offer: ControllerOffer
    /// The group picked from the list (it glows on the TV).
    let picked: HitTarget?
    let onPick: (HitTarget) -> Void
    let onHit: () -> Void
    let onCancel: () -> Void
    let onLayDown: () -> Void

    var body: some View {
        Group {
            if let hit = offer.hit {
                HitList(hit: hit, picked: picked, onPick: onPick, onHit: onHit, onCancel: onCancel)
            } else if offer.layDown {
                ActionPill(
                    title: String(localized: "Lay down", comment: "Table on Cards: lay the ready trays down"),
                    style: .go, action: onLayDown)
                    .fixedSize()
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
        // One line, centred: tighter chips when they don't fit, and sideways scrolling only when
        // even those don't (many targets, big text).
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
            ScrollView(.horizontal, showsIndicators: false) { row(compact: true).padding(.horizontal, 4) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hit.list")
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            if let picked, let choice = hit.choices.first(where: { $0.target == picked }) {
                ActionPill(
                    title: String(localized: "Cancel", comment: "Hit list on Cards: put the picked group back"),
                    style: .quiet, compact: compact, action: onCancel)
                    .accessibilityIdentifier("hit.cancel")
                chip(choice, on: true, compact: compact)
                ActionPill(
                    title: String(localized: "Hit", comment: "Hit list on Cards: play the picked card on the picked group"),
                    style: .go, compact: compact, action: onHit)
                    .accessibilityIdentifier("hit.confirm")
            } else {
                ForEach(hit.choices, id: \.target) { choice in chip(choice, on: false, compact: compact) }
            }
        }
        .fixedSize()
    }

    private func chip(_ choice: HitChoice, on: Bool, compact: Bool) -> some View {
        ActionPill(title: Self.label(choice, in: hit.model), style: on ? .picked : .chip, compact: compact) {
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
    /// Smaller lettering and less padding, the same height (a row that is short of width).
    var compact = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var type
    private var letters: CGFloat { (compact ? 15 : 17) * ChromeType.scale(type, upTo: 1.5) }
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
                .padding(.horizontal, face * (compact ? 0.22 : 0.3))
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
