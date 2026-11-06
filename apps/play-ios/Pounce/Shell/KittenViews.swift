import PounceKit
import SwiftUI
import WebKit

// Parent consent (consent design §2 "What the kitten sees" and "What the parent sees", D6; plan
// decisions 33–39, 50–55). Pictures, names and numerals only. The notice page and the phone field
// are legal text, like the privacy page; the code from Twilio Verify is numerals and a keypad.

/// The kitten's bell in the gear sheet: padlocked with six numerals for a grown-up, padlocked
/// with no code while the significant change is owed, asleep while the parent is still to
/// consent, or the normal bell once they have. While the sheet is open it checks every 15 s, so
/// the bell changes as the parent links and confirms.
struct KittenBellView: View {
    @Environment(AppModel.self) private var model
    var scale: CGFloat = 1

    /// A code asked for from the asleep or on bell, for one more parent.
    @State private var showCode = false
    @State private var now = Date.now

    private static let poll: Duration = .seconds(15)

    private var bell: KittenBell {
        KittenBell.of(status: model.kittens.status, held: model.kittenPushHeld, code: model.kittens.code, now: now)
    }

    private var shownCode: String? {
        if case .locked(let code) = bell { return code }
        guard showCode, let code = model.kittens.code, code.fresh(at: now) else { return nil }
        return code.code
    }

    var body: some View {
        VStack(spacing: 14 * scale) {
            Button(action: tap) {
                art
                    .frame(width: 150 * scale, height: 150 * scale)
                    .background(Circle().fill(RadialGradient(
                        colors: [Palette.orange.mix(with: .white, by: 0.3), Palette.magenta], center: .center,
                        startRadius: 6, endRadius: 100 * scale)))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 5))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Notifications", comment: "VoiceOver: a kitten's notification bell"))
            .accessibilityValue(Self.value(bell))
            .accessibilityIdentifier("kitten.bell")
            if let code = shownCode {
                HStack(spacing: 8 * scale) {
                    ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                        CodeTile(char: ch, active: false)
                            .frame(maxWidth: 52 * scale)
                            .accessibilityIdentifier("kitten.code.\(i)")
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.ink.opacity(0.35)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("kitten.code")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: shownCode)
        .task { await loop() }
    }

    @ViewBuilder private var art: some View {
        switch bell {
        case .locked, .held:
            Image(ArtName.Habit.kittenBellLocked).resizable().scaledToFit().padding(6 * scale)
        case .asleep:
            Image(ArtName.Habit.pounceBellAsleep).resizable().scaledToFit().padding(14 * scale)
        case .on:
            Image(ArtName.Habit.pounceBell).resizable().scaledToFit().padding(6 * scale)
                .overlay(alignment: .bottomTrailing) {
                    Image(ArtName.iconCheck).resizable().scaledToFit().frame(width: 40 * scale).offset(x: 4, y: 4)
                }
        }
    }

    static func value(_ bell: KittenBell) -> String {
        switch bell {
        case .locked: "locked"
        case .held: "held"
        case .asleep: "asleep"
        case .on: "on"
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            now = .now
            await model.refreshKitten()
            if case .locked(nil) = bell { await model.requestKittenCode() }
            now = .now
            try? await Task.sleep(for: Self.poll)
        }
    }

    private func tap() {
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop)
        switch bell {
        case .held:
            Haptics.shared.thump()
        case .locked:
            Task { await model.requestKittenCode() }
        case .asleep, .on:
            // One more grown-up: a code for them too. The normal bell also asks iOS once.
            showCode.toggle()
            Task {
                await model.requestKittenCode()
                now = .now
                if bell == .on, let push = model.push, await push.authorizationStatus() == .notDetermined {
                    _ = await push.requestAuthorization()
                }
            }
        }
    }
}

