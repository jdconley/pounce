import PounceKit
import SwiftUI

// The phone's Purrtrait screens (spec §11.2, §11.3). Each fills the stage under the top bar.

/// The drawer's two words: big cards, Easy and Tricky, with their points. One tap picks.
struct PurrPickView: View {
    let choices: PurrChoices
    let onPick: (PurrLevel) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: PurrLevel?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 0.9
            let layout = wide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 20))
            layout {
                card(.easy, word: choices.easy, color: Palette.teal)
                card(.tricky, word: choices.tricky, color: Palette.orange)
            }
            .frame(maxWidth: wide ? 900 : 520)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tipTarget("purr.pick")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("purr.pick")
    }

    private func card(_ level: PurrLevel, word: String, color: Color) -> some View {
        Button {
            guard picked == nil else { return }
            picked = level
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            onPick(level)
        } label: {
            VStack(spacing: 10) {
                OutlinedText(word.uppercased(), size: sizeClass == .regular ? 64 : 44, fill: .white, width: 5, lines: 2)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    OutlinedText(PurrWords.level(level), size: 22, fill: Palette.yellow, width: 3)
                    OutlinedText(PurrWords.points(level.points), size: 18, width: 2.5)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.ink.opacity(0.35)))
                }
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.2), color, color.mix(with: Palette.ink, by: 0.25)],
                                         startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
            .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 7)
            .scaleEffect(picked == level ? 1.05 : picked == nil ? 1 : 0.92)
            .opacity(picked == nil || picked == level ? 1 : 0.5)
            .animation(.spring(duration: 0.3, bounce: 0.4).paced, value: picked)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(word), \(PurrWords.level(level)), \(PurrWords.points(level.points))", comment: "Purrtrait: VoiceOver, a word to pick"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("purr.pick.\(level.rawValue)")
    }
}

