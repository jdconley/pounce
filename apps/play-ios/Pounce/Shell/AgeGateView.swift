import PounceKit
import SwiftUI

/// The age check before anything goes to the server (spec §14.1). First Apple's Declared Age
/// Range; if the person doesn't share, a neutral birth-year keypad: the question in words, four
/// empty tiles, no default and no hint about which years are "allowed", then the year said back
/// for a yes. The year becomes a band on the device and is dropped; the band goes to the
/// Keychain, so the keypad never comes back. A wrong band is put right only by Apple's answer
/// (`AgeCorrection`, the gear's "Check with Apple").
struct AgeGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var entry = BirthYearEntry()
    @State private var keypad = false
    /// The year waiting for its yes.
    @State private var confirming: Int?
    @State private var shake = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                if let year = confirming {
                    confirmStep(year, size: geo.size)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else if keypad {
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
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: confirming)
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
                    hero(side: min(size.height * 0.3, 220))
                    question(size: 34)
                    tiles
                }
                .frame(width: min(size.width * 0.38, 460))
                keys(height: 72, size: 38)
                    .frame(width: min(size.width * 0.38, 440))
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: roomy ? 26 : 16) {
                hero(side: roomy ? 200 : min(size.height * 0.15, 130))
                question(size: roomy ? 36 : 28)
                tiles
                keys(height: roomy ? 72 : 60, size: roomy ? 38 : 32)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: roomy ? 520 : 440)
            .frame(maxWidth: .infinity)
        }
    }

    private func question(size: CGFloat) -> some View {
        OutlinedText(
            String(localized: "What year were you born?", comment: "Age screen: the birth-year question above the keypad"),
            size: size, lines: 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("age.question")
    }

    /// The year said back, for a yes or a change.
    private func confirmStep(_ year: Int, size: CGSize) -> some View {
        let roomy = sizeClass == .regular
        return VStack(spacing: roomy ? 30 : 22) {
            hero(side: roomy ? 200 : min(size.height * 0.2, 160))
            OutlinedText(
                String(localized: "Born in \(String(year))?", comment: "Age screen: the typed birth year said back for a yes"),
                size: roomy ? 44 : 36, lines: 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("age.confirmYear")
            HStack(spacing: 14) {
                PillButton(
                    icon: nil, color: Palette.sky, size: .small, width: roomy ? 180 : 140,
                    title: String(localized: "Change", comment: "Age screen: go back and retype the birth year"),
                    accessibilityLabel: "Change"
                ) {
                    entry = BirthYearEntry()
                    confirming = nil
                }
                .accessibilityIdentifier("age.change")
                PillButton(
                    icon: nil, color: Palette.lime, size: .small, width: roomy ? 220 : 170,
                    title: String(localized: "Yes, that's right", comment: "Age screen: confirm the birth year said back"),
                    accessibilityLabel: "Yes, that's right"
                ) {
                    finish(year)
                }
                .accessibilityIdentifier("age.yes")
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: roomy ? 560 : 440)
        .frame(maxWidth: .infinity)
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

    /// A birthday cake on a sunny disc, above the question in words.
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
                    .accessibilityLabel(Text("Birth year, digit \(i + 1) of \(BirthYearEntry.length)",
                                             comment: "VoiceOver: one tile of the birth-year keypad"))
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
        DigitKeys(height: height, size: size, idPrefix: "age", onDigit: { entry.type($0) }, onDelete: { entry.delete() },
                  onDone: confirm)
    }

    private func confirm() {
        guard let year = entry.year() else {
            shake += 1
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxNope)
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "Check the year and try again", comment: "VoiceOver: the birth year wasn't taken"))
            return
        }
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop)
        confirming = year
    }

    private func finish(_ year: Int) {
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop)
        // Only the band is kept; the year goes out of scope here.
        confirming = nil
        entry = BirthYearEntry()
        model.finishAge(AgeBand.from(birthYear: year), source: .keypad)
    }
}

/// The gear's way to put a wrong age right (launch review): offered while the band limits the
/// person. Only Apple's Declared Age Range answer can change it; the keypad never comes back, so a
/// child can't retype their way out. A decline changes nothing and says where to allow sharing.
struct AgeCorrectionRow: View {
    @Environment(AppModel.self) private var model

    @State private var busy = false
    @State private var noAnswer = false

    var body: some View {
        VStack(spacing: 10) {
            WordLine(String(localized: "Age not right?", comment: "Gear sheet: the age-correction row's question"), size: 17)
            PillButton(
                icon: nil, color: Palette.sky, size: .small, width: 220,
                title: String(localized: "Check with Apple", comment: "Gear sheet: ask Apple's Declared Age Range again"),
                accessibilityLabel: "Check with Apple"
            ) {
                guard !busy else { return }
                busy = true
                Task {
                    defer { busy = false }
                    let changed = await model.correctAge()
                    noAnswer = !changed
                    if changed { Haptics.shared.success() } else { Haptics.shared.thump() }
                }
            }
            .opacity(busy ? 0.5 : 1)
            .accessibilityIdentifier("gear.ageCheck")
            if noAnswer {
                WordLine(
                    String(localized: "Apple didn't share a different age. You can allow age sharing for Pounce in the Settings app, then try again.",
                           comment: "Gear sheet: Declared Age Range gave no new band"),
                    size: 14)
                    .accessibilityIdentifier("gear.ageCheck.none")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.ink.opacity(0.35)))
        .accessibilityElement(children: .contain)
    }
}

/// A short line of plain words on the dark screens: bold, rounded, white, centred, wrapping.
struct WordLine: View {
    let text: String
    var size: CGFloat = 16
    var color: Color = .white

    init(_ text: String, size: CGFloat = 16, color: Color = .white) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 1.5)
    }
}

/// The numeral keypad in the room-code keypad's style (the age screen, the parent's link code):
/// 1 to 9, then delete, 0 and the check. Ids: `<prefix>.key.<n>`, `<prefix>.key.delete`,
/// `<prefix>.confirm`.
struct DigitKeys: View {
    let height: CGFloat
    let size: CGFloat
    let idPrefix: String
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit($0) }
                }
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    onDelete()
                } label: {
                    Image(ArtName.iconDelete).resizable().scaledToFit().frame(height: size)
                }
                .buttonStyle(KeyStyle(color: Palette.teal, height: height))
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("\(idPrefix).key.delete")
                digit(0)
                Button(action: onDone) {
                    Image(ArtName.iconCheck).resizable().scaledToFit().frame(height: size)
                }
                .buttonStyle(KeyStyle(color: Palette.lime, height: height))
                .accessibilityLabel("Done")
                .accessibilityIdentifier("\(idPrefix).confirm")
            }
        }
    }

    private func digit(_ d: Int) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            onDigit(d)
        } label: {
            OutlinedText(String(d), size: size, width: 2.5)
        }
        .buttonStyle(KeyStyle(color: Palette.magenta, height: height))
        .accessibilityLabel(Text(verbatim: String(d)))
        .accessibilityIdentifier("\(idPrefix).key.\(d)")
    }
}
