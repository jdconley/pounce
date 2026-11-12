import PounceKit
import SwiftUI

/// The Pounce sheet (spec §12.4): the other person's cat at the top, three kinds of big picture
/// tiles (a table you share, by its name; New game, a plus on a rug; You pick, the dice), the
/// bell to send it, and the share button for a Messages link (never on a kitten's device). With
/// no partner it's the share-only sheet for someone who doesn't play yet.
struct PounceSheetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let view: StreakView?
    var preferNew = false
    let onClose: () -> Void

    @State private var selected: PounceTile?
    @State private var shake = 0
    @State private var sharing: URL?
    @State private var shareShown = false

    /// This kitten can't pounce them yet (parent consent, plan decision 38).
    private var locked: Bool { view.map { model.pounceLocked($0.pair) } ?? false }

    private var tiles: [PounceTile] { PounceSheet.tiles(view: view, names: tableNames) }
    private var choice: PounceTile { selected ?? PounceSheet.preselect(tiles, preferNew: preferNew) }
    private var scale: CGFloat { sizeClass == .regular ? 1.35 : 1 }

    private var tableNames: [String: String] {
        var names: [String: String] = [:]
        for (code, cached) in model.cache { if let name = cached.name { names[code] = name } }
        for entry in model.tables { if let name = entry.name { names[entry.code] = name } }
        return names
    }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 18 * scale) {
                header
                WordLabel(title: LocalizedStringResource("Ask to play", comment: "Pounce sheet: the title over the game tiles"),
                          alignment: .center)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10 * scale) {
                        ForEach(Array(tiles.enumerated()), id: \.element) { i, tile in
                            tileView(tile, index: i)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
                .frame(maxWidth: 720)
                buttons
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 760)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(16)
            .wiggle(trigger: shake)
        }
        .background {
            if let sharing {
                ShareRoom(isPresented: $shareShown, url: sharing, tableName: model.people.owner?.name ?? "",
                          catArt: ArtName.Habit.pounceBell)
            }
        }
        .onChange(of: shareShown) { _, shown in if !shown && sharing != nil { onClose() } }
        .accessibilityElement(children: .contain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .tipHost(.pounce, paused: shareShown)
        .accessibilityIdentifier("sheet-pounce")
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let view {
                VStack(spacing: 2) {
                    Image(ArtName.cat(view.partner.cat, .awake)).resizable().scaledToFit().frame(width: 110 * scale)
                        // A kitten's unapproved person (parent consent, PR 9): a padlock; a tap asks Apple.
                        .overlay(alignment: .bottomTrailing) {
                            if locked {
                                Image(ArtName.Habit.iconPadlock).resizable().scaledToFit().frame(width: 44 * scale)
                                    .offset(x: 6, y: 4)
                                    .accessibilityIdentifier("pounce.padlock")
                            }
                        }
                        .onTapGesture {
                            guard locked else { return }
                            fail()
                            Task { await model.communicationLimits.askAgain(pair: view.pair) }
                        }
                    NameTag(view.partner.name, maxWidth: 160, active: true, size: 18 * scale)
                }
            } else {
                Image(ArtName.cat(model.people.owner?.cat ?? 0, .awake)).resizable().scaledToFit().frame(width: 110 * scale)
            }
            Image(ArtName.Habit.pounceBell).resizable().scaledToFit().frame(width: 90 * scale)
                .wiggle(trigger: shake)
                .accessibilityHidden(true)
        }
    }

    private func tileView(_ tile: PounceTile, index: Int) -> some View {
        let on = tile == choice
        let side = (sizeClass == .regular ? 132 : 88) * scale
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.tips.used("pounce.tile")
            selected = tile
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch tile {
                    case .table(_, _, let theirs):
                        Image(ArtName.rug).resizable().scaledToFit()
                        if theirs, let view {
                            Image(ArtName.cat(view.partner.cat, .idle)).resizable().scaledToFit().padding(side * 0.18)
                        } else {
                            Image(ArtName.cardBack).resizable().scaledToFit().padding(side * 0.26)
                        }
                    case .new:
                        Image(ArtName.Habit.pounceNewGame).resizable().scaledToFit()
                    case .pick:
                        Image(ArtName.Habit.pouncePick).resizable().scaledToFit()
                    }
                }
                .frame(width: side, height: side)
                if case .table(_, let name, _) = tile {
                    NameTag(name, maxWidth: side, active: on, size: 14 * scale)
                } else {
                    Text(tile == .new ? "New game" : "You pick", comment: "Pounce sheet: caption under a tile")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(on ? Palette.teal : Palette.violet)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(on ? .white : Palette.ink, lineWidth: on ? 5 : 3)))
            .scaleEffect(on ? 1.06 : 0.94)
            .animation(.spring(duration: 0.3, bounce: 0.5).paced, value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(tile))
        .accessibilityValue(Self.value(tile))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("pounce.tile.\(index)")
        .tipTarget("pounce.tile.\(index)")
    }

    static func label(_ tile: PounceTile) -> Text {
        switch tile {
        case .table(_, let name, _): Text(verbatim: name)
        case .new: Text("New game", comment: "VoiceOver: the Pounce sheet's new-game tile")
        case .pick: Text("You pick", comment: "VoiceOver: the Pounce sheet's you-pick tile")
        }
    }

    static func value(_ tile: PounceTile) -> String {
        switch tile {
        case .table(let code, _, _): "table:\(code)"
        case .new: "new"
        case .pick: "pick"
        }
    }

    private var buttons: some View {
        HStack(spacing: 16 * scale) {
            PillButton(icon: ArtName.iconBack, color: Palette.violet, size: .medium, accessibilityLabel: "Close", action: onClose)
                .accessibilityIdentifier("pounce.close")
                .captioned("Close")
            if model.limits.sharesLinks {
                ArtIconButton(icon: ArtName.iconShare, color: Palette.sky, size: 64 * scale, label: "Send a link") {
                    Task {
                        guard let url = await model.sharePounce(target: PounceSheet.shareTarget(choice)) else {
                            fail()
                            return
                        }
                        sharing = url
                        shareShown = true
                    }
                }
                .accessibilityIdentifier("pounce.share")
                .captioned("Link")
            }
            if view != nil {
                PillButton(icon: locked ? ArtName.Habit.iconPadlock : ArtName.Habit.pounceBell,
                           color: locked ? Palette.violet : Palette.orange, size: .large, width: 170 * scale,
                           accessibilityLabel: "Pounce") {
                    model.tips.used("pounce.send")
                    if locked { fail() } else { send() }
                }
                .saturation(locked ? 0.4 : 1)
                .bounceLoop(active: !locked)
                .accessibilityValue(locked ? "locked" : "ready")
                .accessibilityIdentifier("pounce.send")
                .captioned(locked
                    ? LocalizedStringResource("Ask a grown-up", comment: "Pounce sheet: under the padlocked send button on a kitten's device")
                    : LocalizedStringResource("Send", comment: "Pounce sheet: under the send button"))
            }
        }
    }

    private func send() {
        guard let view else { return }
        Task {
            switch await model.sendPounce(pair: view.pair, target: PounceSheet.target(choice)) {
            case .sent:
                Haptics.shared.success()
                Sound.shared.play(ArtName.Sound.sfxSparkle)
                onClose()
            case .busy:
                break
            case .resting, .failed:
                fail()
            }
        }
    }

    private func fail() {
        shake += 1
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }
}

