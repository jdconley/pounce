/// Runs async work handed over from the main actor one piece at a time, in the order it was
/// handed over, without the main actor ever waiting for it: a Keychain save, a widget snapshot
/// write. `run` returns at once; `settle()` waits for everything so far (tests, going to the
/// background).
@MainActor
public final class InOrder {
    private var last: Task<Void, Never>?

    public init() {}

    public func run(_ work: @escaping @Sendable () async -> Void) {
        let previous = last
        last = Task {
            await previous?.value
            await work()
        }
    }

    public func settle() async {
        await last?.value
    }
}
