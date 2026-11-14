import PounceKit
import SwiftUI
import UIKit

/// Join by code (spec §5.4): the gray cat peeking over five chunky tiles and the room-code
/// keypad. The fifth character submits. A code that doesn't exist shakes the tiles clear while
/// the cat shakes its head, and one line under the tiles says so until the next key. While a
/// code is being checked delete stays live (it cancels the check), and a check whose socket
/// can't connect shows the offline card. With a link copied (an invite page copies one), the
/// top bar offers the system paste control, which opens the invite as a tapped link would.
struct JoinView: View {
    @Environment(AppModel.self) private var model

    @State private var typed = ""
    @State private var tilesShake = 0
    @State private var headShake = 0
    @State private var sad = false
    /// The last code was wrong: the line under the tiles says so until the next key.
    @State private var wrong = false

    private static let length = 5

    private var checking: Bool { model.probing != nil && model.probing == typed }
    /// The check's socket failed to connect several times: the server can't be reached.
    private var offline: Bool { checking && model.room?.offline == true }
    /// The server refused the check: too many wrong codes from this phone or its network.
    private var locked: Bool { checking && model.room?.store.phase == .locked }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            if sizeClass == .regular {
                roomy(geo.size)
            } else {
                VStack(spacing: 0) {
                    topBar
                    cat(height: max(120, geo.size.height * 0.22))
                    tiles
                        .padding(.horizontal, 16)
                        .zIndex(1)
                    message(height: 40)
                    CodeKeypad(enabled: !checking, deleteEnabled: true, onKey: type, onDelete: delete)
                        .padding(.horizontal, 14)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background { background }
        .overlay {
            if locked {
                StateCard(kind: .locked) { model.goHome() }
                    .transition(.opacity)
            } else if offline {
                StateCard(kind: .offline, onRetry: { model.room?.retry() }) { model.goHome() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: offline)
        .animation(.easeOut(duration: 0.25).paced, value: locked)
        .onChange(of: model.joinNope) { nope() }
        // The table is there, but this version can't join it: the table's own screen says why.
        .onChange(of: model.room?.store.phase) { _, phase in
            if checking, phase == .needsUpdate, let code = model.probing { model.open(code: code, intent: .join) }
        }
        .onAppear {
            if let bounced = model.takeBouncedCode() {
                typed = bounced
                nope()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-join")
    }

    // MARK: roomy (iPad)

    /// A regular-width window. Wide: the cat peeking over the code tiles on the left, the
    /// keypad on the right with bigger keys, both centered. Tall: one column like the phone's,
    /// with a bigger cat and keys, capped to a comfortable width.
    @ViewBuilder private func roomy(_ size: CGSize) -> some View {
        let keypad = CodeKeypad(
            enabled: !checking, deleteEnabled: true, keyHeight: 68, keySize: 36, spacing: 14,
            onKey: type, onDelete: delete)
        if Roomy.sideBySide(size) {
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .center, spacing: 56) {
                    VStack(spacing: 0) {
                        cat(height: min(size.height * 0.36, 300))
                        tiles
                            .zIndex(1)
                        message(height: 48)
                    }
                    .frame(width: min(size.width * 0.4, 500))
                    keypad
                        .frame(width: min(size.width * 0.42, 540))
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                cat(height: min(max(160, size.height * 0.24), 300))
                tiles
                    .zIndex(1)
                message(height: 56)
                keypad
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: pieces

    private var background: some View {
        ZStack {
            Palette.night
            Image(ArtName.homeBg)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, Palette.night.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("join.back")
            Spacer()
            if checking {
                YarnIndicator()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // A copied link: paste it instead of typing (the invite page's "tap Paste").
        .overlay {
            if model.pasteboard.hasLink && !checking {
                InvitePasteButton(size: .large, textSizes: sizeClass == .regular ? .xxLarge ... .xxxLarge : .large ... .xLarge)
                    .accessibilityIdentifier("join.paste")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .frame(height: 64)
        .animation(.spring(duration: 0.3).paced, value: checking)
        .animation(.spring(duration: 0.3).paced, value: model.pasteboard.hasLink)
    }

    /// Under the tiles: why they shook, in a few words; empty space otherwise, so nothing moves.
    private func message(height: CGFloat) -> some View {
        ZStack {
            if wrong {
                Text("No table with that code.", comment: "Join: a code with no table behind it")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.yellow)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .transition(.opacity)
                    .accessibilityIdentifier("join.wrong")
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.2).paced, value: wrong)
    }

    private func cat(height: CGFloat) -> some View {
        Image(ArtName.cat(3, sad ? .away : (typed.count == Self.length ? .awake : .idle)))
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 5)
            .wiggle(trigger: headShake)
            .shake(trigger: headShake)
            // Paws over the panel's top edge, like the mock.
            .padding(.bottom, -18)
            .accessibilityHidden(true)
    }

    private var tiles: some View {
        let chars = Array(typed)
        return HStack(spacing: 8) {
            ForEach(0..<Self.length, id: \.self) { i in
                CodeTile(
                    char: i < chars.count ? chars[i] : nil,
                    active: i == min(chars.count, Self.length - 1) && !checking)
                    .accessibilityIdentifier("join.tile.\(i)")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Palette.violet.mix(with: Palette.ink, by: 0.25), Palette.night],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
        )
        .shake(trigger: tilesShake)
    }

    // MARK: input

    private func type(_ c: Character) {
        guard typed.count < Self.length else { return }
        wrong = false
        typed.append(c)
        if typed.count == Self.length {
            model.joinTyped(typed)
        }
    }

    private func delete() {
        guard !typed.isEmpty else { return }
        model.cancelProbe()
        typed.removeLast()
    }

    /// Bad code: shake the tiles, the cat shakes its head, then the tiles clear.
    private func nope() {
        tilesShake += 1
        headShake += 1
        sad = true
        wrong = true
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "No table with that code.", comment: "Join: a code with no table behind it"))
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
        Task {
            try? await Task.sleep(for: Pace.duration(.milliseconds(380)))
            withAnimation(.spring(duration: 0.3).paced) { typed = "" }
            try? await Task.sleep(for: Pace.duration(.milliseconds(600)))
            sad = false
        }
    }
}

/// One letter tile: violet block with a thick outline; the next slot to fill glows teal.
/// Also shows a move code's six letters (`MoveSeatSheet`).
struct CodeTile: View {
    let char: Character?
    let active: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let color = active ? Palette.teal : Palette.violet
        shape
            .fill(LinearGradient(
                colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: Palette.ink, by: 0.25)],
                startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 4))
            .overlay {
                if let char {
                    OutlinedText(String(char), size: 40, width: 3)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .aspectRatio(0.86, contentMode: .fit)
            .shadow(color: active ? Palette.teal.opacity(0.9) : Palette.ink.opacity(0.4), radius: active ? 10 : 0, x: 0, y: active ? 0 : 4)
            .pop(trigger: char.map(String.init) ?? "")
            .animation(.spring(duration: 0.25, bounce: 0.5).paced, value: char)
            .accessibilityElement()
            .accessibilityLabel(char.map { Text(verbatim: String($0)) } ?? Text("Empty"))
    }
}
