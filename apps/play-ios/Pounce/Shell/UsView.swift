import PounceKit
import SwiftUI

/// The Us screen (spec §10.2): a row of your pairs' cats to switch between them (long-press one to
/// pin it as your top pair or leave that streak; a ghosted cat with a plus starts a left streak
/// afresh), the Cat Condo with both cats and the toys, the big numeral, today's two paws, this
/// week's strip, three stat tiles (best, days together, perfect weeks), the next-milestone arc and
/// any gifts waiting, and the pause suitcase. With no shared table in play a big Play pill starts
/// a game. No words but names and numerals.
struct UsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selected: String?
    @State private var bubble: String?
    @State private var leaving: StreakView?
    @State private var pausing: StreakView?
    @State private var opening: (pair: StreakView, gift: StreakView.Gift)?
    @State private var signIn = false

    private var store: StreakStore { model.streaks }

    private var current: StreakView? {
        store.pairs.first { $0.pair == selected } ?? store.top
    }

    private var mine: Int { model.people.owner?.cat ?? 0 }

    /// The pairs row is bigger on a roomy screen.
    private var rowScale: CGFloat { sizeClass == .regular ? 1.4 : 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let view = current {
                    content(view, size: geo.size)
                } else {
                    empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background { background }
        .overlay { overlays }
        .animation(.easeOut(duration: 0.25).paced, value: overlayKey)
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: current?.pair)
        .task { await model.refreshStreaks() }
        .task {
            // Home's gift: open it here.
            guard let id = model.pendingGift else { return }
            model.pendingGift = nil
            if let view = store.pairs.first(where: { $0.gifts.contains { $0.id == id } }),
               let gift = view.gifts.first(where: { $0.id == id }) {
                selected = view.pair
                opening = (view, gift)
            }
        }
        #if DEBUG
        .task {
            // `-show-gift`: the first gift opens at launch (screenshots).
            guard CommandLine.arguments.contains("-show-gift") else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if let view = store.pairs.first(where: { !$0.gifts.isEmpty }), let gift = view.gifts.first {
                selected = view.pair
                opening = (view, gift)
            }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-us")
    }

    private var overlayKey: String {
        "\(leaving?.pair ?? "")|\(pausing?.pair ?? "")|\(opening?.gift.id ?? "")|\(signIn)|\(bubble ?? "")"
    }

    private var background: some View {
        ZStack {
            Palette.night
            Image(ArtName.homeBg).resizable().scaledToFill().opacity(0.55).accessibilityHidden(true)
            Palette.night.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    // MARK: top: back, the pairs row, the cloud

    private var topBar: some View {
        VStack(spacing: 4) {
            topRow
            if let pair = bubble, let view = store.pairs.first(where: { $0.pair == pair }) {
                pairBubble(view)
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("us.back")
            pairsRow
            if offerSignIn {
                CloudPlusBubble(size: 44) { signIn = true }
                    .accessibilityIdentifier("us.cloud")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var offerSignIn: Bool {
        StreakBadge.make(store.top, all: store.pairs, signedIn: model.account.isSignedIn,
                         offersSignIn: model.account.offersSignIn)?.offerSignIn ?? false
    }

    private var pairsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(store.pairs.enumerated()), id: \.element.pair) { i, view in
                    pairCat(view, index: i)
                }
                ForEach(Array(store.left.enumerated()), id: \.element.pair) { i, ghost in
                    ghostCat(ghost, index: i)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity)
    }

    private func pairCat(_ view: StreakView, index: Int) -> some View {
        let on = view.pair == current?.pair
        return VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(ArtName.cat(view.partner.cat, .idle))
                    .resizable().scaledToFit()
                    .padding(4)
                    .frame(width: (on ? 62 : 52) * rowScale, height: (on ? 62 : 52) * rowScale)
                    .background(Circle().fill(on ? Palette.teal : Palette.violet))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                if view.pinned {
                    Image(ArtName.Habit.iconPin).resizable().scaledToFit().frame(width: 20).offset(x: 4, y: -4)
                }
                if !view.gifts.isEmpty {
                    Image(ArtName.Habit.giftBox).resizable().scaledToFit().frame(width: 22).offset(x: 6, y: 34)
                }
            }
            NameTag(view.partner.name, maxWidth: 76 * rowScale, active: on, size: 13 * rowScale)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            bubble = nil
            selected = view.pair
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.shared.thump()
            selected = view.pair
            bubble = view.pair
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(view.partner.name), \(view.count)", comment: "VoiceOver: a pair's cat on the Us screen"))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("us.pair.\(index)")
        .accessibilityAction(named: Text("Pin", comment: "VoiceOver: pin a pair as the top one")) { pin(view) }
        .accessibilityAction(named: Text("Leave", comment: "VoiceOver: leave a streak")) { leaving = view }
    }

    /// Long-press: pin, or the trash can (§14).
    private func pairBubble(_ view: StreakView) -> some View {
        HStack(spacing: 10) {
            ArtIconButton(icon: ArtName.Habit.iconPin, color: Palette.orange, size: 48, label: "Pin") { pin(view) }
                .accessibilityIdentifier("us.pin")
            ArtIconButton(icon: ArtName.Habit.iconTrash, color: Palette.magenta, size: 48, label: "Leave") {
                bubble = nil
                leaving = view
            }
            .accessibilityIdentifier("us.leave")
        }
        .padding(8)
        .background(Capsule().fill(Palette.night).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
        .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
    }

    private func ghostCat(_ ghost: LeftPair, index: Int) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            Task { await store.rejoin(ghost.pair) }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .bottomTrailing) {
                    Image(ArtName.cat(ghost.partner.cat, .idle))
                        .resizable().scaledToFit()
                        .padding(4)
                        .frame(width: 52 * rowScale, height: 52 * rowScale)
                        .saturation(0.2)
                        .opacity(0.45)
                        .background(Circle().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [6, 5])))
                    Image(ArtName.iconPlus).resizable().scaledToFit().frame(width: 22)
                        .background(Circle().fill(Palette.lime).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2)))
                }
                NameTag(ghost.partner.name, maxWidth: 76 * rowScale, size: 13 * rowScale).opacity(0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Start a streak with \(ghost.partner.name) again", comment: "VoiceOver: a ghosted cat on the Us screen"))
        .accessibilityIdentifier("us.ghost.\(index)")
    }

    // MARK: the pair

    @ViewBuilder private func content(_ view: StreakView, size: CGSize) -> some View {
        let roomy = sizeClass == .regular
        if roomy && Roomy.sideBySide(size, minWidth: 900) {
            HStack(spacing: 48) {
                hero(view, side: min(size.height * 0.7, 640))
                    .frame(maxWidth: .infinity)
                details(view, scale: 1.6)
                    .frame(width: min(size.width * 0.45, 620))
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: roomy ? 28 : 16) {
                    hero(view, side: roomy ? min(size.width * 0.66, 600) : min(size.width - 60, 300))
                    details(view, scale: roomy ? 1.6 : 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func hero(_ view: StreakView, side: CGFloat) -> some View {
        VStack(spacing: 4) {
            CondoView(view: view, mine: mine, side: side, seenStage: model.condoSeen[view.pair]) { stage in
                model.noteCondoSeen(pair: view.pair, stage: stage)
            }
            .id(view.pair)
            HStack(spacing: side * 0.06) {
                pawCat(mine, lit: view.me || view.kept, scale: side / 300)
                numeral(view, size: side * 0.26)
                pawCat(view.partner.cat, lit: view.them || view.kept, scale: side / 300)
            }
            .overlay { todayPaws(view) }
        }
    }

    private func numeral(_ view: StreakView, size: CGFloat) -> some View {
        let mode = StreakBadge.mode(view)
        return HStack(alignment: .center, spacing: 10) {
            OutlinedText(String(view.count), size: size, fill: .white, width: max(3, size / 16))
                .contentTransition(.numericText(value: Double(view.count)))
                .fixedSize()
            switch mode {
            case .winback(let kept):
                VStack(spacing: 4) {
                    Image(ArtName.Habit.pawBandage).resizable().scaledToFit().frame(width: size * 0.45)
                    HStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(i < kept ? Palette.lime : Palette.night)
                                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                                .frame(width: size * 0.14, height: size * 0.14)
                        }
                    }
                }
            case .paused:
                Image(ArtName.Habit.pawSuitcase).resizable().scaledToFit().frame(width: size * 0.5)
            case .napped:
                Image(ArtName.Habit.pawNap).resizable().scaledToFit().frame(width: size * 0.45)
            case .fresh:
                Image(ArtName.fxSparkle).resizable().scaledToFit().frame(width: size * 0.4).bounceLoop(active: true)
            case .normal:
                EmptyView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("us.count")
        .accessibilityLabel(String(view.count))
        .accessibilityValue(PawBadge.modeName(mode))
    }

    private func details(_ view: StreakView, scale: CGFloat) -> some View {
        VStack(spacing: 16 * scale) {
            WeekStrip(week: view.week, size: 34 * scale)
            HStack(spacing: 12 * scale) {
                StatTile(icon: ArtName.iconTrophy, number: view.best, color: Palette.orange, id: "us.stat.best", scale: scale)
                StatTile(icon: ArtName.Habit.iconDays, number: view.lifetimeKept, color: Palette.magenta, id: "us.stat.days", scale: scale)
                StatTile(icon: ArtName.Habit.iconWeeks, number: view.perfectWeeks, color: Palette.teal, id: "us.stat.weeks", scale: scale)
            }
            HStack(spacing: 14 * scale) {
                MilestoneArc(count: view.count, next: view.next, side: 84 * scale)
                ForEach(view.gifts) { gift in
                    giftTile(view, gift, scale: scale)
                }
                ArtIconButton(icon: ArtName.Habit.iconPause, color: view.pausedUntil == nil ? Palette.sky : Palette.orange,
                              size: 60 * scale, label: "Pause") { pausing = view }
                    .accessibilityIdentifier("us.pause")
            }
            if view.myMove.isEmpty && view.theirMove.isEmpty {
                PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .large, width: 150 * scale,
                           accessibilityLabel: "Play") {
                    Task { await model.newGame() }
                }
                .accessibilityIdentifier("us.play")
            }
        }
    }

    /// Today's two paws for VoiceOver and the tests: mine, then theirs.
    private func todayPaws(_ view: StreakView) -> some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(Text("Today", comment: "VoiceOver: today's two paws on the Us screen"))
            .accessibilityIdentifier("us.paws")
            .accessibilityValue("\(view.me || view.kept ? 1 : 0)|\(view.them || view.kept ? 1 : 0)")
    }

    /// One of today's two paws, under its cat (§14: both people see both; they're the turn cue).
    private func pawCat(_ cat: Int, lit: Bool, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image(ArtName.cat(cat, .idle)).resizable().scaledToFit().frame(width: 42 * scale)
            Image(lit ? ArtName.Habit.pawOne : ArtName.Habit.pawGrey).resizable().scaledToFit().frame(width: 32 * scale)
                .scaleEffect(lit ? 1.1 : 0.9)
                .animation(.spring(duration: 0.35, bounce: 0.6).paced, value: lit)
        }
        .padding(6 * scale)
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).fill(lit ? Palette.violet : Palette.night)
            .overlay(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3)))
        .accessibilityHidden(true)
    }

    private func giftTile(_ view: StreakView, _ gift: StreakView.Gift, scale: CGFloat) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            opening = (view, gift)
        } label: {
            Image(ArtName.Habit.giftBox)
                .resizable().scaledToFit()
                .frame(width: 84 * scale, height: 84 * scale)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .bounceLoop(active: true)
        .accessibilityLabel(Text("Open the gift", comment: "VoiceOver: an unopened milestone gift"))
        .accessibilityIdentifier("us.gift.\(gift.id)")
    }

    private var empty: some View {
        VStack(spacing: 20) {
            Image(ArtName.Habit.catsAsleepCondo).resizable().scaledToFit().frame(width: 260)
            PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .large, width: 160, accessibilityLabel: "Play") {
                Task { await model.newGame() }
            }
            .accessibilityIdentifier("us.play")
        }
    }

    // MARK: overlays

    @ViewBuilder private var overlays: some View {
        if let opening {
            GiftReveal(gift: opening.gift, mine: mine, theirs: opening.pair.partner.cat) {
                await store.openGift(opening.pair.pair, opening.gift.id)
            } onDone: {
                self.opening = nil
            }
            .transition(.opacity)
        } else if let pausing {
            PauseDial(paused: store.pair(pausing.pair)?.pausedUntil != nil) { days in
                self.pausing = nil
                Task { await store.pause(pausing.pair, days: days) }
            } onEnd: {
                self.pausing = nil
                Task { await store.unpause(pausing.pair) }
            } onBack: {
                self.pausing = nil
            }
            .transition(.opacity)
        } else if let leaving {
            LeaveConfirm(mine: mine, theirs: leaving.partner.cat, name: leaving.partner.name) {
                self.leaving = nil
                selected = nil
                Task { await store.leave(leaving.pair) }
            } onBack: {
                self.leaving = nil
            }
            .transition(.opacity)
        } else if signIn, let owner = model.people.owner {
            ZStack {
                Palette.night.opacity(0.85).ignoresSafeArea().onTapGesture { signIn = false }
                SignInOffer(identifier: "us.signin") {
                    Task {
                        await model.account.signIn(owner)
                        signIn = false
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func pin(_ view: StreakView) {
        bubble = nil
        Haptics.shared.success()
        Task { await store.pin(view.pair) }
    }
}

/// Leaving a streak (§14) asks first: the two cats with the trash can between them.
private struct LeaveConfirm: View {
    let mine: Int
    let theirs: Int
    let name: String
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Palette.night.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack(spacing: 6) {
                    Image(ArtName.cat(mine, .away)).resizable().scaledToFit().frame(width: 110)
                    Image(ArtName.Habit.iconTrash).resizable().scaledToFit().frame(width: 64)
                    VStack(spacing: 2) {
                        Image(ArtName.cat(theirs, .away)).resizable().scaledToFit().frame(width: 110)
                        NameTag(name, maxWidth: 110)
                    }
                }
                HStack(spacing: 18) {
                    PillButton(icon: ArtName.iconBack, color: Palette.violet, size: .medium, accessibilityLabel: "Keep it") { onBack() }
                        .accessibilityIdentifier("leave.back")
                    PillButton(icon: ArtName.Habit.iconTrash, color: Palette.magenta, size: .medium, accessibilityLabel: "Leave the streak") {
                        onConfirm()
                    }
                    .accessibilityIdentifier("leave.confirm")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-leave")
    }
}

/// The suitcase and the day dial (§8.3): 1 to 14 days; when paused, also the end.
private struct PauseDial: View {
    let paused: Bool
    let onPause: (Int) -> Void
    let onEnd: () -> Void
    let onBack: () -> Void

    @State private var days: Int?

    var body: some View {
        ZStack {
            Palette.night.opacity(0.88).ignoresSafeArea().onTapGesture(perform: onBack)
            VStack(spacing: 18) {
                Image(ArtName.Habit.pawSuitcase).resizable().scaledToFit().frame(width: 96)
                    .wiggle(trigger: days ?? 0)
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(1...7, id: \.self) { col in
                                dayTile(row * 7 + col)
                            }
                        }
                    }
                }
                HStack(spacing: 16) {
                    PillButton(icon: ArtName.iconBack, color: Palette.violet, size: .medium, accessibilityLabel: "Back", action: onBack)
                        .accessibilityIdentifier("pause.back")
                    if paused {
                        PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .medium, accessibilityLabel: "End the pause", action: onEnd)
                            .accessibilityIdentifier("pause.end")
                    }
                    PillButton(icon: ArtName.iconCheck, color: Palette.teal, size: .medium, accessibilityLabel: "Pause") {
                        if let days { onPause(days) }
                    }
                    .opacity(days == nil ? 0.5 : 1)
                    .disabled(days == nil)
                    .accessibilityIdentifier("pause.confirm")
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-pause")
    }

    private func dayTile(_ n: Int) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            days = n
        } label: {
            OutlinedText(String(n), size: 20, fill: .white, width: 2.5)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(days.map { n <= $0 } == true ? Palette.orange : Palette.violet)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(n) days", comment: "VoiceOver: a day count on the pause dial"))
        .accessibilityIdentifier("pause.day.\(n)")
    }
}

#if DEBUG
/// `-demo-streaks off`: a server with streaks off.
struct StreaksOffService: StreakService {
    func streaks(person: String?) async throws -> StreakList { throw APIError.notFound }
    func pause(pair: String, days: Int, person: String?) async throws { throw APIError.notFound }
    func unpause(pair: String, person: String?) async throws { throw APIError.notFound }
    func openGift(pair: String, gift: String, person: String?) async throws { throw APIError.notFound }
    func pin(pair: String, person: String?) async throws { throw APIError.notFound }
    func leave(pair: String, person: String?) async throws { throw APIError.notFound }
    func rejoin(pair: String, person: String?) async throws { throw APIError.notFound }
}
#endif
