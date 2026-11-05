import PounceKit
import SwiftUI

@main
struct PounceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .task {
                    delegate.model = model
                    await model.bootstrap()
                }
                .onOpenURL { open($0) }
                // The server keeps each device's time zone for the day boundary (spec §13.4).
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    model.account.timeZoneChanged()
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { open(url) }
                }
        }
    }

    private func open(_ url: URL) {
        // A widget tap (spec §11.1): WidgetKit hands these only to this app.
        if let link = WidgetLink.parse(url) {
            model.handle(link)
            return
        }
        #if DEBUG
        let allowDevScheme = true
        #else
        let allowDevScheme = false
        #endif
        if let link = DeepLink.parse(url, allowDevScheme: allowDevScheme) { model.handle(link) }
    }
}
