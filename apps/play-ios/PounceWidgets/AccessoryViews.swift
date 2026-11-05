import PounceKit
import SwiftUI
import WidgetKit

/// The Streak widget on the lock screen (spec §11.1).
struct AccessoryWidgetView: View {
    let entry: UsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularStreakView(state: entry.state)
                .widgetURL(WidgetLink.us(pair: entry.state.pair).url)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            RectangularStreakView(state: entry.state)
                .widgetURL(entry.state.url)
                .containerBackground(for: .widget) { Color.clear }
        default:
            InlineStreakView(state: entry.state)
                .widgetURL(WidgetLink.app.url)
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

/// The paw ring around the numeral: half full when one of you is in today, full when kept.
struct CircularStreakView: View {
    let state: UsWidgetState

    var body: some View {
        Gauge(value: state.ring, in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: -1) {
                Image(systemName: modeSymbol)
                    .font(.system(size: 11, weight: .bold))
                if state.kind == .pair {
                    Text(verbatim: String(state.count))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                }
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(Text(verbatim: SmallUsView.label(state)))
    }

    private var modeSymbol: String {
        switch state.mode {
        case .paused: "suitcase.fill"
        case .winback: "bandage.fill"
        case .napped: "moon.zzz.fill"
        default: "pawprint.fill"
        }
    }
}

/// The partner's cat as a template, the numeral, and a bell when it's your move.
struct RectangularStreakView: View {
    let state: UsWidgetState

    var body: some View {
        HStack(spacing: 6) {
            if let partner = state.partner {
                ArtImage(WidgetArt.cat(partner.cat, state.theirPose), points: 56)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: -2) {
                    Text(verbatim: String(state.count))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .widgetAccentable()
                    Text(verbatim: partner.name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.myMove != nil {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20, weight: .bold))
                        .widgetAccentable()
                }
            } else {
                ArtImage(WidgetArt.cat(state.me?.cat ?? 3, .idle), points: 56)
                    .frame(width: 52, height: 52)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SmallUsView.label(state)))
    }
}

/// The paw plus "12 · Mia".
struct InlineStreakView: View {
    let state: UsWidgetState

    var body: some View {
        if let partner = state.partner {
            Label {
                Text(verbatim: "\(state.count) · \(partner.name)")
            } icon: {
                Image(systemName: "pawprint.fill")
            }
        } else {
            Image(systemName: "pawprint.fill")
        }
    }
}
