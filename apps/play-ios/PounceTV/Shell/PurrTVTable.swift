import PounceKit
import SwiftUI

/// Purrtrait on the TV (spec §11.1): the easel in the middle at full height, in its magenta frame;
/// every player's cat, name and score on the left, the drawer's highlighted; who is drawing, the
/// clock and the word's group on the right. The lines come live from the drawer's phone. When
/// someone gets it their cat jumps and the word shows big across the easel. The word is never on
/// the TV before the turn ends: the TV's view has none.
struct PurrTVTable: View {
    let table: TVRoom

    @State private var arrived = Date()
    @State private var overSent = false

    private var room: RoomView? { table.store.room }
    private var view: PurrView? { room?.purrtrait }

    var body: some View {
        GeometryReader { g in
            if let room, let view {
                let easelHeight = g.size.height - 120
                let easelWidth = easelHeight * 0.75
                let side = max((g.size.width - easelWidth - 160) / 2, 360)
                HStack(spacing: 40) {
                    PurrTVScores(room: room, view: view)
                        .frame(width: side, height: easelHeight)
                    ZStack {
                        PurrEaselFrame(border: 16) {
                            PurrTVEasel(feed: table.store.ink)
                        }
                        .frame(width: easelWidth, height: easelHeight)
                        if view.phase == .reveal || view.phase == .over, let last = view.last {
                            PurrTVReveal(room: room, last: last)
                                .frame(width: easelWidth, height: easelHeight)
                                .compositingGroup()
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                                .id(view.turn)
                        }
                    }
                    PurrTVTurn(room: room, view: view, deadline: deadline(view))
                        .frame(width: side, height: easelHeight)
                }
                .frame(width: g.size.width, height: g.size.height)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: view.phase)
            }
        }
        .overlay(alignment: .topLeading) {
            if table.reconnecting { TVReconnecting().padding(40) }
        }
        .onChange(of: ClockKey(view: view), initial: true) { arrived = Date() }
        .onChange(of: view?.phase == .over, initial: true) { _, over in
            // The last word stays up a moment, then game over comes over the table.
            guard over, !overSent else { return }
            overSent = true
            let winners = view?.winners ?? []
            Task {
                try? await Task.sleep(for: Pace.duration(.seconds(3)))
                table.gameOver(winners)
            }
        }
        .onChange(of: view?.last?.guesser) { _, guesser in
            guard guesser != nil else { return }
            Sound.shared.play(ArtName.Sound.sfxFanfare, volume: 0.8)
        }
        #if DEBUG
        // SwiftUI and layers, no SpriteKit table: its frames and hangs count as gameplay.
        .onAppear { MainThreadWatchdog.shared?.screen(true) }
        .onDisappear { MainThreadWatchdog.shared?.screen(false) }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.purrtrait")
    }

    private struct ClockKey: Equatable {
        var turn: String?
        var phase: PurrPhase?
        var remaining: Int?
        var paused: Bool?

        init(view: PurrView?) {
            turn = view?.turn
            phase = view?.phase
            remaining = view?.remainingMs
            paused = view?.paused
        }
    }

    private func deadline(_ view: PurrView) -> Date? {
        guard !view.paused, let ms = view.remainingMs else { return nil }
        return arrived.addingTimeInterval(Double(ms) / 1000)
    }
}

/// The live easel: the room's ink, drawn by the shared easel view.
struct PurrTVEasel: UIViewRepresentable {
    let feed: InkFeed

    func makeUIView(context: Context) -> PurrEaselView {
        let view = PurrEaselView(frame: .zero)
        view.accessibilityLabel = String(localized: "The drawing", comment: "TV: VoiceOver, Purrtrait's easel")
        view.accessibilityIdentifier = "tv.purr.easel"
        context.coordinator.follower = PurrInkFollower(feed: feed, view: view)
        return view
    }

    func updateUIView(_ view: PurrEaselView, context: Context) {}

    static func dismantleUIView(_ view: PurrEaselView, coordinator: Coordinator) {
        coordinator.follower?.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var follower: PurrInkFollower?
    }
}

/// Every player's cat, name and score, the drawer's highlighted.
private struct PurrTVScores: View {
    let room: RoomView
    let view: PurrView

