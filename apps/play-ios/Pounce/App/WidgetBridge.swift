import Foundation
import PounceKit
import WidgetKit

/// The app's side of the widgets (spec §11.2): it writes the snapshot to the App Group whenever
/// what a widget shows changed and reloads them then (a foreground reload doesn't spend the
/// widgets' budget), reloads once more when the app goes to the background, and uploads the
/// widgets' WidgetKit push token from a teen's or an adult's device (never a kitten's, §14.1).
@MainActor
final class WidgetBridge {
    private let store: WidgetSnapshotStore?
    /// The server the widget fetches from; nil under demos and UI tests (no network from the widget).
    private let server: URL?
    private var uploading = false

    init(store: WidgetSnapshotStore? = .shared, server: URL?) {
        self.store = store
        self.server = server
    }

    /// Writes the snapshot when a widget would draw differently, and reloads them. `pairs` are as
    /// of `pairsAt` (the last answered fetch); nil: not known yet this launch, the stored ones stay.
    /// A stored list that is newer news (a push, the Pounce button) is kept over an older one.
    /// `reload` also reloads when nothing changed (going to the background).
    func update(
        owner: Person?, band: AgeBand?, pairs: [StreakView]?, pairsAt: Date?, names: [String: String],
        quietStart: ClockTime, reload: Bool = false
    ) {
        guard let store else { return }
        let changed = store.write { stored in
            let next = WidgetSnapshot.make(
                owner: owner.map { .init(person: $0.id, name: $0.name, cat: $0.cat) }, band: band,
                server: self.server?.absoluteString, pairs: owner == nil ? [] : pairs, pairsAt: pairsAt, names: names,
                quietStart: quietStart, previous: stored, now: .now)
            return next.visiblyDiffers(from: stored) ? next : nil
        }
        if changed || reload { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// One pair a table's socket brought, as news from now.
    func fold(_ view: StreakView) {
        guard let store else { return }
        let now = Date.now
        if store.update({ $0.replacing(view, now: now) }) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The widgets' push token to the server, once per token and device.
    func uploadToken(api: APIClient, band: AgeBand?) async {
        guard let store, server != nil, !uploading, WidgetPushToken.uploads(band: band) else { return }
        uploading = true
        defer { uploading = false }
        guard let token = await Self.pushToken() else { return }
        let hex = PushPolicy.hexToken(token)
        let device = try? await api.credential().deviceId
        guard WidgetPushToken.needsUpload(token: hex, deviceId: device, last: store.uploadedToken, band: band) else { return }
        // Offline, or a server with NOTIFY off: tried again on the next foreground.
        if let deviceId = try? await api.setWidgetPushToken(hex) {
            store.uploadedToken = .init(deviceId: deviceId, token: hex)
        }
    }

    /// The widgets' current WidgetKit push token (nil until APNs gave one, and on the simulator).
    nonisolated private static func pushToken() async -> Data? {
        await WidgetCenter.shared.currentPushInfo?.token
    }
}
