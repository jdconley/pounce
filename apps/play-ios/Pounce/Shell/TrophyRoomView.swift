import PounceKit
import SwiftUI

/// The trophy room (trophy room design §3): your own streak big at the top, the five personal
/// records, the shelf of everything you've earned across your pairs, the locked silhouettes still
/// to earn (each with its progress ring and the numeral where it unlocks, D4), your connections
/// (a tap opens Us on that pair) and the plus. On a roomy landscape screen it's two columns, as the
/// Us screen is. Each part has a short heading.
struct TrophyRoomView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var room: TrophyRoom? { model.trophies.trophies.map(TrophyRoom.init) }
    private var roomy: Bool { sizeClass == .regular }
    private var scale: CGFloat { roomy ? 1.35 : 1 }

    var body: some View {
        GeometryReader { geo in
            if roomy && Roomy.sideBySide(geo.size) {
                HStack(alignment: .top, spacing: 36) {
                    column { header; records; shelfHeading; shelf }
                    column { lockedHeading; locked; peopleHeading; connections }
                }
                .padding(.horizontal, 32)
            } else {
                column { header; records; shelfHeading; shelf; lockedHeading; locked; peopleHeading; connections }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background { background }
        .task { await model.refreshTrophies() }
        .task { await model.refreshStreaks() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-trophies")
    }

    private func column(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22 * scale) { content() }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var background: some View {
        ZStack {
            Palette.night
            Image(ArtName.homeBg).resizable().scaledToFill().opacity(0.5).accessibilityHidden(true)
            LinearGradient(colors: [Palette.violet.opacity(0.35), Palette.night.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    /// Back, the title and the plus on one line; at the largest text sizes the title gets a line
    /// of its own under the buttons rather than breaking mid-word between them.
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                backButton
                Spacer()
                title
                Spacer()
                addButton
            }
            VStack(spacing: 4) {
                HStack {
                    backButton
                    Spacer()
                    addButton
                }
                title
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            // Content scrolls under the bar: a night band keeps the buttons readable.
            LinearGradient(colors: [Palette.night, Palette.night.opacity(0.85), Palette.night.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var backButton: some View {
        CornerHomeButton { model.goHome() }
            .accessibilityIdentifier("trophies.back")
    }

    private var title: some View {
        VStack(spacing: 0) {
            Image(ArtName.iconTrophy).resizable().scaledToFit().frame(width: 36, height: 36)
                .accessibilityHidden(true)
            Text("Trophies", comment: "Trophy room: the screen's title")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var addButton: some View {
        ArtIconButton(icon: ArtName.iconInvite, color: Palette.magenta, size: 52, label: "Invite") {
            model.showInvite()
        }
        .accessibilityIdentifier("trophies.add")
        .captioned("Invite")
    }

    // MARK: your own streak and the records

    @ViewBuilder private var header: some View {
        let own = model.trophies.trophies?.own ?? model.streaks.own ?? OwnStreak(count: 0)
        let mode = StreakStrip.mode(own)
        HStack(spacing: 14 * scale) {
            Image(ArtName.cat(model.people.owner?.cat ?? 0, own.count == 0 && own.best > 0 ? .asleep : .celebrate))
                .resizable().scaledToFit()
                .frame(width: 110 * scale, height: 110 * scale)
                .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 5)
            OutlinedText(String(own.count), size: 72 * scale, fill: .white, width: 5)
                .fixedSize()
                .overlay(alignment: .topTrailing) { ModeMark(mode: mode, scale: 1.6 * scale).offset(x: 26 * scale, y: -8 * scale) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(own.count))
                .accessibilityValue(PawBadge.modeName(mode))
                .accessibilityIdentifier("trophies.count")
        }
        .padding(.top, 8)
        StreakModeLine(mode: mode)
    }

    @ViewBuilder private var records: some View {
        if let room {
            let tiles = room.records
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8 * scale), count: roomy ? 5 : 3), spacing: 10 * scale) {
                ForEach(tiles) { record in
                    StatTile(icon: Self.icon(record.kind), number: record.value, color: Self.color(record.kind),
                             id: "trophies.record.\(record.kind.rawValue)", scale: min(scale, 1.1))
                        .captioned(Self.caption(record.kind))
                }
            }
            .frame(maxWidth: 560 * scale)
        }
    }

    static func caption(_ kind: TrophyRoom.RecordKind) -> LocalizedStringResource {
        switch kind {
        case .current: "Streak now"
        case .best: "Best streak"
        case .longestPair: "Longest pair"
        case .totalDays: "Days played"
        case .perfectWeeks: "Perfect weeks"
        }
    }

    static func icon(_ kind: TrophyRoom.RecordKind) -> String {
        switch kind {
        case .current: ArtName.Habit.iconRecordOwn
        case .best: ArtName.Habit.iconRecordBest
        case .longestPair: ArtName.Habit.iconRecordPair
        case .totalDays: ArtName.Habit.iconRecordDays
        case .perfectWeeks: ArtName.Habit.iconRecordWeeks
        }
    }

    static func color(_ kind: TrophyRoom.RecordKind) -> Color {
        switch kind {
        case .current: Palette.orange
        case .best: Palette.violet
        case .longestPair: Palette.sky
        case .totalDays: Palette.magenta
        case .perfectWeeks: Palette.teal
        }
    }

    @ViewBuilder private var shelfHeading: some View {
        if let room, !room.shelf.isEmpty {
            WordLabel(title: "Your trophies", alignment: .center, speaks: true)
        }
    }

    @ViewBuilder private var lockedHeading: some View {
        if let room, !room.locked.isEmpty {
            WordLabel(title: "Still to win", alignment: .center, speaks: true)
        }
    }

    private var peopleHeading: some View {
        WordLabel(title: "Your people", alignment: .center, speaks: true)
    }

    // MARK: the shelf

    @ViewBuilder private var shelf: some View {
        if let room, !room.shelf.isEmpty {
            let side = 64 * scale
            LazyVGrid(columns: [GridItem(.adaptive(minimum: side + 18, maximum: side + 30), spacing: 0)], spacing: 14 * scale) {
                ForEach(room.shelf) { item in
                    VStack(spacing: -6 * scale) {
                        Image(Self.art(item.id, kind: item.kind))
                            .resizable().scaledToFit()
                            .frame(width: side, height: side)
                            .shadow(color: Self.glow(item.id).opacity(0.9), radius: 8 * scale)
                            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
                        Image(ArtName.Habit.trophyShelf)
                            .resizable()
                            .frame(width: side + 22, height: 14 * scale)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: Self.spoken(item.id)))
                    .accessibilityIdentifier("trophies.shelf.\(item.id)")
                }
            }
            .padding(14 * scale)
            .background(panel(Palette.violet))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trophies.shelf")
        }
    }

    // MARK: still to earn (D4)

    @ViewBuilder private var locked: some View {
        if let room, !room.locked.isEmpty {
            let side = 54 * scale
            LazyVGrid(columns: [GridItem(.adaptive(minimum: side + 30, maximum: side + 40), spacing: 6)], spacing: 12 * scale) {
                ForEach(room.locked) { item in
                    LockedTrophy(item: item, art: Self.art(item.id, kind: item.kind), side: side, scale: scale)
                }
            }
            .padding(14 * scale)
            // A bright teal panel, so the ink silhouettes read as shapes waiting to be filled in.
            .background(panel(Palette.teal.mix(with: Palette.violet, by: 0.45)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trophies.locked")
        }
    }

    // MARK: connections and Invite

    private var connections: some View {
        let views = room?.connections ?? model.streaks.pairs
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14 * scale) {
                ForEach(Array(views.enumerated()), id: \.element.pair) { i, view in
                    Button {
                        Haptics.shared.tick()
                        Sound.shared.play(ArtName.Sound.sfxPop)
                        model.showUs(pair: view.pair)
                    } label: {
                        VStack(spacing: 2) {
                            Image(ArtName.cat(view.partner.cat, .idle)).resizable().scaledToFit()
                                .padding(4)
                                .frame(width: 62 * scale, height: 62 * scale)
                                .background(Circle().fill(Palette.teal).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3)))
                            NameTag(view.partner.name, maxWidth: 84 * scale, size: 13 * scale)
                            OutlinedText(String(view.count), size: 22 * scale, fill: .white, width: 2.5).fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(view.partner.name), \(view.count)", comment: "VoiceOver: a connection in the trophy room"))
                    .accessibilityIdentifier("trophies.pair.\(i)")
                }
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    model.showInvite()
                } label: {
                    Image(ArtName.iconInvite).resizable().scaledToFit()
                        .frame(width: (views.isEmpty ? 84 : 62) * scale, height: (views.isEmpty ? 84 : 62) * scale)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .bounceLoop(active: StreakStrip.inviteBounces(connected: !views.isEmpty, band: model.ageBand))
                .accessibilityLabel(Text("Invite someone", comment: "VoiceOver: the trophy room's envelope; opens the invite sheet"))
                .accessibilityIdentifier("trophies.plus")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
        .defaultScrollAnchor(.center, for: .alignment)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trophies.connections")
    }

    private func panel(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.1), color.mix(with: Palette.ink, by: 0.3)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
    }

    // MARK: art

    /// A catalog id's picture: the condo stage, a back, a rug or a toy (PR 8's art by name).
    static func art(_ id: String, kind: Trophies.Kind) -> String {
        switch kind {
        case .condo: ArtName.Habit.condo(Int(id.dropFirst("condo-".count)) ?? 1) ?? ArtName.Habit.giftBox
        case .back, .rug, .toy, .unknown: ArtName.Habit.item(id)
        }
    }

    /// What VoiceOver says for a catalog id: its words without the kind ("golden fish", "condo 7").
    static func spoken(_ id: String) -> String {
        id.split(separator: "-").dropFirst().joined(separator: " ")
    }

    /// Golden things glow gold, shiny ones sky; the rest a magenta halo.
    static func glow(_ id: String) -> Color {
        switch StreakCatalog.rarity(id) {
        case .golden: Palette.orange
        case .shiny: Palette.sky
        case .common: Palette.magenta
        }
    }
}

/// One thing still to earn (D4): its silhouette in ink with a lock, a progress ring around it, and
/// the numeral where it unlocks.
struct LockedTrophy: View {
    let item: Trophies.Item
    let art: String
    var side: CGFloat = 54
    var scale: CGFloat = 1

    var body: some View {
        let ring = side + 22 * scale
        ZStack {
            Circle().fill(.white.opacity(0.22))
            Circle().stroke(Palette.night.mix(with: .white, by: 0.25), lineWidth: 7 * scale)
            Circle()
                .trim(from: 0, to: TrophyRoom.ring(item.progress))
                .stroke(LinearGradient(colors: [Palette.lime, Palette.teal], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(art)
                .resizable().scaledToFit()
                .frame(width: side * 0.72, height: side * 0.72)
                .colorMultiply(Palette.ink)
                .opacity(0.85)
            Image(ArtName.Habit.trophyLock).resizable().scaledToFit()
                .frame(width: 22 * scale, height: 22 * scale)
                .offset(x: ring * 0.32, y: -ring * 0.32)
            // 0: no milestone of the current streak brings it (past the small tier's last); no numeral.
            if item.at > 0 {
                OutlinedText(String(item.at), size: 17 * scale, fill: .white, width: 2.5)
                    .fixedSize()
                    .offset(y: ring * 0.44)
            }
        }
        .frame(width: ring, height: ring)
        .padding(.bottom, 8 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrophyRoomView.spoken(item.id)))
        .accessibilityValue("\(item.at)|\(Int((item.progress * 100).rounded()))")
        .accessibilityIdentifier("trophies.locked.\(item.id)")
    }
}

#if DEBUG
/// `-demo-streaks off`: a server without the trophy room.
struct TrophiesOffService: TrophyService {
    func trophies(person: String?) async throws -> Trophies { throw APIError.notFound }
}
#endif
