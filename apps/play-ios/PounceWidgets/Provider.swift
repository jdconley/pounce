import Foundation
import PounceKit
import WidgetKit

/// One moment of a widget: what it shows for the configured pair at `date`.
struct UsEntry: TimelineEntry {
    let date: Date
    let state: UsWidgetState
}

/// Timelines for both widgets (spec §11.2): one short fetch, else the App Group snapshot, with
/// entries for the predictable changes (the evening, a pounce's hour, the 04:00 rollover).
struct UsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsEntry {
        UsEntry(date: .now, state: .make(.sample, pair: nil, at: .now))
    }

    func snapshot(for configuration: PartnerIntent, in context: Context) async -> UsEntry {
        let stored = WidgetData.load()
        let snapshot = stored?.pairs.isEmpty == false ? stored : (context.isPreview ? .sample : stored)
        return UsEntry(date: .now, state: .make(snapshot, pair: configuration.partner?.id, at: .now))
    }

    func timeline(for configuration: PartnerIntent, in context: Context) async -> Timeline<UsEntry> {
        let snapshot = await WidgetData.fresh()
        let pair = configuration.partner?.id
        let now = Date.now
        let plan = WidgetTimeline.plan(snapshot, pair: pair, now: now)
        let entries = plan.dates.map { UsEntry(date: $0, state: .make(snapshot, pair: pair, at: $0)) }
        return Timeline(entries: entries, policy: .after(plan.reload))
    }
}

/// The widget extension's side of the App Group and the server. It reads the app's device
/// credential through the shared keychain group and never mints or clears one.
enum WidgetData {
    /// The widget's fetch gives up after this (spec §11.2).
    static let fetchTimeout: TimeInterval = 5

    static func load() -> WidgetSnapshot? { WidgetSnapshotStore.shared?.load() }

    /// A client for the snapshot's server, or nil under demos and UI tests (no server).
    static func client(_ snapshot: WidgetSnapshot, timeout: TimeInterval = fetchTimeout) -> APIClient? {
        guard let server = snapshot.server, let url = URL(string: server) else { return nil }
        let config = APIConfig(baseURL: url)
        return APIClient(config: config, credentials: credentials(config), mints: false, timeout: timeout)
    }

    static func credentials(_ config: APIConfig) -> KeychainCredentialStore {
        KeychainCredentialStore(service: KeychainCredentialStore.serviceName(for: config))
    }

    /// The owner's streaks from the server, written back to the App Group; the stored snapshot
    /// when offline (or anything else fails), or when its pairs are news from the last minute (the
    /// app just wrote and reloaded). A 404 is a server with streaks off: no pairs.
    static func fresh() async -> WidgetSnapshot? {
        guard let store = WidgetSnapshotStore.shared, let snapshot = store.load() else { return nil }
        guard snapshot.needsFetch(now: .now), let api = client(snapshot), let person = snapshot.owner?.person
        else { return snapshot }
        let pairs: [StreakView]
        do {
            pairs = try await api.streaks(person: person).pairs
        } catch APIError.notFound {
            pairs = []
        } catch {
            return snapshot
        }
        let now = Date.now
        store.update { $0.withPairs(pairs, now: now) }
        return store.load() ?? snapshot.withPairs(pairs, now: now)
    }

    /// The widget push token, from a teen's or an adult's device only, once per token and device.
    static func uploadToken(_ hex: String) async {
        guard let store = WidgetSnapshotStore.shared, let snapshot = store.load(),
              WidgetPushToken.uploads(band: snapshot.band), let api = client(snapshot, timeout: 15),
              let server = snapshot.server, let url = URL(string: server)
        else { return }
        let device = credentials(APIConfig(baseURL: url)).load()?.deviceId
        guard WidgetPushToken.needsUpload(token: hex, deviceId: device, last: store.uploadedToken, band: snapshot.band)
        else { return }
        if let deviceId = try? await api.setWidgetPushToken(hex) {
            store.uploadedToken = .init(deviceId: deviceId, token: hex)
        }
    }
}