/// The parent's Kittens panel (consent design §2 "What the parent sees"): each linked kitten with
/// its cat, the consent state (an hourglass, the phone, the bell, the bell with a check once the
/// confirmation push reached this parent), a toggle per person, the notice, number and code while
/// pending, the bell with a slash to revoke, and the trash can to unlink. The plus opens the
/// six-digit keypad. Opened from a consent notification, it scrolls to that kitten and rings it.
struct KittensSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The kitten a notification named (`k_…`).
    var focus: String?

    @State private var linking = false
    @State private var notice: ParentKitten?

    private var scale: CGFloat { sizeClass == .regular ? 1.2 : 1 }

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20 * scale) {
                        HStack {
                            Image(ArtName.Habit.iconKittens).resizable().scaledToFit().frame(width: 64 * scale)
                                .accessibilityHidden(true)
                            Spacer()
                            PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") {
                                dismiss()
                            }
                            .accessibilityIdentifier("kittens.close")
                        }
                        ForEach(Array(model.kittens.kittens.enumerated()), id: \.element.id) { i, kitten in
                            KittenCard(kitten: kitten, index: i, scale: scale, focused: kitten.id == focus) { notice = kitten }
                                .id(kitten.id)
                        }
                        ArtIconButton(icon: ArtName.iconPlus, color: Palette.lime, size: 76 * scale, label: "Add a kitten") {
                            linking = true
                        }
                        .bounceLoop(active: model.kittens.kittensLoaded && model.kittens.kittens.isEmpty)
                        .accessibilityIdentifier("kittens.add")
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .task {
                    await model.kittens.refreshKittens()
                    if let focus { withAnimation(.easeOut(duration: 0.3).paced) { proxy.scrollTo(focus, anchor: .center) } }
                }
            }
            if linking {
                LinkCodeOverlay { linking = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2).paced, value: linking)
        .sheet(item: $notice) { kitten in
            KittenNoticeSheet(kitten: kitten)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-kittens")
    }
}

/// One kitten on the panel.
private struct KittenCard: View {
    @Environment(AppModel.self) private var model
    let kitten: ParentKitten
    let index: Int
    let scale: CGFloat
    /// The kitten a consent notification opened the panel on.
    var focused = false
    let onPhone: () -> Void

    @State private var confirmUnlink = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        VStack(spacing: 14 * scale) {
            HStack(spacing: 14 * scale) {
                Image(ArtName.cat(kitten.cat, .idle)).resizable().scaledToFit()
                    .padding(6)
                    .frame(width: 84 * scale, height: 84 * scale)
                    .background(Circle().fill(Palette.teal))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                NameTag(kitten.name, maxWidth: 170 * scale, active: true, size: 20 * scale)
                Spacer(minLength: 4)
                stateArt
                    .frame(width: 54 * scale, height: 54 * scale)
                    .accessibilityHidden(true)
            }
            if !kitten.people.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(kitten.people.enumerated()), id: \.element.pair) { j, person in
                        PersonToggle(person: person, apple: kitten.mode == .apple, scale: scale) {
                            Task { await model.kittens.toggle(kitten: kitten.id, pair: person.pair) }
                        }
                        .accessibilityIdentifier("kittens.person.\(index).\(j)")
                    }
                }
            }
            HStack(spacing: 16 * scale) {
                if kitten.state != .on {
                    ArtIconButton(icon: ArtName.Habit.iconPhone, color: Palette.sky, size: 64 * scale, label: "Notice and phone", action: onPhone)
                        .bounceLoop(active: true)
                        .accessibilityIdentifier("kittens.phone.\(index)")
                } else {
                    ArtIconButton(icon: ArtName.Habit.iconBellOff, color: Palette.violet, size: 64 * scale, label: "Turn off notifications") {
                        Task { await model.kittens.revoke(kitten: kitten.id) }
                    }
                    .accessibilityIdentifier("kittens.revoke.\(index)")
                }
                ArtIconButton(icon: ArtName.Habit.iconTrash, color: confirmUnlink ? Palette.magenta : Palette.night,
                              size: 64 * scale, label: confirmUnlink ? "Remove, sure" : "Remove") {
                    if confirmUnlink {
                        Task { await model.kittens.unlink(kitten: kitten.id) }
                    } else {
                        confirmUnlink = true
                    }
                }
                .wiggle(trigger: confirmUnlink)
                .accessibilityIdentifier("kittens.unlink.\(index)")
            }
        }
        .padding(18 * scale)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.violet)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(focused ? Palette.lime : Palette.ink, lineWidth: focused ? 8 : 5)))
        .wiggle(trigger: focused)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Self.value(kitten))
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityIdentifier("kittens.card.\(index)")
    }

    /// `pending`, `code`, `on`, or `confirmed` once the confirmation push reached the parent.
    static func value(_ kitten: ParentKitten) -> String {
        kitten.state == .on && kitten.confirmed ? "confirmed" : kitten.state.rawValue
    }

    /// An hourglass, the phone, the bell waiting on the confirmation (a small hourglass), or the
    /// bell with a check: confirmed.
    @ViewBuilder private var stateArt: some View {
        switch kitten.state {
        case .pending:
            Image(ArtName.Habit.iconHourglass).resizable().scaledToFit()
        case .code:
            Image(ArtName.Habit.iconPhone).resizable().scaledToFit()
        case .on:
            Image(ArtName.Habit.pounceBell).resizable().scaledToFit()
                .overlay(alignment: .bottomTrailing) {
                    Image(kitten.confirmed ? ArtName.iconCheck : ArtName.Habit.iconHourglass)
                        .resizable().scaledToFit().frame(width: 26 * scale).offset(x: 6, y: 6)
                }
        }
    }
}

