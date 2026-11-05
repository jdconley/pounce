import ActivityKit
import PounceKit
import SwiftUI
import WidgetKit

/// The live table (spec §11.3): a Live Activity for a live stretch of play, started by the server
/// with push-to-start when you leave a table someone else is at. The Lock Screen shows the rug strip
/// with every seat's cat, a glowing ring on whoever's move it is and a bell when it's yours, each
/// phase numeral, the table name and the pair's paws; the Dynamic Island shows your cat and the
/// bell (or the current player's cat). No buttons: a tap opens the table. A missed push greys it
/// out at its stale date.
struct LiveTableWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveTableAttributes.self) { context in
            LiveTableLockView(look: LiveTableLook(context.state), stale: context.isStale)
                .activityBackgroundTint(Palette.night)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WidgetLink.table(context.attributes.code).url)
        } dynamicIsland: { context in
            let look = LiveTableLook(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveCat(cat: look.leadingCat, pose: .idle, size: 46)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let paws = look.paws {
                        LivePaws(paws: paws, paw: 20, numeral: 24)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    OutlinedText(look.table, size: 18, fill: .white, width: 2.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RugStrip(look: look, cat: 38)
                        .opacity(context.isStale ? 0.55 : 1)
                        .saturation(context.isStale ? 0 : 1)
                }
            } compactLeading: {
                LiveCat(cat: look.leadingCat, pose: .idle, size: 24)
            } compactTrailing: {
                LiveTrailing(trailing: look.trailing, size: 24)
            } minimal: {
                if look.trailing == .none {
                    LiveCat(cat: look.leadingCat, pose: .idle, size: 22)
                } else {
                    LiveTrailing(trailing: look.trailing, size: 22)
                }
            }
            .widgetURL(WidgetLink.table(context.attributes.code).url)
            .keylineTint(Palette.magenta)
        }
    }
}

/// The Lock Screen banner: the table name and the pair's paws over the rug strip.
struct LiveTableLockView: View {
    let look: LiveTableLook
    let stale: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                OutlinedText(look.table, size: 22, fill: .white, width: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                if let paws = look.paws { LivePaws(paws: paws, paw: 24, numeral: 28) }
            }
            RugStrip(look: look, cat: 46)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Shapes, not the big backdrop art: a Live Activity draws an oversized image as a grey box.
        .background(LinearGradient(colors: [Palette.violet, Palette.magenta], startPoint: .topLeading, endPoint: .bottomTrailing))
        .opacity(stale ? 0.6 : 1)
        .saturation(stale ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: look.spoken))
    }
}

/// Every seat's cat on the rug: a glowing ring on whoever's move it is, each phase numeral, and
/// the bell at the end when the move is yours.
struct RugStrip: View {
    let look: LiveTableLook
    let cat: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(look.seats.enumerated()), id: \.offset) { i, seat in
                LiveSeatView(seat: seat, color: Palette.playerRings[i % Palette.playerRings.count], cat: cat)
                    .frame(maxWidth: .infinity)
            }
            if look.bell {
                ArtImage(ArtName.iconBell, points: cat * 0.9)
                    .frame(width: cat * 0.9, height: cat * 0.9)
                    .rotationEffect(.degrees(-14))
                    .shadow(color: Palette.orange, radius: 6)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background { RugShape(corner: cat * 0.42) }
    }
}

/// The rug, drawn: a teal shag with the classic rug's magenta and violet rings and an ink edge.
struct RugShape: View {
    let corner: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(RadialGradient(colors: [Palette.teal.mix(with: .white, by: 0.25), Palette.teal, Palette.sky],
                                 center: .center, startRadius: 4, endRadius: 220))
            .overlay(shape.inset(by: 5).strokeBorder(Palette.magenta, lineWidth: 4))
            .overlay(shape.inset(by: 9).strokeBorder(Palette.violet, lineWidth: 3))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 3))
    }
}

/// One seat: its cat (awake on its move, inside the glowing ring), the bot badge, and the phase
/// numeral on a chip in the seat's ring color.
struct LiveSeatView: View {
    let seat: LiveTableLook.Seat
    let color: Color
    let cat: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if seat.glowing {
                    ArtImage(ArtName.ringGlow, points: cat * 1.35)
                        .frame(width: cat * 1.35, height: cat * 1.35)
                    Circle().strokeBorder(Palette.lime, lineWidth: 3).frame(width: cat * 1.08, height: cat * 1.08)
                }
                LiveCat(cat: seat.cat, pose: seat.glowing ? .awake : .idle, size: cat)
            }
            .frame(width: cat * 1.1, height: cat * 1.1)
            if seat.bot {
                ArtImage(ArtName.badgeBot, points: cat * 0.36)
                    .frame(width: cat * 0.36, height: cat * 0.36)
                    .offset(x: -cat * 0.62, y: 0)
            }
            OutlinedText(String(seat.phase), size: cat * 0.3, fill: .white, width: 2)
                .fixedSize()
                .frame(minWidth: cat * 0.38, minHeight: cat * 0.38)
                .background(Circle().fill(color).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2)))
        }
    }
}

/// A cat from the app's sprites.
struct LiveCat: View {
    let cat: Int
    let pose: WidgetPose
    let size: CGFloat

    var body: some View {
        ArtImage(WidgetArt.cat(cat, pose), points: size)
            .frame(width: size, height: size)
    }
}

/// The Island's trailing side: the bell when it's your move, else the mover's cat.
struct LiveTrailing: View {
    let trailing: LiveTableLook.Trailing
    let size: CGFloat

    var body: some View {
        switch trailing {
        case .bell:
            ArtImage(ArtName.iconBell, points: size).frame(width: size, height: size)
        case .cat(let cat, _):
            LiveCat(cat: cat, pose: .awake, size: size)
        case .none:
            EmptyView()
        }
    }
}

/// The pair's two paws around the streak numeral: yours on the left, theirs on the right.
struct LivePaws: View {
    let paws: LiveTableLook.Paws
    let paw: CGFloat
    let numeral: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            pawImage(lit: paws.me)
            OutlinedText(String(paws.count), size: numeral, fill: .white, width: 3).fixedSize()
            pawImage(lit: paws.them)
        }
    }

    private func pawImage(lit: Bool) -> some View {
        ArtImage(lit ? ArtName.Habit.pawOne : ArtName.Habit.pawGrey, points: paw)
            .frame(width: paw, height: paw)
            .opacity(lit ? 1 : 0.7)
    }
}
