import PounceKit
import SwiftUI

/// One choice in the seat menu.
struct SeatMenuItem: Identifiable {
    let id: String
    let icon: String
    let color: Color
    /// The words on the pill (and what VoiceOver reads).
    let label: String
    let action: () -> Void
}

/// The menu for a tapped cushion (spec §5.5): a dimmed backdrop (tap to dismiss) and a card
/// with what the seat is and one worded pill per choice. It sits beside the cushion, toward
/// the rug's middle, and always whole on screen.
struct SeatMenu: View {
    /// What the seat is now ("Open seat", "Closed seat", a name).
    let title: String
    let center: CGPoint
    /// The card sits on this side of the cushion.
    let toward: CGPoint
    let items: [SeatMenuItem]
    let onDismiss: () -> Void

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 268

    var body: some View {
        GeometryReader { geo in
            let height = CGFloat(items.count) * 56 + 58
            let at = place(in: geo.size, height: height)
            ZStack {
                Palette.ink.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(verbatim: title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.violet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("seatmenu.title")
                    ForEach(items) { item in
                        PillButton(
                            icon: item.icon, color: item.color, size: .small, width: Self.width - 28,
                            title: item.label, accessibilityLabel: LocalizedStringKey(item.label)
                        ) {
                            item.action()
                        }
                        .accessibilityIdentifier("seatmenu.\(item.id)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(width: Self.width)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
                .scaleEffect(open || reduceMotion ? 1 : 0.6)
                .opacity(open ? 1 : 0)
                .position(at)
                .animation(reduceMotion ? .easeOut(duration: 0.15).paced : .spring(duration: 0.35, bounce: 0.4).paced, value: open)
            }
        }
        .onAppear {
            open = true
            Sound.shared.play(ArtName.Sound.sfxPop)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seatmenu")
        .accessibilityAction(.escape, onDismiss)
    }

    /// The card's center: a little toward the rug's middle from the cushion, kept on screen.
    private func place(in size: CGSize, height: CGFloat) -> CGPoint {
        let x = center.x + (toward.x - center.x) * 0.5
        let y = center.y + (toward.y - center.y) * 0.5
        let mx = Self.width / 2 + 8, my = height / 2 + 8
        return CGPoint(
            x: min(max(x, mx), max(mx, size.width - mx)),
            y: min(max(y, my), max(my, size.height - my)))
    }
}

/// "Who's sitting here?": the people on this phone not already at the table, plus a quick
/// "new person" (cat grid + name). Picking one claims the seat.
struct PersonPicker: View {
    let people: [Person]
    let ownerID: String?
    let onPick: (Person) -> Void
    /// On a kitten's device everyone added is a kitten (§14.1): no age pictures, dice names.
    var kittenDevice = false
    let onCreate: (String, Int, AgeBand) -> Void
    let onClose: () -> Void

    /// Adding someone: how old they are first (§14.1), then their name and cat.
    private enum Creating: Equatable { case age, person(AgeBand) }
    @State private var creating: Creating?

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            if creating == .age {
                AgeBandPicker(cat: freshCat(), onBack: { creating = nil }) { creating = .person($0) }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else if case .person(let band) = creating {
                CatEditorView(
                    initialName: "", initialCat: freshCat(), typedNames: band != .kitten,
                    onCancel: { creating = nil }
                ) { name, cat in
                    onCreate(name, cat, band)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                list.transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: creating)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-picker")
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") {
                    onClose()
                }
                .accessibilityIdentifier("picker.close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { i, person in
                        PersonTile(person: person, ringIndex: i, isOwner: person.id == ownerID) {
                            onPick(person)
                        }
                        .accessibilityIdentifier("picker.person.\(i)")
                    }
                    AddTile { creating = kittenDevice ? .person(.kitten) : .age }
                        .accessibilityIdentifier("picker.add")
                }
                .padding(24)
            }
        }
    }

    private func freshCat() -> Int {
        let used = Set(people.map(\.cat))
        return (0..<ArtName.catCount).first { !used.contains($0) } ?? 0
    }
}