    var body: some View {
        let seats = (0..<min(view.seats, room.seats.count)).filter { room.seats[$0].kind == .human }
        let big = seats.count <= 6
        VStack(alignment: .leading, spacing: big ? 16 : 8) {
            ForEach(seats, id: \.self) { seat in
                let drawing = seat == view.drawer
                HStack(spacing: 16) {
                    Image(ArtName.cat(SeatInfo.catIndex(room.seats[seat]), drawing ? .celebrate : .awake))
                        .resizable().scaledToFit()
                        .frame(width: big ? 84 : 62, height: big ? 84 : 62)
                    NameTag(SeatInfo.name(room, seat), maxWidth: big ? 230 : 210, active: drawing, size: big ? 28 : 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OutlinedText("\(view.scores[safe: seat] ?? 0)", size: big ? 44 : 34, fill: drawing ? Palette.yellow : .white, width: 4)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: view.scores[safe: seat])
                }
                .padding(.horizontal, 18)
                .padding(.vertical, big ? 8 : 4)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(drawing ? tvRing(seat).opacity(0.85) : Palette.ink.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(drawing ? Color.white : .clear, lineWidth: 5))
                .opacity(view.isOut(seat) ? 0.45 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(SeatInfo.name(room, seat)), \(view.scores[safe: seat] ?? 0)"))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Who is drawing, the clock and the word's group.
private struct PurrTVTurn: View {
    let room: RoomView
    let view: PurrView
    let deadline: Date?

    var body: some View {
        // The turn and its reveal are one layer each: the old one goes at once and the new one
        // fades in whole, so the drawer's name never shows through the points.
        panel
            .compositingGroup()
            .id(view.phase == .reveal ? "reveal \(view.turn)" : "turn \(view.turn)")
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .frame(maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(spacing: 36) {
            if let drawer = view.drawer, view.phase == .choosing || view.phase == .drawing {
                let name = SeatInfo.name(room, drawer)
                Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: drawer]), .awake))
                    .resizable().scaledToFit().frame(width: 190, height: 190)
                OutlinedText(view.phase == .choosing ? PurrWords.isPicking(name) : PurrWords.isDrawing(name),
                             size: 50, fill: .white, width: 4, lines: 2)
                    .accessibilityIdentifier("tv.purr.turn")
                if view.paused {
                    OutlinedText(PurrWords.waitingForTV, size: 34, fill: Palette.yellow, width: 3, lines: 2)
                } else {
                    PurrClock(deadline: deadline, frozen: view.remainingMs.map { $0 / 1000 }, size: 64)
                }
                if view.phase == .drawing, let group = view.group {
                    OutlinedText(PurrWords.group(group), size: 48, fill: .white, width: 4)
                        .padding(.horizontal, 34).padding(.vertical, 12)
                        .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 6)))
                        .accessibilityIdentifier("tv.purr.group")
                }
            } else if view.phase == .reveal, let last = view.last, let drawer = view.drawer {
                // Both score: the drawer and whoever got it.
                Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: drawer]), last.points > 0 ? .celebrate : .awake))
                    .resizable().scaledToFit().frame(width: 190, height: 190)
                if last.points > 0 {
                    OutlinedText("+\(last.points)", size: 72, fill: .white, width: 5)
                        .padding(.horizontal, 40).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.teal).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 6)))
                }
            }
        }
    }
}

/// The word, big across the easel, and the cat who got it, jumping.
private struct PurrTVReveal: View {
    let room: RoomView
    let last: PurrLast
    @State private var jump = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Palette.ink.opacity(0.6))
            VStack(spacing: 28) {
                if let guesser = last.guesser {
                    Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: guesser]), .celebrate))
                        .resizable().scaledToFit().frame(width: 260, height: 260)
                        .offset(y: jump ? -40 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.35).repeatCount(3, autoreverses: true), value: jump)
                }
                OutlinedText(last.word.uppercased(), size: 96, fill: Palette.yellow, width: 8, lines: 2)
                    .padding(.horizontal, 30)
                    .accessibilityIdentifier("tv.purr.word")
                OutlinedText(last.guesser.map { PurrWords.gotItBy(SeatInfo.name(room, $0)) } ?? PurrWords.nobody,
                             size: 48, width: 4, lines: 2)
            }
        }
        .onAppear { jump = true }
    }
}