/// A pounce waiting on you (§12.4): their cat ringing the bell, what it asks for, and the three
/// answers: Play, In a bit (a clock), Not now (a sleeping cat).
struct WaitingPounceCard: View {
    @Environment(AppModel.self) private var model
    let view: StreakView
    let waiting: PounceState.Waiting
    var scale: CGFloat = 1

    @State private var ring = 0
    @State private var answered: PounceAnswer?

    var body: some View {
        // One row where it fits; on a narrow phone the answers go under the cat and the table.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12 * scale) {
                who
                Spacer(minLength: 0)
                reply
            }
            VStack(spacing: 8 * scale) {
                HStack(spacing: 12 * scale) {
                    who
                    Spacer(minLength: 0)
                }
                reply
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .frame(maxWidth: 560 * scale)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: [Palette.magenta, Palette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
        .animation(.spring(duration: 0.35, bounce: 0.4).paced, value: answered)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Pace.duration(.seconds(1.6)))
                ring += 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(view.partner.name) wants to play", comment: "VoiceOver: a pounce waiting on you"))
        .accessibilityValue(PounceSheetView.value(Self.tile(waiting.target, view: view)))
        .accessibilityIdentifier("us.waiting")
    }

    private var who: some View {
        HStack(spacing: 12 * scale) {
            ZStack(alignment: .topTrailing) {
                Image(ArtName.cat(view.partner.cat, .awake)).resizable().scaledToFit().frame(width: 70 * scale)
                Image(ArtName.Habit.pounceBell).resizable().scaledToFit().frame(width: 34 * scale)
                    .wiggle(trigger: ring)
                    .offset(x: 8, y: -6)
            }
            target
        }
    }

