import PounceKit
import SwiftUI

/// Short visible words for a control or a screen part: a bold title and an optional plain line
/// under it. Text styles, so it follows Dynamic Type. VoiceOver skips it by default because the
/// control it sits beside already speaks (pass `speaks: true` when it stands alone).
struct WordLabel: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    var alignment: HorizontalAlignment = .leading
    var speaks = false

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .black))
            if let detail {
                Text(detail)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(!speaks)
    }
}

/// A control with its words beside it, for settings lists. At the accessibility text sizes the
/// words go under the control, so they get the row's whole width and never break mid-word.
struct WordRow<Control: View>: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @ViewBuilder let control: Control

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                control
                WordLabel(title: title, detail: detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                control
                WordLabel(title: title, detail: detail)
                Spacer(minLength: 0)
            }
        }
    }
}

extension View {
    /// A short word under a control. Hidden from VoiceOver (the control's own label speaks).
    func captioned(_ title: LocalizedStringResource) -> some View {
        VStack(spacing: 3) {
            self
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Under a fixed-size button, so it grows with Dynamic Type but not past the button's row.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
        }
    }
}

/// One plain line about what the streak's little picture (bandage, suitcase, nap) means.
struct StreakModeLine: View {
    let mode: StreakBadge.Mode

    var body: some View {
        switch mode {
        case .normal: EmptyView()
        case .winback: line(LocalizedStringResource("Play two days in a row to win it back.", comment: "Streak line: the bandaged paw, a streak that can still be won back"))
        case .paused: line(LocalizedStringResource("Paused for a trip.", comment: "Streak line: the suitcase, a paused streak"))
        case .napped: line(LocalizedStringResource("A cat nap saved yesterday.", comment: "Streak line: a missed day the nap covered"))
        case .fresh: line(LocalizedStringResource("A fresh start.", comment: "Streak line: a new streak"))
        }
    }

    private func line(_ text: LocalizedStringResource) -> some View {
        WordLabel(title: text, alignment: .center)
            .font(.callout)
            .padding(.horizontal, 24)
    }
}