/// A person the kitten plays with: their cat and name, lit with a check when approved, a padlock
/// when not. A linked parent is always on; Apple's answers show but don't change here.
private struct PersonToggle: View {
    let person: KittenPerson
    let apple: Bool
    let scale: CGFloat
    let action: () -> Void

    private var fixed: Bool { person.parent || apple }

    var body: some View {
        Button {
            guard !fixed else {
                Haptics.shared.thump()
                return
            }
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            VStack(spacing: 4) {
                Image(ArtName.cat(person.cat, person.approved ? .awake : .asleep)).resizable().scaledToFit()
                    .padding(5)
                    .frame(width: 66 * scale, height: 66 * scale)
                    .background(Circle().fill(person.approved ? Palette.lime : Palette.night))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                    .saturation(person.approved ? 1 : 0.55)
                    .overlay(alignment: .bottomTrailing) {
                        Image(person.approved ? ArtName.iconCheck : ArtName.Habit.iconPadlock)
                            .resizable().scaledToFit().frame(width: 26 * scale).offset(x: 4, y: 4)
                    }
                    .overlay(alignment: .topLeading) {
                        if apple {
                            Image(ArtName.Habit.iconHourglass).resizable().scaledToFit().frame(width: 22 * scale).offset(x: -4, y: -4)
                        }
                    }
                NameTag(person.name, maxWidth: 90 * scale, active: person.approved, size: 13 * scale)
            }
        }
        .buttonStyle(.plain)
        .opacity(fixed && !person.approved ? 0.8 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: person.name))
        .accessibilityValue(person.approved ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }
}