/// The drawer's turn: the word, the easel, the colours and widths, Undo and Clear, Got it and
/// Give up. A phone in portrait stacks them under the easel; a wide screen (iPad in landscape)
/// puts the tools in a column beside it, so the 3:4 easel takes the whole height.
struct PurrDrawView: View {
    let model: PurrDrawModel
    let word: String
    let clock: PurrClock
    let revision: PurrCanvas.Revision
    let onTool: (InkDrawing.Change) -> Void
    let onGotIt: () -> Void
    let onGiveUp: () -> Void
    var onStroke: () -> Void = {}
    var onMenu: () -> Void = {}
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmGiveUp = false

    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 0.95
            if wide {
                let column = min(max(geo.size.width - (geo.size.height - 16) * 0.75 - 72, 260), 380)
                HStack(spacing: 24) {
                    easel(height: geo.size.height - 16)
                    VStack(spacing: 18) {
                        header
                        Spacer(minLength: 0)
                        palette(width: column, columns: 3)
                        widths
                        edits
                        Spacer(minLength: 0)
                        actions(width: column, stacked: true)
                    }
                    .frame(width: column)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let width = min(geo.size.width - 24, roomy ? 620 : .infinity)
                let swatch = Self.swatch(width: width, columns: InkGrid.colors, roomy: roomy)
                let rows: CGFloat = swatch + (roomy ? 52 : 42) + (roomy ? 76 : 58) + (roomy ? 30 : 20)
                let header: CGFloat = roomy ? 64 : 44
                VStack(spacing: roomy ? 12 : 8) {
                    self.header.frame(height: header)
                    easel(height: max(geo.size.height - rows - header - (roomy ? 40 : 26), 120), maxWidth: geo.size.width - 24)
                    VStack(spacing: roomy ? 10 : 7) {
                        palette(width: width, columns: InkGrid.colors)
                        HStack(spacing: 8) {
                            widths
                            Spacer(minLength: 0)
                            edits
                        }
                        actions(width: width, stacked: false)
                    }
                    .frame(width: width)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .alert(Text("Give up this one?", comment: "Purrtrait: confirm ending the turn with no points"), isPresented: $confirmGiveUp) {
            Button(PurrWords.giveUp, role: .destructive) { onGiveUp() }
                .accessibilityIdentifier("purr.giveUp.confirm")
            Button(String(localized: "Keep drawing", comment: "Purrtrait: back to the easel"), role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("purr.draw")
    }

    /// A swatch's side, so `columns` of them fill `width`.
    static func swatch(width: CGFloat, columns: Int, roomy: Bool) -> CGFloat {
        let gap: CGFloat = roomy ? 10 : 5
        return min((width - gap * CGFloat(columns - 1)) / CGFloat(columns), roomy ? 58 : 46)
    }

    /// The word, big, and the clock.
    private var header: some View {
        HStack(spacing: 10) {
            PurrPawButton(action: onMenu)
            OutlinedText(word.uppercased(), size: roomy ? 46 : 32, fill: Palette.yellow, width: roomy ? 5 : 4)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Draw \(word)", comment: "Purrtrait: VoiceOver, the drawer's word"))
                .accessibilityIdentifier("purr.word")
            clock
        }
    }

    private func easel(height: CGFloat, maxWidth: CGFloat = .infinity) -> some View {
        let border: CGFloat = roomy ? 10 : 7
        let h = max(min(height, (maxWidth - border * 2) / 0.75 + border * 2), 100)
        let w = (h - border * 2) * 0.75 + border * 2
        return PurrEaselFrame(border: border) {
            PurrCanvas(model: model, onStroke: onStroke, revision: revision)
                .overlay {
                    if model.full {
                        OutlinedText(PurrWords.easelFull, size: 24, fill: Palette.yellow, width: 4)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.ink.opacity(0.85)))
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("purr.full")
                    }
                }
        }
        .frame(width: w, height: h)
        .tipTarget("purr.easel")
    }

    private func palette(width: CGFloat, columns: Int) -> some View {
        let side = Self.swatch(width: width, columns: columns, roomy: roomy) * (columns < InkGrid.colors ? 0.8 : 1)
        let gap: CGFloat = roomy ? 10 : 5
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: columns), spacing: gap + 4) {
            ForEach(0..<InkGrid.colors, id: \.self) { n in
                let on = model.color == n
                Button {
                    Haptics.shared.tick()
                    model.color = n
                } label: {
                    ZStack {
                        Circle().fill(InkGrid.swatch(n))
                        if n == InkGrid.eraser {
                            Image(systemName: "eraser.fill")
                                .font(.system(size: side * 0.42, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .frame(width: side * 0.84, height: side * 0.84)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                    .frame(width: side, height: side)
                    .background(Circle().fill(on ? Color.white : .clear))
                    .overlay(Circle().strokeBorder(on ? Palette.ink : .clear, lineWidth: 2.5))
                    .animation(.spring(duration: 0.2, bounce: 0.4).paced, value: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PurrWords.colorName(n))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("purr.color.\(n)")
            }
        }
        .frame(width: width)
    }

    private var widths: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { n in
                let dot = CGFloat([7, 14, 24][n]) * (roomy ? 1.25 : 1)
                Button {
                    Haptics.shared.tick()
                    model.width = n
                } label: {
                    Circle().fill(model.color == InkGrid.eraser ? Palette.ink.opacity(0.4) : InkGrid.swatch(model.color))
                        .frame(width: dot, height: dot)
                        .overlay(Circle().strokeBorder(Palette.ink.opacity(0.6), lineWidth: 1))
                        .frame(width: roomy ? 52 : 40, height: roomy ? 52 : 40)
                        .background(Circle().fill(model.width == n ? Color.white : Color.white.opacity(0.5)))
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: model.width == n ? 4 : 2.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PurrWords.widthName(n))
                .accessibilityAddTraits(model.width == n ? .isSelected : [])
                .accessibilityIdentifier("purr.width.\(n)")
            }
        }
    }

    private var edits: some View {
        HStack(spacing: 8) {
            tool(PurrWords.undo, symbol: "arrow.uturn.backward", id: "purr.undo", enabled: model.canUndo) {
                if model.undo() { onTool(.removedLive) }
            }
            tool(PurrWords.clear, symbol: "trash.fill", id: "purr.clear", enabled: model.canClear, glow: model.full) {
                if model.clear() { onTool(.cleared) }
            }
        }
    }

    private func tool(_ title: String, symbol: String, id: String, enabled: Bool, glow: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tick()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: roomy ? 18 : 14, weight: .black))
                Text(title).font(.system(size: roomy ? 19 : 15, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, roomy ? 16 : 11)
            .frame(height: roomy ? 50 : 40)
            .background(Capsule().fill(glow ? Palette.orange : Palette.violet))
            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .groupOpacity(enabled ? 1 : 0.5)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func actions(width: CGFloat, stacked: Bool) -> some View {
        let giveWidth: CGFloat = stacked ? min(width, 220) : (roomy ? 170 : 118)
        let gotWidth: CGFloat = stacked ? min(width, 300) : max(width - giveWidth - 12, 140)
        let got = PillButton(icon: ArtName.iconCheck, color: Palette.orange, size: roomy ? .large : .medium, width: gotWidth,
                             iconOutline: .white, title: PurrWords.gotIt, accessibilityLabel: "Got it", action: onGotIt)
            .accessibilityIdentifier("purr.gotIt")
            .tipTarget("purr.gotIt")
        let give = PillButton(icon: nil, color: Palette.violet, size: roomy ? .medium : .small, width: giveWidth,
                              title: PurrWords.giveUp, accessibilityLabel: "Give up") { confirmGiveUp = true }
            .accessibilityIdentifier("purr.giveUp")
        if stacked {
            VStack(spacing: 14) { got; give }
        } else {
            HStack(spacing: 12) { got; give }
        }
    }
}

/// The paw that opens the table's menu.
struct PurrPawButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
            Image(ArtName.iconPawMenu).resizable().scaledToFit().frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.violet).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Menu", comment: "Purrtrait: VoiceOver, the paw menu"))
        .accessibilityIdentifier("purr.menu")
    }
}

