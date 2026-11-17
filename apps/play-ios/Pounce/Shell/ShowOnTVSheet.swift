import AVFoundation
import PounceKit
import SwiftUI
import UIKit

/// "Show on TV" (docs/tv-protocol.md, TV links): puts this table on a TV. The camera looks for
/// the TV's QR; "Type the TV's code" takes the six letters under it instead. A TV that shows
/// another table asks "Move the TV to this table?" first. Done, it says "On the TV" and closes,
/// and the table switches to Cards by itself once the TV is there.
///
/// No scanner on this device (the simulator, an old phone) or no camera allowed: the code entry
/// is all there is. The camera is asked for only when this sheet opens from its button, never for
/// a TV link opened on the phone. The scanner reads the QR's text and nothing else.
struct ShowOnTVSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The table to show.
    let code: String
    /// A TV's link opened on this phone: linked as soon as the sheet is up.
    var start: ScreenKey?
    /// Back to the menu this page sits in (nil: the sheet is on its own).
    var onBack: (() -> Void)?
    /// Closes the sheet (or the menu it sits in): its X, and once the table is on the TV.
    let onClose: () -> Void

    private enum Mode: Equatable { case starting, scan, type }
    private enum Step: Equatable { case idle, linking, linked }

    @State private var mode: Mode = .starting
    @State private var step: Step = .idle
    @State private var typed = ""
    /// Why the last try didn't work, in place of what to do, until the next key or scan.
    @State private var message: String?
    /// The TV shows another table: "Move the TV to this table?" for this key.
    @State private var moving: ScreenKey?
    /// Tokens already tried from the camera: a code still in view isn't sent again, unless the
    /// try failed on the way or the move was cancelled (`TVCode.retriesScan`).
    @State private var tried: Set<String> = []
    @State private var shake = 0
    @State private var began = false
    /// Closes the sheet a moment after "On the TV"; cancelled if the sheet goes first.
    @State private var closing: Task<Void, Never>?

    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                SheetBar(
                    title: String(localized: "Show on TV", comment: "Show on TV: the sheet's title"),
                    onBack: step == .linked ? nil : onBack, backID: "tv.back",
                    onClose: step == .linked ? nil : onClose, closeID: "tv.close")
                content(Self.area(geo.size, roomy: roomy))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25).paced, value: mode)
        .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: step)
        .animation(.easeOut(duration: 0.2).paced, value: message)
        .alert(
            String(localized: "Move the TV to this table?", comment: "Show on TV: the TV shows another table"),
            isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })
        ) {
            Button(String(localized: "Move", comment: "Show on TV: move the TV to this table")) {
                if let key = moving { link(key, move: true) }
                moving = nil
            }
            .accessibilityIdentifier("tv.move")
            Button(String(localized: "Cancel", comment: "Show on TV: leave the TV where it is"), role: .cancel) {
                if let key = moving { mayRetry(key, after: nil) }
                moving = nil
            }
            .accessibilityIdentifier("tv.move.cancel")
        }
        .task { await begin() }
        .onDisappear { closing?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-tv")
    }

    @ViewBuilder private func content(_ area: Area) -> some View {
        switch (step, mode) {
        case (.linked, _):
            linked
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case (_, .starting):
            YarnIndicator()
        case (_, .scan):
            scan(area)
                .transition(.opacity)
        case (_, .type):
            type(area)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: scanning

    private func scan(_ area: Area) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            QRScanner(
                active: step == .idle && moving == nil,
                onText: scanned,
                onUnavailable: { mode = .type })
                .frame(width: area.camera, height: area.camera)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
                .overlay { if step == .linking { YarnIndicator() } }
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                .accessibilityElement()
                .accessibilityLabel(Text("Camera", comment: "VoiceOver: Show on TV's camera, looking for the TV's code"))
                .accessibilityIdentifier("tv.scanner")
            line(nil)
            PillButton(
                icon: ArtName.iconKeypad, color: Palette.violet, size: .medium, width: min(area.width, 320),
                title: String(localized: "Type the TV's code", comment: "Show on TV: type the code under the TV's QR instead"),
                accessibilityLabel: "Type the TV's code"
            ) {
                message = nil
                mode = .type
            }
            .accessibilityIdentifier("tv.type")
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    /// A QR's text from the camera: a TV's link links; anything else is ignored and the camera
    /// keeps looking.
    private func scanned(_ text: String) {
        guard step == .idle, moving == nil, let token = TVCode.token(scanned: text), !tried.contains(token) else { return }
        tried.insert(token)
        link(.token(token))
    }

    // MARK: typing

    private func type(_ area: Area) -> some View {
        VStack(spacing: area.gap) {
            line(String(localized: "Type the TV's code", comment: "Show on TV: what to do with the code entry"))
            CodeTiles(typed: typed, length: TVCode.length, busy: step != .idle, idPrefix: "tv.tile")
                .frame(width: area.width)
                .shake(trigger: shake)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("TV code", comment: "VoiceOver: the tiles that show the TV's code as it is typed"))
                .accessibilityValue(Text(verbatim: typed.map(String.init).joined(separator: " ")))
                .accessibilityIdentifier("tv.code")
            CodeKeypad(
                enabled: step == .idle, keyHeight: area.key, keySize: min(30, area.key * 0.56), spacing: area.keyGap,
                idPrefix: "tv.key", onKey: key, onDelete: delete)
                .frame(width: area.width)
            let ready = typed.count == TVCode.length && step == .idle
            PillButton(
                icon: nil, color: ready ? Palette.orange : Palette.violet.mix(with: Palette.night, by: 0.45),
                size: .medium, width: min(area.width, 260),
                title: String(localized: "Show", comment: "Show on TV: put the table on the TV with the typed code"),
                accessibilityLabel: "Show"
            ) {
                show()
            }
            .groupOpacity(ready ? 1 : 0.8)
            .shadow(color: ready ? Palette.orange.opacity(0.7) : .clear, radius: 12)
            .wiggle(trigger: shake)
            .accessibilityIdentifier("tv.show")
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func key(_ c: Character) {
        guard step == .idle, typed.count < TVCode.length else { return }
        message = nil
        typed.append(c)
    }

    private func delete() {
        guard step == .idle, !typed.isEmpty else { return }
        message = nil
        typed.removeLast()
    }

    private func show() {
        guard step == .idle else { return }
        guard let code = TVCode.normalized(typed) else {
            shake += 1
            Haptics.shared.thump()
            return
        }
        link(.code(code))
    }

    // MARK: the line under the title

    /// What to do (`prompt`), or why the last try didn't work, or the yarn while linking: one line,
    /// always the same height, so nothing under it moves.
    private func line(_ prompt: String?) -> some View {
        ZStack {
            if step == .linking, mode == .type {
                YarnIndicator()
                    .scaleEffect(0.7)
                    .transition(.opacity)
            } else if let message {
                lineText(message, color: Palette.yellow)
                    .accessibilityIdentifier("tv.message")
            } else if let prompt {
                lineText(prompt, color: .white)
                    .accessibilityIdentifier("tv.prompt")
            }
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func lineText(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .transition(.opacity)
    }

    // MARK: done

    private var linked: some View {
        VStack(spacing: 18) {
            Image(ArtName.iconTV)
                .resizable()
                .scaledToFit()
                .frame(width: roomy ? 180 : 140)
                .overlay(alignment: .bottomTrailing) {
                    Image(ArtName.iconCheck)
                        .resizable()
                        .scaledToFit()
                        .frame(width: roomy ? 70 : 56)
                        .offset(x: 14, y: 10)
                }
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
            OutlinedText(String(localized: "On the TV", comment: "Show on TV: the table is on the TV now"), size: roomy ? 48 : 40, fill: Palette.lime, width: 4)
        }
        .padding(.bottom, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("On the TV", comment: "Show on TV: the table is on the TV now"))
        .accessibilityIdentifier("tv.linked")
    }

    // MARK: linking

    /// The first look: the camera when there is a scanner and it may be used (asked for here,
    /// only when the button opened the sheet), else the code entry. Then a TV link, if one came.
    private func begin() async {
        guard !began else { return }
        began = true
        mode = await Self.firstMode(askForCamera: start == nil)
        if let start { link(start) }
    }

    /// `TVSheetStart` decides; this only reads the device and asks the system's question.
    private static func firstMode(askForCamera: Bool) async -> Mode {
        let start = TVSheetStart.first(
            supported: QRScanner.supported, available: QRScanner.canScan,
            permission: cameraPermission, askForCamera: askForCamera)
        switch start {
        case .scan: return .scan
        case .type: return .type
        case .askForCamera:
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            return TVSheetStart.afterAsking(allowed: allowed, available: QRScanner.canScan) == .scan ? .scan : .type
        }
    }

    private static var cameraPermission: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        default: .denied
        }
    }

    private func link(_ key: ScreenKey, move: Bool = false) {
        step = .linking
        message = nil
        let api = model.api
        let room = code
        Task {
            do {
                switch try await api.linkScreen(key, room: room, move: move) {
                case .linked: done()
                case .showing:
                    step = .idle
                    moving = key
                }
            } catch {
                mayRetry(key, after: error)
                refused(Self.words(for: error))
            }
        }
    }

    /// A scanned QR that didn't link may be scanned again, unless the server refused it. After a
    /// moment: the camera sees a code in view many times a second, so it isn't sent again at
    /// once (the words stay up to read, and a Cancel isn't asked again right away).
    private func mayRetry(_ key: ScreenKey, after error: (any Error)?) {
        guard case .token(let token) = key, TVCode.retriesScan(after: error) else { return }
        Task {
            try? await Task.sleep(for: Pace.duration(.seconds(2)))
            tried.remove(token)
        }
    }

    private func done() {
        step = .linked
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxSparkle)
        let words = String(localized: "On the TV", comment: "Show on TV: the table is on the TV now")
        UIAccessibility.post(notification: .announcement, argument: words)
        // Long enough to read at any speed (it is words, not an animation), then the table. A
        // sheet that went away before then (closed, or replaced by a newer request) closes nothing.
        closing = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    private func refused(_ words: String) {
        step = .idle
        message = words
        shake += 1
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
        UIAccessibility.post(notification: .announcement, argument: words)
        Task {
            try? await Task.sleep(for: Pace.duration(.milliseconds(380)))
            withAnimation(.spring(duration: 0.3).paced) { typed = "" }
        }
    }

    /// One short sentence for each refusal (the server's answers, docs/tv-protocol.md).
    static func words(for error: any Error) -> String {
        switch error as? ScreenLinkError {
        case .notFound?:
            // Also an old server, or one with no TVs: there is no such TV for this phone.
            String(localized: "No TV with that code.", comment: "Show on TV: no TV has that code (or it ran out)")
        case .tooManyAttempts?:
            String(localized: "Too many wrong codes. Try again later.", comment: "Show on TV: too many wrong codes from this phone")
        case .notSeated?:
            String(localized: "Take a seat first.", comment: "Show on TV: only a phone with a seat at the table can put it on a TV")
        case .seated?:
            String(localized: "That TV has a seat here.", comment: "Show on TV: the TV's device plays at this table, so it can't show it")
        case nil:
            String(localized: "Didn't go through. Try again.", comment: "Show on TV: no connection, or the server failed")
        }
    }

    // MARK: sizes

    /// How big things are in the space the sheet has: the camera's square, the column's width,
    /// the keys' height (smaller keys on a short screen such as the SE, so nothing clips).
    struct Area {
        var width: CGFloat
        var camera: CGFloat
        var key: CGFloat
        var keyGap: CGFloat
        var gap: CGFloat
    }

    static func area(_ size: CGSize, roomy: Bool) -> Area {
        let width = min(size.width - 32, roomy ? 480 : 420)
        // Under the sheet's bar: the line, the tiles, five rows of keys and the Show pill.
        let bar: CGFloat = 76
        let line: CGFloat = 50
        let tile = ((width - 20 - 5 * 6) / 6) / 0.86 + 20 + 6
        let pill = PillSize.medium.height + 6
        let gap: CGFloat = size.height < 700 ? 8 : 14
        let keyGap: CGFloat = size.height < 700 ? 6 : 8
        let rest = size.height - bar - line - tile - pill - 3 * gap - 16
        // Five rows: each a key and its 5 pt lip, with four gaps (the keypad adds 2 between rows).
        let key = ((rest - 4 * (keyGap + 2)) / 5 - 5).clamped(to: 36...(roomy ? 64 : 54))
        let camera = min(width, size.height - bar - line - pill - 2 * 14 - 40, roomy ? 460 : 360)
        return Area(width: width, camera: max(160, camera), key: key, keyGap: keyGap, gap: gap)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
