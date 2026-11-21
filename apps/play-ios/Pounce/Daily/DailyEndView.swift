import CoreTransferable
import PounceKit
import SwiftUI
import UniformTypeIdentifiers

/// A share card's image, for the share sheet.
struct DailyCardImage: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
    }
}

/// A finished run (daily games design §7, "When it ends"): the result, where you landed on
/// today's board, Share (never on a kitten's device), Stats, and the next puzzle you haven't
/// played.
struct DailyEndView: View {
    let game: DailyGameInfo
    let result: DailyResult
    let session: DailyRunSession
    let marks: @Sendable (DailyJSON) -> [[DailyShareMark]]?

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var card: DailyCardImage?
    @State private var cardPreview: Image?

    private var roomy: Bool { sizeClass == .regular }
    private var share: DailyShare { DailyShare(game: game, result: result, marks: nil) }
    private var sharing: Bool { model.ageBand != .kitten }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: roomy ? 24 : 18) {
                DailyTreat(game: game, side: roomy ? 110 : 84, done: result.outcome.finished)
                    .padding(.top, 12)
                OutlinedText(headline, size: roomy ? 44 : 34, fill: result.outcome.finished ? Palette.lime : .white, width: 4)
                    .accessibilityIdentifier("daily.end.headline")
                OutlinedText(game.summary(result), size: roomy ? 64 : 50, fill: Palette.yellow, width: 5)
                    .accessibilityIdentifier("daily.end.result")
                if let detail = share.detail {
                    Text(verbatim: detail)
                        .font(.system(size: roomy ? 20 : 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                place
                buttons
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { if sharing { await render() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daily.end")
    }

    private var headline: String {
        switch result.outcome {
        case .solved: String(localized: "Solved", comment: "Daily end: the puzzle was solved")
        case .done: String(localized: "Fort built", comment: "Daily end: Box Fort's run ended")
        case .missed: String(localized: "Missed", comment: "Daily end: Sniff's six guesses ran out")
        case .gaveUp: String(localized: "Gave up", comment: "Daily end: the player gave up")
        case .closed: String(localized: "Out of time", comment: "Daily end: the day ended first")
        case .other: String(localized: "Done", comment: "Daily end: an outcome this app doesn't know")
        }
    }

    /// Where you landed on today's board: "2nd on your board". Nothing for a run too fast to
    /// count, or before the board has it.
    @ViewBuilder private var place: some View {
        if !result.tooFast, let rank = model.daily.board?.mine(game.id)?.rank {
            let others = (model.daily.board?.game(game.id)?.rows.count ?? 1) - 1
            HStack(spacing: 10) {
                RankBadge(rank: rank, side: roomy ? 40 : 32)
                Text(others > 0
                     ? String(localized: "\(Self.ordinal(rank)) on your board", comment: "Daily end: your place on today's board, e.g. 2nd on your board")
                     : String(localized: "First on your board", comment: "Daily end: nobody else has played yet"))
                    .font(.system(size: roomy ? 22 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Palette.ink.opacity(0.45)).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("daily.end.place")
        }
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var buttons: some View {
        let width: CGFloat = roomy ? 320 : 260
        let next = DailyHost.next(after: game.id, board: model.daily.board)
        return VStack(spacing: 12) {
            if let next {
                PillButton(
                    icon: nil, color: Palette.orange, size: .medium, width: width,
                    title: String(localized: "Next puzzle", comment: "Daily end: play a puzzle you haven't played"),
                    accessibilityLabel: "Next puzzle: \(next.title)"
                ) {
                    model.playDaily(next.id)
                }
                .accessibilityIdentifier("daily.end.next")
            }
            HStack(spacing: 12) {
                if sharing { shareButton(width: (width - 12) / 2) }
                PillButton(
                    icon: nil, color: Palette.sky, size: .medium, width: sharing ? (width - 12) / 2 : width,
                    title: String(localized: "Stats", comment: "Daily end: this game's board and stats"), accessibilityLabel: "Stats"
                ) {
                    model.showDish(focus: game.id)
                }
                .accessibilityIdentifier("daily.end.stats")
            }
            if next == nil {
                PillButton(
                    icon: nil, color: Palette.violet, size: .small, width: width,
                    title: String(localized: "Daily Dish", comment: "Daily end: back to the Dish"), accessibilityLabel: "Back to the Daily Dish"
                ) {
                    model.showDish()
                }
                .accessibilityIdentifier("daily.end.dish")
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func shareButton(width: CGFloat) -> some View {
        let shape = Capsule()
        Group {
            if let card, let cardPreview {
                ShareLink(
                    item: card, message: Text(verbatim: share.text),
                    preview: SharePreview(Text(verbatim: game.line(result)), image: cardPreview)
                ) {
                    shareLabel
                }
            } else {
                ShareLink(item: share.text) { shareLabel }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: PillSize.medium.height)
        .background(shape.fill(Palette.magenta).overlay(shape.strokeBorder(Palette.ink, lineWidth: 4)))
        .compositingGroup()
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
        .accessibilityIdentifier("daily.end.share")
    }

    private var shareLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .black))
            Text("Share", comment: "Daily end: share the result card")
                .font(.system(size: 20, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    /// The card, off the main actor: the run's final state for the marks (Sniff), then the image.
    private func render() async {
        let service = model.daily.service
        let person = model.people.owner?.id
        let game = game
        let result = result
        let marks = marks
        let made: (Data, UIImage)? = await Task.detached {
            let state = try? await service.start(game: game.id, person: person).state
            let grid = state.flatMap(marks)
            guard let png = await DailyShare(game: game, result: result, marks: grid).png(),
                  let image = await UIImage(data: png)?.byPreparingForDisplay() else { return nil }
            return (png, image)
        }.value
        guard let (png, image) = made else { return }
        card = DailyCardImage(png: png)
        cardPreview = Image(uiImage: image)
    }
}