/// Everyone else's phone: look at the TV, whose turn it is, your score, and "You draw next" on
/// the turn before yours. No drawing, no word, nothing to type.
struct PurrWatchView: View {
    let table: PurrTableModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        let view = table.view
        let drawer = view.drawer.map { SeatInfo.name(table.room, $0) } ?? ""
        ScrollView {
            VStack(spacing: roomy ? 28 : 18) {
                Spacer(minLength: roomy ? 40 : 12)
                ZStack {
                    Image(ArtName.iconTV)
                        .resizable().scaledToFit()
                        .frame(width: roomy ? 220 : 150, height: roomy ? 220 : 150)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                    if let seat = view.drawer {
                        Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .awake))
                            .resizable().scaledToFit()
                            .frame(width: roomy ? 110 : 76, height: roomy ? 110 : 76)
                            .offset(x: roomy ? 110 : 76, y: roomy ? 70 : 48)
                    }
                }
                .accessibilityHidden(true)
                OutlinedText(view.paused ? PurrWords.waitingForTV : PurrWords.lookAtTV, size: roomy ? 54 : 38, fill: Palette.yellow, width: 5, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("purr.look")
                    .tipTarget(view.paused ? nil : "purr.look")
                if !drawer.isEmpty {
                    OutlinedText(view.phase == .choosing ? PurrWords.isPicking(drawer) : PurrWords.isDrawing(drawer),
                                 size: roomy ? 30 : 22, width: 3, lines: 2)
                        .accessibilityIdentifier("purr.turn")
                }
                if table.drawsNext != nil {
                    OutlinedText(PurrWords.drawNext, size: roomy ? 30 : 22, fill: .white, width: 3)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.orange).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
                        .accessibilityIdentifier("purr.next")
                        .transition(.scale.combined(with: .opacity))
                }
                scores
                Spacer(minLength: 12)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("purr.watch")
    }

    /// This phone's players and their scores.
    private var scores: some View {
        HStack(spacing: 14) {
            ForEach(table.mySeats.filter { $0 < table.view.scores.count }, id: \.self) { seat in
                HStack(spacing: 8) {
                    Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .idle))
                        .resizable().scaledToFit().frame(width: roomy ? 64 : 46, height: roomy ? 64 : 46)
                    VStack(alignment: .leading, spacing: 0) {
                        NameTag(SeatInfo.name(table.room, seat), maxWidth: roomy ? 200 : 130, size: roomy ? 18 : 14)
                        OutlinedText("\(table.view.scores[seat])", size: roomy ? 36 : 28, fill: Palette.yellow, width: 3)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.ink.opacity(0.55)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(SeatInfo.name(table.room, seat)), \(table.view.scores[seat]) points", comment: "Purrtrait: VoiceOver, a player's score"))
                .accessibilityIdentifier("purr.score.\(seat)")
            }
        }
    }
}

/// The word, now everyone's, and who got it: on every phone for the reveal's few seconds.
struct PurrRevealView: View {
    let table: PurrTableModel
    let last: PurrLast
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var shown = false

    var body: some View {
        let roomy = sizeClass == .regular
        VStack(spacing: roomy ? 24 : 16) {
            if let guesser = last.guesser {
                Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: guesser]), .celebrate))
                    .resizable().scaledToFit().frame(width: roomy ? 200 : 140, height: roomy ? 200 : 140)
                    .scaleEffect(shown ? 1 : 0.5)
                    .accessibilityHidden(true)
            }
            OutlinedText(last.word.uppercased(), size: roomy ? 76 : 52, fill: Palette.yellow, width: 6, lines: 2)
                .accessibilityIdentifier("purr.reveal.word")
            OutlinedText(last.guesser.map { PurrWords.gotItBy(SeatInfo.name(table.room, $0)) } ?? PurrWords.nobody,
                         size: roomy ? 32 : 24, width: 3, lines: 2)
            if last.points > 0 {
                OutlinedText("+\(last.points)", size: roomy ? 44 : 34, fill: .white, width: 4)
                    .padding(.horizontal, 18).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.teal).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Sound.shared.play(last.guesser == nil ? ArtName.Sound.sfxThud : ArtName.Sound.sfxFanfare, volume: 0.8, kind: .game)
            withAnimation(.spring(duration: 0.5, bounce: 0.5).paced) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("purr.reveal")
    }
}

