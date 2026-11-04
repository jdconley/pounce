import PounceKit
import SwiftUI

/// One choice in the seat bubble.
struct SeatMenuItem: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let action: () -> Void
}

/// The radial bubble over a tapped cushion (spec §5.5): a dimmed backdrop (tap to dismiss)
/// and the choices fanned in a half ring around the cushion, opening toward the rug's middle
/// so it never runs off the screen edge.
struct SeatMenu: View {
    let center: CGPoint
    /// The fan opens toward this point.
    let toward: CGPoint
    let items: [SeatMenuItem]
    let onDismiss: () -> Void

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            let c = clamped(center, in: geo.size)
            ZStack {
                Palette.ink.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let p = offset(i, of: items.count)
                    PillButton(icon: item.icon, color: item.color, size: .small, width: 64, accessibilityLabel: item.label) {
                        item.action()
                    }
                    .accessibilityIdentifier("seatmenu.\(item.id)")
                    .scaleEffect(open ? 1 : 0.2)
                    .opacity(open ? 1 : 0)
                    .position(
                        x: c.x + (open || reduceMotion ? p.x : 0),
                        y: c.y + (open || reduceMotion ? p.y : 0))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.15).paced
                            : .spring(duration: 0.4, bounce: 0.5).delay(Double(i) * 0.04).paced,
                        value: open)
                }
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

    /// Spread over a half ring centered on the direction to `toward`.
    private func offset(_ i: Int, of n: Int) -> CGPoint {
        let dx = toward.x - center.x
        let dy = toward.y - center.y
        let facing = (dx == 0 && dy == 0) ? -Double.pi / 2 : atan2(Double(dy), Double(dx))
        let spread = Double.pi * 0.9
        let angle = n <= 1 ? facing : facing - spread / 2 + Double(i) * spread / Double(n - 1)
        return CGPoint(x: cos(angle) * Self.radius, y: sin(angle) * Self.radius)
    }

    /// Keeps the pills on screen.
    private func clamped(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let m: CGFloat = 40
        return CGPoint(
            x: min(max(p.x, m), max(m, size.width - m)),
            y: min(max(p.y, m), max(m, size.height - m)))
    }
}

/// "Who's sitting here?": the people on this phone not already at the table, plus a quick
/// "new person" (cat grid + name). Picking one claims the seat.
struct PersonPicker: View {
    let people: [Person]
    let ownerID: String?
    let onPick: (Person) -> Void
    let onCreate: (String, Int) -> Void
    let onClose: () -> Void

    @State private var creating = false

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            if creating {
                CatEditorView(
                    initialName: "", initialCat: freshCat(),
                    onCancel: { creating = false }
                ) { name, cat in
                    onCreate(name, cat)
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
                    AddTile { creating = true }
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
