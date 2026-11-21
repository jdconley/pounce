import Foundation
import Observation

/// Sending pounces and answering them (spec §12.4, §12.5). Answers go through a queue on disk:
/// written before the request, cleared when the server takes it or refuses it for good, and
/// retried at launch and on foreground otherwise. The server answers a repeat with the same
/// result, so a retry is safe; one entry per pounce, and Play is never taken back.
@MainActor @Observable public final class PounceStore {
    public enum SendResult: Equatable, Sendable {
        case sent(String)
        /// The bell is resting (§12.4 limits): it shows the sleeping bell.
        case resting
        /// Another send is already going.
        case busy
        case failed
    }

    public enum AnswerResult: Equatable, Sendable {
        /// The server took it; Play's table, if any.
        case done(code: String?)
        /// Kept for the next try (offline, or the other answer is still dealing).
        case queued
        /// Refused for good (expired, gone); dropped.
        case failed
    }

    public private(set) var sending = false
    public private(set) var pending: [PendingAnswer] = []

    @ObservationIgnored private let service: any PounceService
    @ObservationIgnored private let file: JSONFile<[PendingAnswer]>?
    /// The send out for each pounce: a second answer waits on it instead of reporting "queued".
    @ObservationIgnored private var inFlight: [String: Task<AnswerResult, Never>] = [:]

    /// `pounce-answers.json` at `url`, written behind.
    public nonisolated static func file(at url: URL) -> JSONFile<[PendingAnswer]> { JSONFile(url: url) }

    /// `loaded` is what `file.read()` returned, read off the main actor at launch. No file keeps
    /// the queue in memory only (the widgets' one-shot send).
    public init(service: any PounceService, file: JSONFile<[PendingAnswer]>?, loaded: [PendingAnswer]? = nil) {
        self.service = service
        self.file = file
        pending = loaded ?? []
    }

    /// Waits for every save so far to reach the disk.
    public func flushFile() async { await file?.flush() }

    // MARK: sending

    public func send(pair: String, target: PounceTarget, person: String?) async -> SendResult {
        guard !sending else { return .busy }
        sending = true
        defer { sending = false }
        do {
            return .sent(try await service.send(to: pair, target: target, person: person).id)
        } catch APIError.rateLimited {
            return .resting
        } catch {
            return .failed
        }
    }

    /// A Messages pounce's link (§12.4), for the share sheet. Nil on failure (or a kitten's
    /// device, which the server refuses and the app never offers).
    public func share(target: PounceTarget, person: String?) async -> URL? {
        guard !sending else { return nil }
        sending = true
        defer { sending = false }
        return try? await service.send(to: nil, target: target, person: person).link
    }

    /// What opening a Messages link found.
    public enum LinkLookup: Equatable, Sendable {
        case found(LinkPounce)
        /// The server says no such link: it expired, someone played on it, or it was never ours.
        case expired
        /// Offline or the server is down: nothing to say about the link itself.
        case unreachable
    }

    public func link(token: String, person: String?) async -> LinkLookup {
        do {
            return .found(try await service.linkPounce(token: token, person: person))
        } catch APIError.notFound {
            return .expired
        } catch {
            return .unreachable
        }
    }

    // MARK: answering

    /// Queues the answer (unless Play is already queued for it) and sends that pounce's entry.
    public func answer(_ answer: PendingAnswer) async -> AnswerResult {
        if let i = pending.firstIndex(where: { $0.id == answer.id }) {
            if pending[i].answer != .play { pending[i] = answer }
        } else {
            pending.append(answer)
        }
        save()
        return await flush(answer.id)
    }

    /// Everything still owed (launch, foreground).
    public func retryPending() async {
        for id in pending.map(\.id) { _ = await flush(id) }
    }

    /// Sends a pounce's entry, or waits on the send already out for it. Either way the caller
    /// gets how the newest answer ended: Play tapped while In a bit is out gets Play's table.
    private func flush(_ id: String) async -> AnswerResult {
        if let out = inFlight[id] { return await out.value }
        guard pending.contains(where: { $0.id == id }) else { return .queued }
        let send = Task { await sendNewest(id) }
        inFlight[id] = send
        return await send.value
    }

    /// Sends the entry until the newest one has gone: an answer that replaced it while the
    /// request was out (In a bit, then Play) isn't dropped with the reply but goes out next.
    private func sendNewest(_ id: String) async -> AnswerResult {
        defer { inFlight[id] = nil }
        while true {
            // On disk before the request goes out, so a kill mid-request still retries it.
            await file?.flush()
            guard let entry = pending.first(where: { $0.id == id }) else { return .queued }
            let result: AnswerResult
            do {
                let code = try await service.answer(
                    id: entry.id, answer: entry.answer, choice: entry.choice, link: entry.link, person: entry.person)
                result = .done(code: code)
            } catch let error as APIError where Self.keeps(error) {
                result = .queued
            } catch {
                result = .failed
            }
            if let now = pending.first(where: { $0.id == id }), now != entry { continue }
            if result != .queued { drop(id) }
            return result
        }
    }

    /// Worth trying again: offline, the server down, or the other answer still dealing the table.
    private static func keeps(_ error: APIError) -> Bool {
        switch error {
        case .transport, .unauthorized, .rateLimited: true
        case .server(let status): status >= 500
        case .conflict(let code): code == "busy"
        default: false
        }
    }

    private func drop(_ id: String) {
        pending.removeAll { $0.id == id }
        save()
    }

    private func save() {
        file?.save(pending)
    }
}
