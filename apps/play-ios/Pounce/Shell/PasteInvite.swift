import PounceKit
import SwiftUI
import UIKit

/// Whether the pasteboard holds something that looks like a link (first-run funnel, part 2): the
/// invite pages copy the invite before sending someone to install Pounce, so it's waiting on the
/// first launch. `detectPatterns` only says what kind of thing is there: no "Allow paste?" alert and
/// no paste banner. Reading it is the system paste control's job (`PasteButton`), which needs no
/// permission because the person tapped it. A pasteboard already pasted, or turned down with
/// "Not now", isn't offered again (`changeCount`, kept across launches).
@MainActor @Observable final class PasteboardWatch {
    private(set) var hasLink = false
    /// Off in staged runs (`AppModel.startPasteboard`): nothing is offered.
    @ObservationIgnored var enabled = true

    @ObservationIgnored private let defaults: UserDefaults
    /// Each look at the pasteboard, counted: an older answer arriving late is dropped.
    @ObservationIgnored private var looks = 0
    private static let handledKey = "pasteInvite.handled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Each time the app is in front: at launch the first look can come before the app is
        // active, when the pasteboard answers nothing.
        // The pasteboard can also answer late right after the app comes to the front (back from the
        // App Store, say), so a look that finds nothing is taken once more a second later.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    if let self, !self.hasLink { self.refresh() }
                }
            }
        }
    }

    /// Looks again (at launch, and each time the app comes to the front).
    func refresh() {
        let board = UIPasteboard.general
        let count = board.changeCount
        looks += 1
        let look = looks
        guard enabled, defaults.object(forKey: Self.handledKey) as? Int != count, board.hasStrings || board.hasURLs else {
            hasLink = false
            return
        }
        // UIKit answers on a background queue: this closure must not inherit the main actor.
        board.detectPatterns(for: [.probableWebURL]) { @Sendable result in
            // A look that failed (the app wasn't in front yet) changes nothing.
            guard let patterns = try? result.get() else { return }
            let found = patterns.contains(.probableWebURL)
            Task { @MainActor in
                // Only the latest look counts, and only for the pasteboard it looked at.
                guard look == self.looks, UIPasteboard.general.changeCount == count else { return }
                self.hasLink = found
            }
        }
    }

    /// This pasteboard was pasted, or turned down: don't offer it again.
    func settle() {
        defaults.set(UIPasteboard.general.changeCount, forKey: Self.handledKey)
        hasLink = false
    }
}

/// The system paste control in Pounce's colours. Its label is the system's ("Paste"), which is
/// what the invite page says to tap.
struct InvitePasteButton: View {
    @Environment(AppModel.self) private var model
    var size: ControlSize = .extraLarge
    /// The label's size in points at the default text size; it grows with Dynamic Type, to a cap.
    var points: CGFloat = 24

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            let text = strings.first ?? ""
            Task { @MainActor in model.pasteInvite(text) }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
        .controlSize(size)
        .font(.system(size: points, weight: .heavy, design: .rounded))
        .tint(Palette.magenta)
        // Big text grows it a little, never past the screen's other controls.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// First launch after an invite page (first-run funnel, part 2): the person copied the invite
/// before installing, so the first thing Home offers is to paste it. Only while this phone has
/// no table yet and the pasteboard looks like it holds a link (`AppModel.offersPasteInvite`).
struct PasteInviteCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var shake = 0
    @State private var wrong = false

    private var scale: CGFloat { sizeClass == .regular ? 1.3 : 1 }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea().onTapGesture(perform: notNow)
            VStack(spacing: 16 * scale) {
                Image(ArtName.iconInvite).resizable().scaledToFit()
                    .frame(width: 96 * scale, height: 96 * scale)
                    .accessibilityHidden(true)
                OutlinedText(
                    String(localized: "Got an invite?", comment: "Paste invite card: the title, on first launch with a link copied"),
                    size: 30 * scale, fill: .white, width: 3, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                Text(wrong
                     ? LocalizedStringResource("That's not an invite.", comment: "Paste invite card: what was pasted isn't a Pounce link")
                     : LocalizedStringResource("Paste it to play.", comment: "Paste invite card: the line under the title"))
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(wrong ? Palette.yellow : .white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pasteInvite.line")
                InvitePasteButton(points: 24 * scale)
                    .accessibilityIdentifier("pasteInvite.paste")
                Button(action: notNow) {
                    Text("Not now", comment: "Paste invite card: closes it")
                        .font(.system(size: 18 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pasteInvite.notNow")
            }
            .padding(.top, 28)
            .padding(.bottom, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440 * scale)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .wiggle(trigger: shake)
            .padding(20)
        }
        .onChange(of: model.pasteNope) {
            wrong = true
            shake += 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-pasteInvite")
    }

    private func notNow() {
        model.pasteboard.settle()
    }
}