    @ViewBuilder private var reply: some View {
        if let answered {
            Image(answered == .later ? ArtName.Habit.iconClock : ArtName.cat(view.partner.cat, .asleep))
                .resizable().scaledToFit().frame(width: 56 * scale)
                .transition(.scale.combined(with: .opacity))
        } else {
            answers
        }
    }

    static func tile(_ target: PounceTarget, view: StreakView) -> PounceTile {
        switch target {
        case .table(let code): .table(code: code, name: "", theirMove: false)
        case .new: .new
        case .pick: .pick
        }
    }

    @ViewBuilder private var target: some View {
        switch waiting.target {
        case .table(let code):
            NameTag(model.tables.first { $0.code == code }?.name ?? model.cache[code]?.name ?? TableName.fallback(code: code),
                    maxWidth: 130 * scale, size: 14 * scale)
        case .new:
            Image(ArtName.Habit.pounceNewGame).resizable().scaledToFit().frame(width: 56 * scale)
        case .pick:
            Image(ArtName.Habit.pouncePick).resizable().scaledToFit().frame(width: 56 * scale)
        }
    }

    private var answers: some View {
        HStack(spacing: 8 * scale) {
            ArtIconButton(icon: ArtName.Habit.iconClock, color: Palette.sky, size: 50 * scale, label: "In a bit") {
                answer(.later)
            }
            .accessibilityIdentifier("waiting.later")
            .captioned("In a bit")
            Button {
                answer(.no)
            } label: {
                Image(ArtName.cat(view.partner.cat, .asleep)).resizable().scaledToFit().padding(5)
                    .frame(width: 50 * scale, height: 50 * scale)
                    .background(Circle().fill(Palette.night).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Not now", comment: "VoiceOver: answer a pounce, not now"))
            .accessibilityIdentifier("waiting.no")
            .captioned("Not now")
            ArtIconButton(icon: ArtName.iconPlay, color: Palette.lime, size: 62 * scale, label: "Play") {
                if waiting.target == .pick {
                    model.showPick(PickRequest(
                        id: waiting.id, target: .pick, from: PushFace(name: view.partner.name, cat: view.partner.cat),
                        link: nil, person: model.people.owner?.id))
                } else {
                    answer(.play)
                }
            }
            .accessibilityIdentifier("waiting.play")
            .captioned("Play")
        }
    }

    private func answer(_ a: PounceAnswer) {
        Haptics.shared.success()
        if a != .play { answered = a }
        Task {
            // Refused for good (expired, gone): the answer comes back off the card with a nope.
            if await model.answerPounce(id: waiting.id, answer: a, choice: nil, link: nil) == .failed {
                answered = nil
                Haptics.shared.thump()
                Sound.shared.play(ArtName.Sound.sfxNope)
            }
        }
    }
}

/// Answering a "you pick" pounce or a Messages link (§12.4): the sender's cat, the tables you
/// share and a new game (tap one to play there), In a bit and Not now.
struct PouncePickView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let request: PickRequest

    @State private var shake = 0

    private var scale: CGFloat { sizeClass == .regular ? 1.35 : 1 }

    private var tiles: [PounceTile] {
        if request.target == .new { return [.new] }
        var names: [String: String] = [:]
        for entry in model.tables { if let name = entry.name { names[entry.code] = name } }
        return PounceSheet.pickTiles(view: model.pairOf(request.from), names: names)
    }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 18 * scale) {
                if let from = request.from {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(ArtName.cat(from.cat, .awake)).resizable().scaledToFit().frame(width: 120 * scale)
                            Image(ArtName.Habit.pounceBell).resizable().scaledToFit().frame(width: 54 * scale).offset(x: 20, y: -6)
                        }
                        NameTag(from.name, maxWidth: 180, active: true, size: 18 * scale)
                    }
                }
                WordLabel(title: "Where do we play?", alignment: .center)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10 * scale) {
                        ForEach(Array(tiles.enumerated()), id: \.element) { i, tile in
                            pickTile(tile, index: i)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                .frame(maxWidth: 720)
                HStack(spacing: 16 * scale) {
                    // Closing answers nothing (a link opened by mistake keeps its token).
                    PillButton(icon: ArtName.iconBack, color: Palette.violet, size: .medium, accessibilityLabel: "Close") {
                        model.pick = nil
                    }
                    .accessibilityIdentifier("pick.close")
                    .captioned("Close")
                    ArtIconButton(icon: ArtName.Habit.iconClock, color: Palette.sky, size: 64 * scale, label: "In a bit") {
                        answer(.later, choice: nil)
                    }
                    .accessibilityIdentifier("pick.later")
                    .captioned("In a bit")
                    Button {
                        answer(.no, choice: nil)
                    } label: {
                        Image(ArtName.cat(request.from?.cat ?? 0, .asleep)).resizable().scaledToFit().padding(6)
                            .frame(width: 64 * scale, height: 64 * scale)
                            .background(Circle().fill(Palette.violet).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Not now", comment: "VoiceOver: answer a pounce, not now"))
                    .accessibilityIdentifier("pick.no")
                    .captioned("Not now")
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 760)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(16)
            .wiggle(trigger: shake)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(request.from?.name ?? "")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("sheet-pick")
    }

    private func pickTile(_ tile: PounceTile, index: Int) -> some View {
        let side = (sizeClass == .regular ? 132 : 88) * scale
        return Button {
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxPop)
            answer(.play, choice: PounceSheet.choice(tile))
        } label: {
            VStack(spacing: 6) {
                Group {
                    switch tile {
                    case .table:
                        ZStack {
                            Image(ArtName.rug).resizable().scaledToFit()
                            Image(ArtName.cardBack).resizable().scaledToFit().padding(side * 0.26)
                        }
                    case .new, .pick:
                        Image(ArtName.Habit.pounceNewGame).resizable().scaledToFit()
                    }
                }
                .frame(width: side, height: side)
                if case .table(_, let name, _) = tile { NameTag(name, maxWidth: side, size: 14 * scale) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.teal)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PounceSheetView.label(tile))
        .accessibilityValue(PounceSheetView.value(tile))
        .accessibilityIdentifier("pick.tile.\(index)")
    }

    private func answer(_ a: PounceAnswer, choice: String?) {
        let request = request
        Task {
            let result = await model.answerPounce(
                id: request.id, answer: a, choice: choice, link: request.link, person: request.person)
            if result == .failed {
                shake += 1
                Haptics.shared.thump()
            }
            model.pick = nil
            // A link that ran out while the sheet was up: say so.
            if result == .failed, request.link != nil { model.expiredInviteShown = true }
        }
    }
}