/// The parent enters the six numerals the kitten's bell shows.
private struct LinkCodeOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onClose: () -> Void

    @State private var entry = LinkCodeEntry()
    @State private var shake = 0
    @State private var busy = false
    @State private var resting = false

    var body: some View {
        let roomy = sizeClass == .regular
        ZStack {
            Palette.night.opacity(0.92).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 20) {
                HStack {
                    Image(ArtName.Habit.kittenBellLocked).resizable().scaledToFit().frame(width: 90)
                        .accessibilityHidden(true)
                    Spacer()
                    if resting {
                        Image(ArtName.Habit.iconHourglass).resizable().scaledToFit().frame(width: 52)
                            .accessibilityIdentifier("link.resting")
                    }
                    PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close", action: onClose)
                        .accessibilityIdentifier("link.close")
                }
                tiles
                DigitKeys(height: roomy ? 68 : 58, size: roomy ? 36 : 30, idPrefix: "link",
                          onDigit: { entry.type($0) }, onDelete: { entry.delete() }, onDone: confirm)
            }
            .padding(22)
            .frame(maxWidth: roomy ? 520 : 420)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Palette.violet)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-link")
    }

    private var tiles: some View {
        let chars = Array(entry.digits)
        return HStack(spacing: 8) {
            ForEach(0..<LinkCodeEntry.length, id: \.self) { i in
                CodeTile(char: i < chars.count ? chars[i] : nil, active: i == min(chars.count, LinkCodeEntry.length - 1))
                    .frame(maxWidth: 60)
                    .accessibilityValue(i < chars.count ? String(chars[i]) : "")
                    .accessibilityIdentifier("link.tile.\(i)")
            }
        }
        .shake(trigger: shake)
    }

    private func confirm() {
        guard entry.complete, !busy else { return nope() }
        busy = true
        Task {
            defer { busy = false }
            switch await model.kittens.link(code: entry.digits) {
            case .linked:
                Haptics.shared.success()
                Sound.shared.play(ArtName.Sound.sfxSparkle)
                onClose()
            case .tooMany:
                resting = true
                entry.clear()
                nope()
            case .wrong, .failed:
                entry.clear()
                nope()
            }
        }
    }

    private func nope() {
        shake += 1
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }
}

