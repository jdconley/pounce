import ActivityKit
import Foundation
import PounceKit

/// The app's side of the live table (spec §11.3). The server starts, updates and ends it by push;
/// the app:
/// - uploads the push-to-start token (`pushToStartTokenUpdates`) and each activity's update token
///   (`pushTokenUpdates`), only from a teen's or an adult's device (never a kitten's or an unknown
///   one, §14.1: a push token is online contact information);
/// - tells the server when an activity it can update was dismissed on the phone (a swipe), so
///   "your move" isn't held back for it any longer;
/// - ends a table's activity as soon as that table opens, every one when the toggle is off, any
///   past its stale date, and all but the newest (`LiveTableSweep`).
@MainActor
final class LiveTableBridge {
    private let api: APIClient
    private let band: () -> AgeBand?
    private let liveOn: () -> Bool
    private var started = false
    /// The latest push-to-start token, kept so a band that becomes known later can still send it.
    private var startToken: String?
    /// Each activity's update token, by activity id.
    private var activityTokens: [String: String] = [:]
    /// Which token the server last took per table, kept across launches: an activity swiped away
    /// while the app was suspended is gone by the next launch, and the server still holds "your
    /// move" back for it until told.
    private var currentToken: [String: String] {
        didSet { UserDefaults.standard.set(currentToken, forKey: Self.currentKey) }
    }
    private var watching: Set<String> = []

    private static let uploadedKey = "live.pushToStart.uploaded"
    private static let currentKey = "live.activityTokens"

    init(api: APIClient, band: @escaping () -> AgeBand?, liveOn: @escaping () -> Bool) {
        self.api = api
        self.band = band
        self.liveOn = liveOn
        currentToken = UserDefaults.standard.dictionary(forKey: Self.currentKey) as? [String: String] ?? [:]
    }

    /// Starts listening for tokens and new activities. Once per launch.
    func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            for await data in Activity<LiveTableAttributes>.pushToStartTokenUpdates {
                guard let self else { return }
                self.startToken = PushPolicy.hexToken(data)
                await self.uploadStartToken()
            }
        }
        Task { [weak self] in
            for await activity in Activity<LiveTableAttributes>.activityUpdates {
                guard let self else { return }
                self.watch(activity)
                await self.sweep(entering: nil)
            }
        }
        for activity in Activity<LiveTableAttributes>.activities { watch(activity) }
        #if DEBUG
        startDemoIfAsked()
        #endif
    }

    /// Foreground, a new device credential, or a band that just became known: the start token again,
    /// each activity's token, and a clear for every table whose activity is gone from the phone.
    func retry() async {
        await uploadStartToken()
        let activities = Activity<LiveTableAttributes>.activities
        for activity in activities {
            if let token = activityTokens[activity.id] { await uploadActivityToken(token, for: activity) }
        }
        let live = Set(activities.map(\.attributes.code))
        for code in currentToken.keys where !live.contains(code) {
            if (try? await api.setLiveActivityToken(code: code, token: nil)) != nil { currentToken[code] = nil }
        }
    }

    /// A new device credential: the server holds none of this phone's live tokens for it.
    func deviceChanged() {
        currentToken = [:]
    }

    /// Ends the activities `LiveTableSweep` picks: `entering`'s table (it's on screen now), stale
    /// ones, all but the newest, or all of them with the toggle off.
    func sweep(entering code: String?) async {
        let activities = Activity<LiveTableAttributes>.activities
        let items = activities.map {
            LiveTableSweep.Item(id: $0.id, code: $0.attributes.code, stale: $0.content.staleDate)
        }
        let ids = Set(LiveTableSweep.toEnd(items, entering: code, liveOn: liveOn(), now: .now))
        if !ids.isEmpty { await Self.end(ids) }
    }

    /// Ends these activities now. Nonisolated, and looked up here: an `Activity` isn't Sendable.
    nonisolated private static func end(_ ids: Set<String>) async {
        for activity in Activity<LiveTableAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: tokens

    private func uploadStartToken() async {
        let band = band()
        guard let token = startToken, LiveTableToken.uploads(band: band) else { return }
        let device = try? await api.credential().deviceId
        let last = Self.loadUploaded()
        guard LiveTableToken.needsUpload(token: token, deviceId: device, last: last, band: band) else { return }
        // Offline, or a server with LIVE off: tried again on the next foreground.
        if let deviceId = try? await api.setLivePushToStart(token) {
            Self.saveUploaded(.init(deviceId: deviceId, token: token))
        }
    }

    private func watch(_ activity: Activity<LiveTableAttributes>) {
        guard !watching.contains(activity.id) else { return }
        watching.insert(activity.id)
        Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                guard let self else { return }
                let hex = PushPolicy.hexToken(data)
                self.activityTokens[activity.id] = hex
                await self.uploadActivityToken(hex, for: activity)
            }
        }
        Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                guard let self else { return }
                await self.forget(activity)
            }
        }
    }

    private func uploadActivityToken(_ hex: String, for activity: Activity<LiveTableAttributes>) async {
        guard LiveTableToken.uploads(band: band()) else { return }
        let code = activity.attributes.code
        guard currentToken[code] != hex else { return }
        do {
            try await api.setLiveActivityToken(code: code, token: hex)
            currentToken[code] = hex
        } catch {
            // Kept in `activityTokens`: the next foreground tries again.
        }
    }

    /// An activity the server could update is gone from the phone: stop holding "your move" back.
    /// Only when it is still the one the server knows for its table (a newer one may have replaced it).
    private func forget(_ activity: Activity<LiveTableAttributes>) async {
        let code = activity.attributes.code
        guard let token = activityTokens.removeValue(forKey: activity.id), currentToken[code] == token else { return }
        // Kept in `currentToken` until the server took the clear: `retry` sends it again.
        if (try? await api.setLiveActivityToken(code: code, token: nil)) != nil { currentToken[code] = nil }
    }

    private static func loadUploaded() -> LiveTableToken.Uploaded? {
        guard let data = UserDefaults.standard.data(forKey: uploadedKey) else { return nil }
        return try? JSONDecoder().decode(LiveTableToken.Uploaded.self, from: data)
    }

    private static func saveUploaded(_ value: LiveTableToken.Uploaded) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: uploadedKey) }
    }

    #if DEBUG
    /// `-demo-live-table mine|theirs [seats]`: a local live table from the demo fixture, for
    /// previews on the Lock Screen and the Dynamic Island (no server, no push).
    private func startDemoIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-demo-live-table") else { return }
        let mine = args[safe: i + 1] != "theirs"
        let seats = args[safe: i + 2].flatMap(Int.init) ?? 3
        let demo = DemoFixtures.liveTable(mine: mine, seats: seats)
        let old = Set(Activity<LiveTableAttributes>.activities.map(\.id))
        Task { await Self.end(old) }
        do {
            _ = try Activity.request(
                attributes: LiveTableAttributes(code: demo.code), content: .init(state: demo.state, staleDate: nil),
                pushType: nil)
            print("[live] demo live table started (\(mine ? "my" : "their") move)")
        } catch {
            print("[live] demo live table failed: \(error)")
        }
    }
    #endif
}
