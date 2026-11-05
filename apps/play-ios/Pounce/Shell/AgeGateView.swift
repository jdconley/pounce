import PounceKit
import SwiftUI

/// The age check before anything goes to the server (spec §14.1). First Apple's Declared Age
/// Range; if the person doesn't share, a neutral birth-year keypad: four empty tiles, digits, no
/// default and no hint about which years are "allowed". The year becomes a band on the device and
/// is dropped; the band goes to the Keychain, so there is no going back to try again.
struct AgeGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var entry = BirthYearEntry()
    @State private var keypad = false
    @State private var shake = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                if keypad {
                    layout(geo.size)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    VStack(spacing: 18) {
                        hero(side: min(geo.size.width * 0.5, 240))
                        YarnIndicator()
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 12)
            }
        }
        .background { background }
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: keypad)
        .task {
            guard !keypad else { return }
            if await model.askDeclaredAge() == false { keypad = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-age")
    }

    @ViewBuilder private func layout(_ size: CGSize) -> some View {
        let roomy = sizeClass == .regular
        if roomy && Roomy.sideBySide(size) {
            HStack(spacing: 56) {
                VStack(spacing: 22) {
                    hero(side: min(size.height * 0.36, 260))
                    tiles
                }
                .frame(width: min(size.width * 0.38, 460))
                keys(height: 72, size: 38)
                    .frame(width: min(size.width * 0.38, 440))
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: roomy ? 30 : 20) {
                hero(side: roomy ? 220 : min(size.height * 0.2, 170))
                tiles
                keys(height: roomy ? 72 : 60, size: roomy ? 38 : 32)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: roomy ? 520 : 440)
            .frame(maxWidth: .infinity)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Palette.violet, Palette.night], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Palette.orange.opacity(0.45), .clear], center: .init(x: 0.5, y: 0.18),
                startRadius: 10, endRadius: 340)
        }
        .ignoresSafeArea()
    }

    /// A birthday cake on a sunny disc: "when were you born", with no words and no hint.
    private func hero(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Palette.orange.mix(with: .white, by: 0.35), Palette.magenta],
                    center: .center, startRadius: 4, endRadius: side * 0.6))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 6))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 7)
            Image(systemName: "birthday.cake.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Palette.lime)
                .padding(side * 0.24)
                .shadow(color: Palette.ink.opacity(0.45), radius: 0, x: 0, y: 4)
        }
        .frame(width: side, height: side)
        .shake(trigger: shake)
        .accessibilityHidden(true)
    }

    private var tiles: some View {
        let chars = Array(entry.digits)
        return HStack(spacing: 10) {
            ForEach(0..<BirthYearEntry.length, id: \.self) { i in
                CodeTile(char: i < chars.count ? chars[i] : nil, active: i == min(chars.count, BirthYearEntry.length - 1))
                    .frame(maxWidth: 76)
                    .accessibilityValue(i < chars.count ? String(chars[i]) : "")
                    .accessibilityIdentifier("age.tile.\(i)")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.ink.opacity(0.35))
        )
        .shake(trigger: shake)
    }

    private func keys(height: CGFloat, size: CGFloat) -> some View {
        let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        return VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit($0, height: height, size: size) }
                }
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    entry.delete()
                } label: {
                    Image(ArtName.iconDelete).resizable().scaledToFit().frame(height: size)
                }
                .buttonStyle(KeyStyle(color: Palette.teal, height: height))
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("age.key.delete")
                digit(0, height: height, size: size)
                Button(action: confirm) {
                    Image(ArtName.iconCheck).resizable().scaledToFit().frame(height: size)
                }
                .buttonStyle(KeyStyle(color: Palette.lime, height: height))
                .accessibilityLabel("Done")
                .accessibilityIdentifier("age.confirm")
            }
        }
    }

    private func digit(_ d: Int, height: CGFloat, size: CGFloat) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            entry.type(d)
        } label: {
            OutlinedText(String(d), size: size, width: 2.5)
        }
        .buttonStyle(KeyStyle(color: Palette.magenta, height: height))
        .accessibilityLabel(Text(verbatim: String(d)))
        .accessibilityIdentifier("age.key.\(d)")
    }

    private func confirm() {
        guard let year = entry.year() else {
            shake += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
            return
        }
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop)
        // Only the band is kept; the year goes out of scope here.
        model.finishAge(AgeBand.from(birthYear: year), source: .keypad)
    }
}
