import PounceKit
import SwiftUI

/// One game's stats (daily games design §7): played, solve rate, current and best streak, the
/// best result, a small chart (Sniff: guesses 1 to 6; the others: the last 30 days), and the last
/// 30 days as a strip.
struct DailyStatsView: View {
    let game: DailyGameInfo
    let stats: DailyStats
    /// Today, the board's date, for the strip's last 30 days.
    let today: String
    var roomy = false

    var body: some View {
        VStack(spacing: 14) {
            tiles
            chart
            strip
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dish.stats.\(game.id)")
    }

    // MARK: the numbers

    private var tiles: some View {
        let best: String =
            switch game.scoring {
            case .points: stats.bestPoints.map { $0.formatted(.number) } ?? "-"
            default: stats.bestTimeMs.map { DailyClock.format(ms: Int64($0)) } ?? "-"
            }
        let items: [(String, String, String)] = [
            (String(stats.played), String(localized: "Played", comment: "Daily stats: runs played"), "dish.stats.played"),
            game.scoring == .points
                ? (best, String(localized: "Best", comment: "Daily stats: best points"), "dish.stats.best")
                : ("\(Int((stats.solveRate * 100).rounded()))%", String(localized: "Solved", comment: "Daily stats: solve rate"), "dish.stats.rate"),
            (String(stats.streak), String(localized: "Streak", comment: "Daily stats: current streak in this game"), "dish.stats.streak"),
            (String(stats.best), String(localized: "Top streak", comment: "Daily stats: best streak in this game"), "dish.stats.top"),
        ]
        return VStack(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                if roomy {
                    GridRow { ForEach(items, id: \.2) { tile($0.0, $0.1, id: $0.2) } }
                } else {
                    GridRow { ForEach(items.prefix(2), id: \.2) { tile($0.0, $0.1, id: $0.2) } }
                    GridRow { ForEach(items.suffix(2), id: \.2) { tile($0.0, $0.1, id: $0.2) } }
                }
            }
            if game.scoring != .points {
                tile(best, String(localized: "Best time", comment: "Daily stats: fastest solve"), id: "dish.stats.best")
            }
        }
    }

    private func tile(_ number: String, _ label: String, id: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: number)
                .font(.system(size: roomy ? 30 : 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: label)
                .font(.system(size: roomy ? 15 : 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.ink.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: the chart

    @ViewBuilder private var chart: some View {
        let tint = DailyArt.tint(game)
        if game.scoring == .guesses {
            // Solves in 1 to 6 guesses: one bar each, labelled.
            let most = max(1, stats.guesses.max() ?? 1)
            VStack(spacing: 4) {
                ForEach(Array(stats.guesses.enumerated()), id: \.offset) { i, count in
                    HStack(spacing: 8) {
                        Text(verbatim: "\(i + 1)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 16)
                        GeometryReader { geo in
                            Capsule()
                                .fill(count > 0 ? tint : Palette.ink.opacity(0.5))
                                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2))
                                .frame(width: max(24, geo.size.width * CGFloat(count) / CGFloat(most)))
                                .overlay(alignment: .trailing) {
                                    Text(verbatim: "\(count)")
                                        .font(.system(size: 12, weight: .black, design: .rounded))
                                        .foregroundStyle(Palette.ink)
                                        .padding(.trailing, 7)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 20)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Guesses", comment: "VoiceOver: Sniff's chart of solves by guesses"))
            .accessibilityValue(Text(verbatim: stats.guesses.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: ", ")))
            .accessibilityIdentifier("dish.stats.chart")
        } else {
            // The last 30 days' times or points, oldest first: taller is better for points,
            // shorter for times.
            let values = days.map { day -> Double? in
                guard let r = day.result else { return nil }
                return game.scoring == .points ? Double(r.points ?? 0) : (r.outcome.finished ? Double(r.timeMs) : nil)
            }
            let top = max(1, values.compactMap { $0 }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value == nil ? Palette.ink.opacity(0.35) : tint)
                        .frame(height: value.map { max(6, 70 * $0 / top) } ?? 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 72, alignment: .bottom)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.ink.opacity(0.3)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Last 30 days", comment: "VoiceOver: the chart of a daily game's last 30 days"))
            .accessibilityIdentifier("dish.stats.chart")
        }
    }

    // MARK: the strip

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(day.result == nil ? Palette.ink.opacity(0.4) : day.result!.outcome.finished ? Palette.lime : Palette.sky)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Played \(days.filter { $0.result != nil }.count) of the last 30 days", comment: "VoiceOver: a daily game's 30-day strip"))
        .accessibilityIdentifier("dish.stats.strip")
    }

    /// The last 30 days ending today, oldest first, each with its result or none.
    private var days: [(date: String, result: DailyResult?)] {
        let byDate = Dictionary(stats.last30.map { ($0.date, $0.result) }, uniquingKeysWith: { a, _ in a })
        return DailyDays.last30(ending: today).map { ($0, byDate[$0]) }
    }
}

/// Dates as the server writes them (`YYYY-MM-DD`), counted on the Gregorian calendar in UTC.
enum DailyDays {
    static func last30(ending today: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = today.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let end = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return [] }
        return (0..<30).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: end) else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
    }
}
