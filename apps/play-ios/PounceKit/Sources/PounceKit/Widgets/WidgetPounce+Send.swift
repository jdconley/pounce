import Foundation

extension WidgetPounce {
    /// The medium widget's Pounce button (spec §11.1, §12.4): from the bell only, a "you pick"
    /// pounce to the pair's partner through the same send rules as the app (`PounceStore`, a 429
    /// is resting). Returns the snapshot to save and what the send did; nil when nothing was sent
    /// (the check, the sleeping bell or an answer shows, or the pair is gone). With no service (a
    /// demo snapshot) the check shows with no network.
    @MainActor
    public static func send(
        snapshot: WidgetSnapshot, pair: String, service: (any PounceService)?, now: Date, calendar: Calendar = .current
    ) async -> (WidgetSnapshot, PounceStore.SendResult?) {
        guard let i = snapshot.pairs.firstIndex(where: { $0.pair == pair }),
              UsWidgetState.make(snapshot, pair: pair, at: now, calendar: calendar).pounce == .ready
        else { return (snapshot, nil) }
        var next = snapshot
        let result: PounceStore.SendResult
        if let service {
            result = await PounceStore(service: service, file: nil).send(pair: pair, target: .pick, person: snapshot.owner?.person)
        } else {
            result = .sent("demo")
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
