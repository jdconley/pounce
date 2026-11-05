import PounceKit
import SwiftUI
import WidgetKit

/// `PounceWidgets` (spec §11): the Us widget on the home screen and in StandBy, and the Streak
/// widget on the lock screen. Both read the App Group snapshot the app keeps (`WidgetSnapshot`)
/// and reload on a WidgetKit push. Plus the live table (§11.3), the Live Activity the server
/// starts and updates by push.
@main
struct PounceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UsWidget()
        StreakWidget()
        LiveTableWidget()
    }
}

/// The home screen and StandBy: the condo with both cats, the numeral and today's paws (small);
/// plus up to two shared tables and the Pounce button (medium).
struct UsWidget: Widget {
    static let kind = "us"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: PartnerIntent.self, provider: UsProvider()) { entry in
            UsWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: "Us"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .pushHandler(WidgetTokenHandler.self)
    }
}

/// The lock screen: the paw ring (circular), the partner's cat (rectangular), the numeral and
/// name (inline).
struct StreakWidget: Widget {
    static let kind = "streak"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: PartnerIntent.self, provider: UsProvider()) { entry in
            AccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: "Streak"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        .pushHandler(WidgetTokenHandler.self)
    }
}

/// WidgetKit push (spec §11.2): the token goes to the server from a teen's or an adult's device
/// only (`WidgetPushToken`); the app sends it too, from `WidgetCenter.currentPushInfo`.
struct WidgetTokenHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let hex = PushPolicy.hexToken(pushInfo.token)
        Task { await WidgetData.uploadToken(hex) }
    }
}
