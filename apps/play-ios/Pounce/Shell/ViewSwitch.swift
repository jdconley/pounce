import PounceKit
import SwiftUI

/// What a seated phone shows of a table (spec §3): the whole table as always, or, while a TV shows
/// it, just this phone's cards with a Cards/Table switch on top. Both games use it.
enum TableShown: Equatable {
    /// No TV (or no seat here): the full table and no switch.
    case plain
    /// A TV shows the table and this phone picked Cards (the default): just its cards.
    case cards
    /// A TV shows the table and this phone picked Table: the full table under the switch.
    case table

    /// `screen`: the room's TV flag. `seated`: this phone holds a seat. `choice`: this phone's pick
    /// for this table (`TableViewChoices`). The pick is kept while the TV is away, so a phone on
    /// Table stays on Table when it comes back.
    static func of(screen: Bool?, seated: Bool, choice: TablePick) -> TableShown {
        guard screen == true, seated else { return .plain }
        return choice == .cards ? .cards : .table
    }

    /// The Cards/Table switch is up.
    var hasSwitch: Bool { self != .plain }

    /// Game sounds are the TV's.
    var quiet: Bool { self == .cards }
}

/// The Cards/Table pick per table, kept on this phone (`TableViews`, written behind off the main
/// thread). Observable, so a table screen redraws when its pick changes.
@MainActor @Observable
final class TableViewChoices {
    @ObservationIgnored private let store: TableViews
    /// Bumped on every change (the store itself isn't observable).
    private var changes = 0

    init(_ loaded: Loaded<TableViews.File>) {
        store = TableViews(file: loaded.file, loaded: loaded.value)
        #if DEBUG
        // `-pick-table` (screenshots): the demo table opens on Table.
        if CommandLine.arguments.contains("-pick-table") { store.set(.table, code: DemoFixtures.code) }
        #endif
    }

    func view(code: String) -> TablePick {
        _ = changes
        return store.view(code: code)
    }

    func set(_ view: TablePick, code: String) {
        guard store.view(code: code) != view else { return }
        store.set(view, code: code)
        changes += 1
    }

    /// Waits for the writes so far (the app going to the background).
    func flush() async { await store.flush() }

    /// Where the file lives: Application Support, or a per-run folder for demos and UI tests (so a
    /// test's pick never carries into the next run).
    nonisolated static var directory: URL {
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-uitest-reset") || args.contains("-demo") {
            return URL.temporaryDirectory.appendingPathComponent("tableviews-\(ProcessInfo.processInfo.processIdentifier)")
        }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("Pounce", isDirectory: true)
    }
}

/// The "Cards" | "Table" pill at the top of a table a TV shows: one tap to see just your cards or
/// the whole table. Always in the same place in both, so it never jumps when it is used. Its
/// first showing carries a tip (`UITip.tableView`); tapping either side learns it.
struct ViewSwitch: View {
    let shown: TableShown
    let onPick: (TablePick) -> Void

    @Environment(\.dynamicTypeSize) private var type
    private var scale: CGFloat { ChromeType.scale(type, upTo: 1.35) }
    private var letters: CGFloat { 17 * scale }
    private var segment: CGFloat { 36 * scale }

    var body: some View {
        HStack(spacing: 0) {
            side(.cards, String(localized: "Cards", comment: "Table switch: show only this phone's cards (the table is on the TV)"))
            side(.table, String(localized: "Table", comment: "Table switch: show the whole table on this phone"))
        }
        .padding(3)
        .background(Capsule().fill(Palette.night.opacity(0.92)))
        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
        .compositingGroup()
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        .tipTarget(shown == .cards ? "table.view" : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.view")
    }

    private func side(_ view: TablePick, _ title: String) -> some View {
        let on = (shown == .cards) == (view == .cards)
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            onPick(view)
        } label: {
            Text(verbatim: title)
                .font(.system(size: letters, weight: .black, design: .rounded))
                .foregroundStyle(on ? Palette.ink : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, segment * 0.5)
                .frame(minWidth: segment * 1.8, minHeight: max(segment, 38))
                .background {
                    if on {
                        Capsule().fill(Palette.yellow)
                            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("table.view.\(view.rawValue)")
    }
}

/// The line under the switch on Cards: whose turn it is ("Your turn", "Ava's turn"), in toy
/// lettering, orange when it is this phone's. Shrinks to its band when the band is short (the
/// largest text sizes on a small phone).
struct StatusLine: View {
    let text: String
    let mine: Bool

    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        OutlinedText(text, size: 22 * ChromeType.scale(type, upTo: 1.5), fill: mine ? Palette.orange : .white, width: 3)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("table.status")
    }
}

/// How much the chrome of a table a TV shows grows with the person's text size: like the text,
/// up to a cap, so the switch, the status line and the action row still leave the cards room on
/// the smallest phone at the largest sizes.
enum ChromeType {
    static func scale(_ size: DynamicTypeSize, upTo cap: CGFloat) -> CGFloat {
        let scale: CGFloat = switch size {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        case .accessibility1: 1.5
        default: 1.65
        }
        return min(scale, cap)
    }
}
