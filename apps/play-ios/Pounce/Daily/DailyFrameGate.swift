import SwiftUI

extension View {
    /// A SwiftUI play screen with no table: while it's up, the DEBUG watchdog counts its frames and
    /// hangs as gameplay, so the frame-rate gates hold it to the budget (`docs/main-thread.md`).
    func frameGate() -> some View {
        #if DEBUG
            onAppear { MainThreadWatchdog.shared?.screen(true) }
                .onDisappear { MainThreadWatchdog.shared?.screen(false) }
        #else
            self
        #endif
    }
}
