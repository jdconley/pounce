import PounceKit
import UIKit

/// The app's side of the App Store rating ask. `RatingPrompt` (PounceKit) holds the rules; the
/// table asks from its game over screen (`TableStage`), and the gear has a "Rate Pounce" row.
extension AppModel {
    /// A demo, a UI test or a screenshot run: no game is counted and nothing is ever asked.
    static let stagedRun = RatingPrompt.isStaged(
        arguments: CommandLine.arguments, env: ProcessInfo.processInfo.environment)

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// The gear's "Rate Pounce" row shows: on an adult's device only.
    var offersRating: Bool { ageBand == .adult }

    /// One of the app's own cards is over whatever screen is up (`RootView`'s overlays).
    var overlayShown: Bool {
        pick != nil || expiredInviteShown || offlineInvite != nil || offersPasteInvite || inviteShown || kittensPanel != nil
    }

    /// The table `code` is over on this phone: a game played to its end counts once.
    func noteGameOver(_ table: TableModel, code: String) {
        guard !Self.stagedRun, RatingPrompt.countsAsCompleted(table) else { return }
        ratingStore.noteCompleted(code: code)
    }

    /// Ask for a rating now, on this finished table's game over screen. `sawItEnd`: the game
    /// ended while this phone was at the table.
    func shouldAskForRating(_ table: TableModel, sawItEnd: Bool, now: Date = .now) -> Bool {
        guard let outcome = RatingPrompt.outcome(table) else { return false }
        let record = ratingStore.load(now: now)
        return RatingPrompt.shouldAsk(RatingPrompt.Input(
            band: ageBand, outcome: outcome, sawItEnd: sawItEnd, localHumans: RatingPrompt.localHumans(table),
            winnerIsOwner: RatingPrompt.winnerIsOwner(table, owner: people.owner?.id),
            completedGames: record.completedGames, firstLaunch: record.firstLaunch, lastRequest: record.lastRequest,
            now: now, version: Self.appVersion, staged: Self.stagedRun))
    }

    /// The system was asked for its rating sheet (it decides whether to show it).
    func noteRatingAsked() {
        ratingStore.noteRequested(version: Self.appVersion)
    }

    /// A sheet, an alert or a share sheet is up over one of the app's windows.
    static var presentingSomething: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
