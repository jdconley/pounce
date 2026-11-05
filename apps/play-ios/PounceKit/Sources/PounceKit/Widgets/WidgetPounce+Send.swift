import Foundation

extension WidgetPounce {
    /// Pairs whose Pounce button is sending right now (in this process): a double tap's second
    /// intent finds its pair here and does nothing.
    @MainActor private static var inFlight: Set<String> = []

    /// The medium widget's Pounce button (spec §11.1, §12.4): from the bell only, a "you pick"
    /// pounce to the pair's partner through the same send rules as the app (`PounceStore`, a 429
    /// is resting). Returns the snapshot to save and what the send did; nil when nothing was sent
    /// (the check, the sleeping bell or an answer shows, the pair is gone, or this pair is already
    /// sending). Only `.sent` and `.resting` change the snapshot. With no service, a Debug demo
    /// snapshot shows the check with no network; a Release build sends nothing.
    @MainActor
    public static func send(
        snapshot: WidgetSnapshot, pair: String, service: (any PounceService)?, now: Date, calendar: Calendar = .current
    ) async -> (WidgetSnapshot, PounceStore.SendResult?) {
        guard !inFlight.contains(pair), let i = snapshot.pairs.firstIndex(where: { $0.pair == pair }),
              UsWidgetState.make(snapshot, pair: pair, at: now, calendar: calendar).pounce == .ready
        else { return (snapshot, nil) }
        inFlight.insert(pair)
        defer { inFlight.remove(pair) }
        var next = snapshot
        let result: PounceStore.SendResult
        if let service {
            result = await PounceStore(service: service, file: nil).send(pair: pair, target: .pick, person: snapshot.owner?.person)
        } else {
            #if DEBUG
            result = .sent("demo")
            #else
            return (snapshot, nil)
            #endif
        }
        switch result {
        case .sent:
            let waiting = next.pairs[i].pounce.waiting
            next.pairs[i].pounce = PounceState(sent: true, waiting: waiting)
        case .resting:
            next.pairs[i].pounce.resting = true
            next.pairs[i].pounce.sent = false
            next.pairs[i].pounce.answer = nil
        case .busy, .failed:
            return (snapshot, result)
        }
        next.pounced[pair] = now
        return (next, result)
    }
}
