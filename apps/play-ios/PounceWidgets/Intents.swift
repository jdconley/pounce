import AppIntents
import Foundation
import PounceKit
import WidgetKit

/// A pair to show, by its partner's name and cat (spec §11.1 configuration).
struct PartnerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Partner")
    static let defaultQuery = PartnerQuery()

    /// The pair id.
    let id: String
    let name: String
    let cat: Int

    init(_ view: StreakView) {
        id = view.pair
        name = view.partner.name
        cat = view.partner.cat
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)", image: WidgetArt.png(ArtName.cat(cat, .idle), points: 60).map { .init(data: $0) })
    }
}

/// The owner's partners from the App Group snapshot. No default: none chosen means the top pair,
/// so pinning another pair in the app moves the widget with it.
struct PartnerQuery: EntityQuery {
    func entities(for identifiers: [PartnerEntity.ID]) async throws -> [PartnerEntity] {
        (WidgetData.load()?.pairs ?? []).filter { identifiers.contains($0.pair) }.map(PartnerEntity.init)
    }

    func suggestedEntities() async throws -> [PartnerEntity] {
        (WidgetData.load()?.pairs ?? []).map(PartnerEntity.init)
    }

    func defaultResult() async -> PartnerEntity? { nil }
}

/// The widgets' one setting: whose streak to show.
struct PartnerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Us"

    @Parameter(title: "Partner")
    var partner: PartnerEntity?

    init() {}

    init(partner: PartnerEntity?) {
        self.partner = partner
    }
}

/// The medium widget's round Pounce button (spec §11.1, §12.4): a "you pick" pounce to the
/// pair's partner, then the check until it's answered or the hour passes. Runs in the widget
/// extension; WidgetKit reloads the widget after it.
struct PounceIntent: AppIntent {
    static let title: LocalizedStringResource = "Pounce"
    static let isDiscoverable = false

    @Parameter(title: "Pair")
    var pair: String

    init() {}

    init(pair: String) {
        self.pair = pair
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let store = WidgetSnapshotStore.shared, let snapshot = store.load() else { return .result() }
        let now = Date.now
        let (next, result) = await WidgetPounce.send(
            snapshot: snapshot, pair: pair, service: WidgetData.client(snapshot, timeout: 15), now: now)
        switch result {
        case .sent?, .resting?:
            // Only this pair's bell: the app, the widget or PounceNotify may have written meanwhile.
            let id = pair
            store.update { $0.mergingPounce(id, from: next, now: now) }
        default:
            break
        }
        return .result()
    }
}
