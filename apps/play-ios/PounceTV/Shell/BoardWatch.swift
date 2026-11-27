import PounceKit
import SwiftUI

/// Watching a puzzle on the TV (daily games design §8): the card that offers it, and the host that
/// draws the run from the server's frames. Each game brings its own read-only `DailyWatchView`,
/// listed in `DailyWatchGames`; a game not listed yet gets a placeholder. The web TV's `tv-watch.tsx`.
private struct WatchStage: View {
    let game: String
    let frame: TVBoardState.Frame?
    /// The listed game's view for the latest frame, decoded off the main actor.
    @State private var built: (@MainActor @Sendable () -> AnyView)?

    var body: some View {
        if let watch = DailyWatchGames.view(for: game) {
            ZStack {
                if let built {
                    built()
                } else {
                    WatchPlaceholder(game: game)
                }
            }
            .task(id: frame) {
                guard let frame else { return }
                // The last frame stays drawn until the next one is decoded.
                if let next = await watch.frame(puzzle: frame.puzzle, state: frame.state) { built = next }
            }
        } else if game == DailyCatalog.test.id, let n = frame?.state["n"], case .int(let count) = n {
            TestWatch(n: count)
        } else {
            WatchPlaceholder(game: game)
        }
    }
}

/// The server's test game ("count to N"): the number reached, big.
private struct TestWatch: View {
    let n: Int

    var body: some View {
        OutlinedText("\(n)", size: 420, width: 14)
            .accessibilityIdentifier("tv.watch.count")
            .accessibilityValue("\(n)")
    }
}

/// A game whose watch view hasn't landed yet: its name, and that someone is at it.
private struct WatchPlaceholder: View {
    let game: String

    var body: some View {
        VStack(spacing: 32) {
            OutlinedText(TVBoardState.title(game), size: 120, width: 8)
                .accessibilityIdentifier("tv.watch.placeholder")
            Image(ArtName.Habit.iconHourglass)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
        }
    }
}

/// The card: "Mom is playing Sniff. Spoilers." Not now has the remote's focus.
struct WatchCard: View {
    let offer: TVBoardState.Offer
    let watch: () -> Void
    let notNow: () -> Void
    @FocusState private var focus: Choice?

    private enum Choice: Hashable { case watch, notNow }

    var body: some View {
        HStack(spacing: 28) {
            Image(ArtName.cat(offer.cat % ArtName.catCount, .awake))
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 20) {
                OutlinedText(TVBoardState.offerWords(name: offer.name, game: offer.game), size: 50, width: 4, lines: 2, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 28) {
                    Button {
                        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                        watch()
                    } label: {
                        TVButtonLabel(icon: ArtName.iconPlay, words: String(localized: "Watch", comment: "TV: the watch card's button that shows the run"), size: 46)
                    }
                    .buttonStyle(TVButtonStyle(tint: Palette.violet))
                    .focused($focus, equals: .watch)
                    .accessibilityIdentifier("tv.watch.watch")
                    Button {
                        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                        notNow()
                    } label: {
                        TVButtonLabel(icon: ArtName.iconBack, words: String(localized: "Not now", comment: "TV: the watch card's button that closes it"), size: 46)
                    }
                    .buttonStyle(TVButtonStyle(tint: Palette.magenta))
                    .focused($focus, equals: .notNow)
                    .accessibilityIdentifier("tv.watch.notNow")
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(width: 1180)
        .background(RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 48, style: .continuous).strokeBorder(Palette.ink, lineWidth: 8))
        .background(RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Palette.ink).offset(y: 16))
        .compositingGroup()
        .focusSection()
        .defaultFocus($focus, .notNow)
        .task {
            // The remote lands on Not now: watching is a choice, never an accident.
            try? await Task.sleep(for: .milliseconds(60))
            focus = .notNow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TVBoardState.offerWords(name: offer.name, game: offer.game))
        .accessibilityIdentifier("tv.watch.card")
    }
}

/// A run, live: who and which game on top, the game's own view below, its result once it ends.
struct WatchHost: View {
    let watching: TVBoardState.Watching
    let frame: TVBoardState.Frame?
    let ended: TVBoardState.Ended?
    let back: () -> Void
    @FocusState private var backFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Image(ArtName.cat(watching.cat % ArtName.catCount, .idle))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                OutlinedText(watching.name, size: 64, width: 5, alignment: .leading)
                    .fixedSize()
                Text(TVBoardState.title(watching.game))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.yellow))
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 5))
                    // On a leaf: a container's identifier folds into the board's.
                    .accessibilityIdentifier("tv.watch.view.\(watching.game)")
                Spacer()
                Button(action: back) {
                    TVButtonLabel(icon: ArtName.iconBack, words: String(localized: "Board", comment: "TV: from a watched run back to the board"), size: 42)
                        .frame(width: 340)
                }
                .buttonStyle(TVButtonStyle(tint: Palette.violet))
                .focused($backFocused)
                .accessibilityIdentifier("tv.watch.back")
            }
            WatchStage(game: watching.game, frame: frame)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if let ended { EndedView(ended: ended, cat: watching.cat).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.4), value: ended)
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            backFocused = true
        }

    }
}

private struct EndedView: View {
    let ended: TVBoardState.Ended
    let cat: Int

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.92).ignoresSafeArea()
            Image(ArtName.sunburst)
                .resizable()
                .frame(width: 1400, height: 1400)
                .opacity(0.4)
            VStack(spacing: 12) {
                Image(ArtName.cat(cat % ArtName.catCount, ended.result.finished ? .celebrate : .idle))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                OutlinedText(title, size: 140, width: 10)
                // The time, guesses or points; or how far the run got ("62%").
                Text(TVBoardState.resultWords(ended.result))
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.yellow)
            }
        }
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tv.watch.ended")
    }

    private var title: String {
        switch ended.result.outcome {
        case .solved: String(localized: "Solved", comment: "TV: a watched run, solved")
        case .done: String(localized: "Done", comment: "TV: a watched Box Fort run, ended")
        case .missed:
            ended.result.game == DailyCatalog.nineLives.id
                ? String(localized: "Out of lives", comment: "TV: a watched Nine Lives run, out of lives")
                : String(localized: "Missed", comment: "TV: a watched Sniff run, out of guesses")
        case .gaveUp: String(localized: "Gave up", comment: "TV: a watched run, given up")
        case .closed, .other: String(localized: "Closed", comment: "TV: a watched run, closed at the day's end")
        }
    }
}