/// The direct notice (the server's page), the parent's mobile number, then the six numerals
/// Twilio Verify texted it (consent design §2 layer 2, D1, D6). The only words besides names are
/// the notice and the phone field: legal text, like the privacy page. The code is numerals on the
/// keypad, with pictures for another code and another number.
struct KittenNoticeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let kitten: ParentKitten

    @State private var flow: ConsentCodeState
    @State private var phone = ""
    @State private var shake = 0
    @State private var busy = false
    @State private var waiting = false
    @FocusState private var focused: Bool

    init(kitten: ParentKitten) {
        self.kitten = kitten
        _flow = State(initialValue: ConsentCodeState(state: kitten.state))
    }

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(ArtName.cat(kitten.cat, .idle)).resizable().scaledToFit().frame(width: 56)
                    NameTag(kitten.name, maxWidth: 160, active: true, size: 18)
                    Spacer()
                    PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") { dismiss() }
                        .accessibilityIdentifier("notice.close")
                }
                switch flow.phase {
                case .phone: phoneStep
                case .code: codeStep
                case .done: doneStep
                }
            }
            .padding(18)
            .frame(maxWidth: 720)
        }
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: flow.phase)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-notice")
    }

    // MARK: the notice and the number

    @ViewBuilder private var phoneStep: some View {
        NoticeWebView(url: model.config.endpoint("/privacy/kitten-notice"))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            .accessibilityIdentifier("notice.web")
        HStack(spacing: 12) {
            Image(ArtName.Habit.iconPhone).resizable().scaledToFit().frame(width: 44).accessibilityHidden(true)
            TextField(
                String(localized: "Your mobile number", comment: "The parent's phone field for consent by a texted code (legal text)"),
                text: $phone
            )
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit(send)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            .onChange(of: phone) { _, new in
                let clean = PhoneEntry.clean(new)
                if clean != new { phone = clean }
            }
            .accessibilityIdentifier("notice.phone")
            if waiting || flow.resting {
                Image(ArtName.Habit.iconHourglass).resizable().scaledToFit().frame(width: 56)
                    .accessibilityIdentifier("notice.waiting")
            } else {
                ArtIconButton(icon: ArtName.iconCheck, color: Palette.lime, size: 60, label: "Send") { send() }
                    .opacity(PhoneEntry.plausible(phone) ? 1 : 0.5)
                    .accessibilityIdentifier("notice.send")
            }
        }
        .shake(trigger: shake)
    }

    private func send() {
        guard PhoneEntry.plausible(phone), !busy else { return nope() }
        busy = true
        focused = false
        Task {
            defer { busy = false }
            switch await model.kittens.sendPhone(kitten: kitten.id, phone: phone) {
            case .sent:
                Haptics.shared.success()
                Sound.shared.play(ArtName.Sound.sfxSparkle)
                flow.sent(at: .now)
            case .notConfigured:
                // Nothing was sent; the kitten stays pending (the hourglass).
                waiting = true
            case .tooMany:
                flow.resent(.tooMany, at: .now)
                nope()
            case .failed:
                nope()
            }
        }
    }

    // MARK: the code

    private var codeStep: some View {
        let roomy = sizeClass == .regular
        let chars = Array(flow.entry.digits)
        return VStack(spacing: roomy ? 22 : 16) {
            Image(ArtName.Habit.iconPhone).resizable().scaledToFit().frame(width: roomy ? 96 : 76)
                .bounceLoop(active: flow.entry.digits.isEmpty && !flow.resting)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                ForEach(0..<LinkCodeEntry.length, id: \.self) { i in
                    CodeTile(char: i < chars.count ? chars[i] : nil, active: i == min(chars.count, LinkCodeEntry.length - 1))
                        .frame(maxWidth: 60)
                        .accessibilityValue(i < chars.count ? String(chars[i]) : "")
                        .accessibilityIdentifier("consent.tile.\(i)")
                }
            }
            .shake(trigger: shake)
            DigitKeys(height: roomy ? 68 : 58, size: roomy ? 36 : 30, idPrefix: "consent",
                      onDigit: type, onDelete: { flow.entry.delete() }, onDone: check)
                .disabled(busy || flow.resting)
                .opacity(flow.resting ? 0.5 : 1)
            HStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let ready = flow.canResend(now: context.date) && !flow.resting
                    ArtIconButton(icon: ArtName.Habit.iconResend, color: Palette.lime, size: 60, label: "Another code") { resend() }
                        .opacity(ready ? 1 : 0.45)
                        .bounceLoop(active: flow.expired && ready)
                        .accessibilityValue(ready ? "ready" : "waiting")
                        .accessibilityIdentifier("consent.resend")
                }
                .frame(width: 60, height: 60)
                ArtIconButton(icon: ArtName.Habit.iconPhone, color: Palette.sky, size: 60, label: "Another number") {
                    flow.changeNumber()
                }
                .accessibilityIdentifier("consent.number")
                if flow.resting {
                    Image(ArtName.Habit.iconHourglass).resizable().scaledToFit().frame(width: 56)
                        .accessibilityIdentifier("consent.resting")
                }
            }
        }
        .padding(roomy ? 26 : 20)
        .frame(maxWidth: roomy ? 520 : 420)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Palette.violet)
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consent.code")
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// Consent is on: the bell with a check, until the sheet closes.
    private var doneStep: some View {
        Image(ArtName.Habit.pounceBell).resizable().scaledToFit().frame(width: 180)
            .overlay(alignment: .bottomTrailing) {
                Image(ArtName.iconCheck).resizable().scaledToFit().frame(width: 64).offset(x: 6, y: 6)
            }
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("consent.done")
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func type(_ digit: Int) {
        flow.entry.type(digit)
        if flow.entry.complete { check() }
    }

    private func check() {
        guard flow.entry.complete, !busy, !flow.resting else { return nope() }
        busy = true
        let code = flow.entry.digits
        Task {
            defer { busy = false }
            let result = await model.kittens.check(kitten: kitten.id, code: code)
            flow.checked(result)
            guard result == .on else { return nope() }
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxFanfare)
            // The confirmation push (the plus) needs this device to take notifications.
            if let push = model.push, await push.authorizationStatus() == .notDetermined { _ = await push.requestAuthorization() }
            dismiss()
        }
    }

    private func resend() {
        guard flow.canResend(now: .now), !flow.resting, !busy else { return nope() }
        busy = true
        Task {
            defer { busy = false }
            let result = await model.kittens.resend(kitten: kitten.id)
            flow.resent(result, at: .now)
            if result == .sent {
                Haptics.shared.success()
                Sound.shared.play(ArtName.Sound.sfxWhoosh)
            } else {
                nope()
            }
        }
    }

    private func nope() {
        shake += 1
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }
}

/// The notice page, read-only. Links to the full policy open in place.
private struct NoticeWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0x2A / 255, green: 0x0F / 255, blue: 0x5C / 255, alpha: 1)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