/// Got it: everyone's cats; tap the one who said it first.
struct PurrGotItSheet: View {
    let table: PurrTableModel
    let onPick: (Seat) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Color.clear.frame(width: SheetBar.side, height: 1)
                Spacer(minLength: 0)
                OutlinedText(String(localized: "Who got it?", comment: "Purrtrait: the sheet of players to tap"), size: 28, fill: Palette.orange, width: 4)
                Spacer(minLength: 0)
                SheetCloseButton(action: onClose).accessibilityIdentifier("purr.gotIt.close")
            }
            .padding(.horizontal, 16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 14)], spacing: 14) {
                    ForEach(table.guessers, id: \.self) { seat in
                        Button {
                            Haptics.shared.success()
                            onPick(seat)
                        } label: {
                            VStack(spacing: 4) {
                                Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .awake))
                                    .resizable().scaledToFit().frame(width: 84, height: 84)
                                NameTag(SeatInfo.name(table.room, seat), maxWidth: 150, size: 16)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SeatInfo.ringColor(seat)))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SeatInfo.name(table.room, seat))
                        .accessibilityIdentifier("purr.guesser.\(seat)")
                    }
                }
                .padding(.horizontal, 16)
                .tipTarget("purr.guessers")
            }
        }
        .padding(.top, 14)
        .tipHost(.purrtrait)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-purr-gotit")
    }
}

/// Game over: the winners' cats, everyone's score, Play again and Home.
struct PurrOverView: View {
    enum Again: Equatable { case ask, waiting, go, off }

    let table: PurrTableModel
    var again: Again?
    var onPlayAgain: () -> Void = {}
    let onHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.72).ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                column(cat: 130)
                column(cat: 80)
                ScrollView { column(cat: 80) }
            }
        }
        .onAppear {
            Sound.shared.play(ArtName.Sound.sfxFanfare, kind: .game)
            Haptics.shared.celebrate()
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-purr-over")
    }

    private func column(cat: CGFloat) -> some View {
        let winners = table.view.winners
        return VStack(spacing: 14) {
            HStack(spacing: -18) {
                ForEach(winners, id: \.self) { seat in
                    Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .celebrate))
                        .resizable().scaledToFit().frame(width: cat, height: cat)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .accessibilityHidden(true)
            OutlinedText(PurrWords.winners(winners.map { SeatInfo.name(table.room, $0) }), size: 34, fill: Palette.orange, width: 5, lines: 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("purr.over.title")
            VStack(spacing: 6) {
                ForEach(Array(table.standings.enumerated()), id: \.element.seat) { place, row in
                    HStack(spacing: 10) {
                        Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: row.seat]), .idle))
                            .resizable().scaledToFit().frame(width: 34, height: 34)
                        OutlinedText(SeatInfo.name(table.room, row.seat), size: 18, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        OutlinedText("\(row.score)", size: 24, fill: winners.contains(row.seat) ? Palette.yellow : .white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(place + 1). \(SeatInfo.name(table.room, row.seat)), \(row.score)"))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.night).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.ink, lineWidth: 4)))
            if again == .off {
                OutlinedText(String(localized: "This game is off for now.", comment: "Purrtrait game over: Play again was refused"), size: 17, fill: Palette.orange, lines: 3)
            }
            HStack(spacing: 14) {
                if let again, again != .off {
                    PillButton(
                        icon: ArtName.iconPlay, color: again == .waiting ? Palette.violet : Palette.orange, size: .medium, width: 210,
                        title: again == .go
                            ? String(localized: "Join", comment: "Game over: someone dealt the next table; join it")
                            : again == .waiting
                                ? String(localized: "Dealing…", comment: "Game over: Play again was asked and the server hasn't answered")
                                : String(localized: "Play again", comment: "Game over: deal a new table with the same players"),
                        accessibilityLabel: again == .go ? "Join the new game" : "Play again", action: onPlayAgain)
                        .accessibilityIdentifier("purr.over.again")
                }
                PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: again == nil || again == .off ? 200 : 84,
                           title: again == nil || again == .off ? String(localized: "Home", comment: "Game over: back to Home") : nil,
                           accessibilityLabel: "Home", action: onHome)
                    .accessibilityIdentifier("purr.over.home")
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}
