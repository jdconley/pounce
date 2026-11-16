import PounceKit
import SwiftUI

@main
struct PounceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Nil for the few milliseconds the launch reads the app's files and Keychain items off the
    /// main actor (`LaunchData`); the launch screen's violet shows meanwhile.
    @State private var model: AppModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView()
                        .environment(model)
                        .environment(model.settings)
                        .task {
                            delegate.model = model
                            await model.bootstrap()
                        }
                        // The server keeps each device's time zone for the day boundary (spec §13.4).
                        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                            model.account.timeZoneChanged()
                        }
                } else {
                    Color("LaunchViolet").ignoresSafeArea()
                }
            }
            .task { model = await AppModel.launch.value }
            .onOpenURL { url in Task { open(url, in: await AppModel.launch.value) } }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                Task { open(url, in: await AppModel.launch.value) }
            }
        }
    }

    private func open(_ url: URL, in model: AppModel) {
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
