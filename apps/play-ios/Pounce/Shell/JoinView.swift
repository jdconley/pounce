import PounceKit
import SwiftUI

/// Join by code (spec §5.4): the gray cat peeking over five chunky tiles and the room-code
/// keypad. The fifth character submits. A code that doesn't exist shakes the tiles clear while
/// the cat shakes its head; no text.
struct JoinView: View {
    @Environment(AppModel.self) private var model

    @State private var typed = ""
    @State private var tilesShake = 0
    @State private var headShake = 0
    @State private var sad = false

    private static let length = 5

    private var checking: Bool { model.probing != nil && model.probing == typed }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                cat(height: max(120, geo.size.height * 0.22))
                tiles
                    .padding(.horizontal, 16)
                    .zIndex(1)
                CodeKeypad(enabled: !checking, onKey: type, onDelete: delete)
                    .padding(.horizontal, 14)
                    .padding(.top, 22)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { background }
        .onChange(of: model.joinNope) { nope() }
        .onAppear {
            if let bounced = model.takeBouncedCode() {
                typed = bounced
                nope()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-join")
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
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .frame(height: 64)
        .animation(.spring(duration: 0.3), value: checking)
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
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(duration: 0.3)) { typed = "" }
            try? await Task.sleep(for: .milliseconds(600))
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
            .animation(.spring(duration: 0.25, bounce: 0.5), value: char)
            .accessibilityElement()
            .accessibilityLabel(char.map { Text(verbatim: String($0)) } ?? Text("Empty"))
    }
}
