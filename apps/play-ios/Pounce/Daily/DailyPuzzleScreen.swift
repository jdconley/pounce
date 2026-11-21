import PounceKit
import SwiftUI

/// One daily puzzle (daily games design §7, "A puzzle screen"): the host around a game's board.
///
/// It starts (or resumes) the run off the main actor, decodes the start answer there, and builds
/// the game's `DailyGameView`. Around it: the top bar (back, the game and number, the clock from
/// the server's start, Show on TV while a TV shows a board you're on, give up), a line while the
/// connection is retrying, a line in the day's last 15 minutes, and the end screen once the
/// server says the run ended. The game draws only its board and controls.
struct DailyPuzzleScreen: View {
    let game: String

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Phase {
        case loading
        case missing
        case offline
        case playing(DailyRunSession, DailyPlayable)
    }

    @State private var phase: Phase = .loading
    @State private var hints = 0
    @State private var link: DailyLink = .ok
    @State private var result: DailyResult?
    @State private var onTV = false
    @State private var askGiveUp = false
    @State private var givingUp = false
    @State private var attempt = 0

    private var roomy: Bool { sizeClass == .regular }
    private var info: DailyGameInfo { DailyCatalog.info(game) ?? DailyGameInfo(id: game, title: game, scoring: .time, hints: false, tint: 0x7B2FFF) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .background { background }
            .task(id: attempt) { await begin() }
            .task(id: model.daily.enabled == true) {
                if model.daily.enabled == true { await model.daily.listen() }
            }
            .confirmationDialog(
                String(localized: "Give up?", comment: "Daily puzzle: confirm giving up"), isPresented: $askGiveUp, titleVisibility: .visible
            ) {
                Button(String(localized: "Give up", comment: "Daily puzzle: end the run unsolved"), role: .destructive) { giveUp() }
                    .accessibilityIdentifier("daily.giveup.confirm")
                Button(String(localized: "Keep playing", comment: "Daily puzzle: don't give up"), role: .cancel) {}
            }
            .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: result)
            .animation(.easeOut(duration: 0.2).paced, value: link)
            .frameGate()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen-daily")
    }

    private var background: some View {
        ZStack {
            Palette.night
            LinearGradient(
                colors: [DailyArt.tint(info).mix(with: Palette.night, by: 0.55), Palette.night], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            YarnIndicator()
        case .missing:
            note(String(localized: "This puzzle isn't here today.", comment: "Daily puzzle: the server doesn't list it"), retry: false)
        case .offline:
            note(String(localized: "No connection.", comment: "Daily puzzle: couldn't reach the server"), retry: true)
        case .playing(let session, let playable):
            if let result {
                DailyEndView(game: info, result: result, session: session, marks: playable.marks)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    notices(session)
                    playable.make(session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onDisappear { Task { await session.flush() } }
            }
        }
    }

    private func note(_ text: String, retry: Bool) -> some View {
        VStack(spacing: 18) {
            OutlinedText(text, size: roomy ? 30 : 24, width: 3, lines: 2)
                .padding(.horizontal, 24)
            if retry {
                PillButton(icon: nil, color: Palette.orange, size: .medium, width: 200, title: String(localized: "Try again", comment: "Daily puzzle: start again after no connection"), accessibilityLabel: "Try again") {
                    phase = .loading
                    attempt += 1
                }
                .accessibilityIdentifier("daily.retry")
            }
        }
        .accessibilityIdentifier("daily.note")
    }

    /// "Reconnecting", and in the day's last 15 minutes, when the Dish turns over.
    @ViewBuilder private func notices(_ session: DailyRunSession) -> some View {
        VStack(spacing: 6) {
            if link == .retrying {
                pill(String(localized: "Reconnecting", comment: "Daily puzzle: the connection dropped; moves are kept"), color: Palette.orange, id: "daily.reconnecting")
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if session.clock.remainingMs(at: context.date) < 15 * 60_000 {
                    pill(String(localized: "The Dish turns over at 4:00", comment: "Daily puzzle: started in the day's last 15 minutes"), color: Palette.violet, id: "daily.closing")
                }
            }
        }
        .padding(.top, 4)
    }

    private func pill(_ text: String, color: Color, id: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: roomy ? 18 : 15, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(color).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .compositingGroup()
            .transition(.scale.combined(with: .opacity))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityIdentifier(id)
    }

    // MARK: the bar

    private var topBar: some View {
        HStack(spacing: 8) {
            CornerHomeButton(label: "Back") { model.showDish() }
                .accessibilityIdentifier("daily.back")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: info.title)
                    .font(.system(size: roomy ? 22 : 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if case .playing(let session, _) = phase, session.start.number > 0 {
                    Text(verbatim: "No. \(session.start.number)")
                        .font(.system(size: roomy ? 15 : 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            clock
            if case .playing(let session, _) = phase, result == nil {
                if model.daily.tvs > 0 { tvSwitch(session) }
                giveUpButton
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: model.daily.tvs > 0)
    }

    /// The server's time from the start, counted here once a second; frozen at the result's.
    @ViewBuilder private var clock: some View {
        if case .playing(let session, _) = phase {
            Group {
                if let result {
                    clockText(DailyClock.format(ms: Int64(result.timeMs)))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        clockText(DailyClock.format(ms: session.clock.elapsedMs(at: context.date, hints: hints)))
                    }
                }
            }
            .accessibilityIdentifier("daily.clock")
        }
    }

    private func clockText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: roomy ? 24 : 19, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.yellow).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .fixedSize()
            .accessibilityLabel(Text("Time \(text)", comment: "VoiceOver: the daily puzzle's clock"))
    }

    /// Show on TV: there only while a TV shows a board you're on (daily games design §8).
    private func tvSwitch(_ session: DailyRunSession) -> some View {
        Button {
            Haptics.shared.tick()
            let next = !onTV
            onTV = next
            Task {
                do { try await session.showOnTV(next) } catch { onTV = !next }
            }
        } label: {
            Image(ArtName.iconTV)
                .resizable().scaledToFit()
                .padding(7)
                .frame(width: 46, height: 46)
                .background(Circle().fill(onTV ? Palette.lime : Palette.ink.opacity(0.5)))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(Text("Show on TV", comment: "Daily puzzle: show this run on the TV"))
        .accessibilityValue(onTV ? Text("On", comment: "VoiceOver: a switch is on") : Text("Off", comment: "VoiceOver: a switch is off"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("daily.tv")
    }

    private var giveUpButton: some View {
        Button {
            Haptics.shared.tick()
            askGiveUp = true
        } label: {
            Image(systemName: "flag.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Palette.ink.opacity(0.5)))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .disabled(givingUp)
        .accessibilityLabel(Text("Give up", comment: "Daily puzzle: the give up button"))
        .accessibilityIdentifier("daily.giveup")
    }

    // MARK: the run

    private func begin() async {
        guard let type = DailyHost.playable(game) else {
            phase = .missing
            return
        }
        let service = model.daily.service
        let person = model.people.owner?.id
        do {
            let session = try await DailyRunSession.begin(game: game, service: service, person: person)
            let playable = try await DailyHost.prepare(type, session)
            hints = session.start.hints
            result = session.start.result
            phase = .playing(session, playable)
            for await event in await session.events() {
                switch event {
                case .hinted(_, let count, _): hints = count
                case .resync(let start): hints = start.hints
                case .ended(let ended): finish(ended)
                case .link(let next): link = next
                case .accepted: break
                }
            }
        } catch APIError.notFound {
            phase = .missing
        } catch is CancellationError {
        } catch {
            phase = .offline
        }
    }

    private func finish(_ ended: DailyResult) {
        guard result == nil else { return }
        result = ended
        onTV = false
        model.daily.record(ended)
        if ended.outcome.finished {
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxSparkle)
        }
        Task {
            await model.refreshDaily()
            await model.daily.refreshStats()
        }
    }

    private func giveUp() {
        guard case .playing(let session, _) = phase else { return }
        givingUp = true
        Task {
            await session.giveUp()
            givingUp = false
        }
    }
}
