import Foundation

/// The first-run funnel's steps only the app sees (first-run funnel design, Part 3). The raw
/// values are the server's names (`apps/play-api/src/funnel/milestones.ts`, `APP_MILESTONES`);
/// a test holds the two lists together. The server records the rest itself (a new device, a
/// table, a seat, a first move, a finished game).
public enum FunnelMilestone: String, CaseIterable, Codable, Sendable {
    case ageDone = "age_done"
    case named
    case homeSeen = "home_seen"
    /// An invite to a table went out: the share sheet sent it, or its QR code showed.
    case inviteSent = "invite_sent"
    /// The app opened a `/j` or `/p` link.
    case linkOpened = "link_opened"
    case invitePasted = "invite_pasted"
    /// The notifications prompt was answered, either way.
    case pushAnswered = "push_answered"
    case pushAllowed = "push_allowed"
}

/// How this device first came to Pounce (`SOURCES` on the server).
public enum FunnelSource: String, Codable, Sendable {
    case organic
    case joinLink = "join_link"
    case pounceLink = "pounce_link"
    case paste
}

/// What `POST /v1/funnel` takes: each step with how many seconds ago it was reached.
public struct FunnelReport: Codable, Equatable, Sendable {
    public var reached: [String: Int]
    public var source: FunnelSource?
    public var locale: String?

    public init(reached: [String: Int], source: FunnelSource?, locale: String?) {
        self.reached = reached
        self.source = source
        self.locale = locale
    }
}

public protocol FunnelSending: Sendable {
    func sendFunnel(_ report: FunnelReport) async throws
}

extension APIClient: FunnelSending {
    public func sendFunnel(_ report: FunnelReport) async throws {
        _ = try await authenticated("POST", "/v1/funnel", body: report)
    }
}

/// Reports the app's funnel steps to our own server, never to anyone else. Each step is kept
/// on disk with when it was first reached, sent once, and retried after a failure (offline, the
/// server down) on the next step or foreground. Nothing is sent before `allow()`, which the app
/// calls once the age check is done: a step reached earlier (a link that opened the app) waits.
/// Calls return at once; sending never holds up the screen.
@MainActor public final class Funnel {
    struct Saved: Codable, Equatable {
        /// Step → when it was first reached (seconds since 1970).
        var reached: [String: Double] = [:]
        var sent: Set<String> = []
        var source: FunnelSource?
        /// Set once the first table opened: the source stays as it was then.
        var sourceKept = false
        var allowed = false
    }

    private(set) var saved: Saved
    private let sender: any FunnelSending
    private let file: URL?
    private let now: @Sendable () -> Date
    private let locale: String?
    private var sending: Task<Void, Never>?
    private var again = false

    public init(
        sender: any FunnelSending, file: URL?, now: @escaping @Sendable () -> Date = { .now },
        locale: String? = Funnel.locale(.current)
    ) {
        self.sender = sender
        self.file = file
        self.now = now
        self.locale = locale
        saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    /// "en-US": the language, and the region when there is one. Nil for anything else.
    public nonisolated static func locale(_ locale: Locale) -> String? {
        guard let language = locale.language.languageCode?.identifier, (2...3).contains(language.count),
              language.allSatisfy({ $0.isASCII && $0.isLowercase })
        else { return nil }
        guard let region = locale.region?.identifier, region.count == 2, region.allSatisfy({ $0.isASCII && $0.isUppercase })
        else { return language }
        return "\(language)-\(region)"
    }

    /// The age check is done: from now on steps are sent.
    public func allow() {
        guard !saved.allowed else { return }
        saved.allowed = true
        save()
        flush()
    }

    /// The first time this device reached `step`. Again is a no-op.
    public func reach(_ step: FunnelMilestone) {
        guard saved.reached[step.rawValue] == nil else { return }
        saved.reached[step.rawValue] = now().timeIntervalSince1970
        save()
        flush()
    }

    /// An invite brought the person here (a link, a paste). The first invite's way is kept, and
    /// nothing changes it once the first table opens.
    public func came(from source: FunnelSource) {
        guard !saved.sourceKept, saved.source == nil || saved.source == .organic else { return }
        saved.source = source
        save()
    }

    // MARK: the app's steps, one call each

    /// The age check finished: the step, and from now on steps are sent.
    public func ageChecked() {
        reach(.ageDone)
        allow()
    }

    /// The app opened an invite (`link_opened`, however it came: tapped or pasted). A table or
    /// request-to-play link is how the person came, if no invite came first. A move link (a seat
    /// moving between your own phones) is no invite.
    public func opened(_ link: DeepLink) {
        switch link {
        case .join: came(from: .joinLink)
        case .pounce: came(from: .pounceLink)
        case .move: return
        }
        reach(.linkOpened)
    }

    /// The app opened an invite it found on the clipboard. Call before opening it.
    public func pasted() {
        came(from: .paste)
        reach(.invitePasted)
    }

    /// The notifications prompt was answered.
    public func answeredPush(allowed: Bool) {
        reach(.pushAnswered)
        if allowed { reach(.pushAllowed) }
    }

    /// The first table opened: how the device came is settled ("organic" when no invite came first).
    public func tableOpened() {
        guard !saved.sourceKept else { return }
        saved.sourceKept = true
        if saved.source == nil { saved.source = .organic }
        save()
    }

    /// The source sent with each report: what is known so far, "organic" until an invite says otherwise.
    var source: FunnelSource { saved.source ?? .organic }

    /// The report owed now, or nil when nothing is owed (or nothing may be sent yet).
    func pending() -> FunnelReport? {
        guard saved.allowed else { return nil }
        let owed = saved.reached.filter { !saved.sent.contains($0.key) }
        guard !owed.isEmpty else { return nil }
        let at = now().timeIntervalSince1970
        return FunnelReport(reached: owed.mapValues { max(0, Int((at - $0).rounded())) }, source: source, locale: locale)
    }

    /// Sends what's owed, in the background. One request at a time; a step reached meanwhile goes next.
    public func flush() {
        guard sending == nil else {
            again = true
            return
        }
        guard let report = pending() else { return }
        sending = Task { [sender] in
            let delivered: Bool
            do {
                try await sender.sendFunnel(report)
                delivered = true
            } catch APIError.badRequest {
                // Refused for good: dropped, never sent again and again.
                delivered = true
            } catch {
                delivered = false
            }
            self.finished(report, delivered: delivered)
        }
    }

    /// Waits for the request that's out, if any (tests).
    func settle() async {
        while let task = sending { await task.value }
    }

    private func finished(_ report: FunnelReport, delivered: Bool) {
        sending = nil
        if delivered {
            saved.sent.formUnion(report.reached.keys)
            save()
        }
        guard again else { return }
        again = false
        if delivered { flush() }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
