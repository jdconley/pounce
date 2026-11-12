import Foundation

/// How this copy of the app was installed, which decides where "Update" can go.
public enum InstallChannel: String, Codable, Sendable {
    /// From the App Store (or a build run from Xcode, which behaves the same here).
    case appStore
    /// From TestFlight: the App Store can't update it, TestFlight does.
    case testFlight
}

/// What the soft "a new version is ready" card remembers on this device.
public struct SoftPromptState: Codable, Equatable, Sendable {
    /// The newest version the card was closed for.
    public var dismissedVersion: String?
    /// When the card was last closed, for whatever version.
    public var dismissedAt: Date?

    public init(dismissedVersion: String? = nil, dismissedAt: Date? = nil) {
        self.dismissedVersion = dismissedVersion
        self.dismissedAt = dismissedAt
    }
}

/// The pure decisions behind update awareness (app updates design §4): when the soft card shows,
/// when the app is too old, what the Update button does, and what a card says. No I/O.
public enum UpdatePolicy {
    /// Pounce on the App Store: where Update goes when the server names no listing.
    public static let storeURL = URL(string: "https://apps.apple.com/app/id6829560061")!
    /// Pounce in the TestFlight app: where a beta's Update goes when the server names no beta link.
    public static let testFlightURL = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/6829560061")!

    /// After the card is closed, no card for this long, whatever version comes out.
    public static let quietAfterDismiss: TimeInterval = 7 * 24 * 60 * 60
    /// How often the app asks the server what is current.
    public static let refreshEvery: TimeInterval = 6 * 60 * 60

    /// The server should be asked again: never asked, or long enough ago. A clock set back counts as long ago.
    public static func shouldRefresh(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        let age = now.timeIntervalSince(fetchedAt)
        return age < 0 || age >= refreshEvery
    }

    // MARK: the three moments

    /// A newer version than this one is on the App Store.
    public static func hasNewer(current: String, status: AppStatus?) -> Bool {
        AppVersion.isOlder(current, than: status?.latest)
    }

    /// The version to offer in the soft card now, or nil for no card (design §4.1).
    ///
    /// Once per new version: closing the card ends it for that version. After any close, nothing
    /// for a week, whatever comes out. Never on a TestFlight install (the App Store can't update
    /// it), never in a demo, a UI test or a screenshot run (`staged`), and never when the app is
    /// too old to run at all: that has its own screen.
    public static func soft(
        current: String, status: AppStatus?, channel: InstallChannel, state: SoftPromptState, now: Date, staged: Bool = false
    ) -> String? {
        guard !staged, channel == .appStore, let latest = AppVersion(status?.latest), hasNewer(current: current, status: status),
              !isRequired(current: current, status: status) else { return nil }
        if let closed = AppVersion(state.dismissedVersion), latest <= closed { return nil }
        if let at = state.dismissedAt {
            let since = now.timeIntervalSince(at)
            if since >= 0, since < quietAfterDismiss { return nil }
        }
        return latest.description
    }

    /// The soft card was closed for `version`.
    public static func dismissed(_ state: SoftPromptState, version: String, now: Date) -> SoftPromptState {
        var next = state
        // Never backwards: closing 1.2's card after 1.3's keeps 1.3.
        if let old = AppVersion(state.dismissedVersion), let new = AppVersion(version), new < old {
            next.dismissedVersion = old.description
        } else {
            next.dismissedVersion = AppVersion(version)?.description ?? state.dismissedVersion
        }
        next.dismissedAt = now
        return next
    }

    /// This version is older than the oldest the server supports (design §4.3), as `GET /v1/app`
    /// says it. A 426 from any other call says the same thing without asking.
    public static func isRequired(current: String, status: AppStatus?) -> Bool {
        AppVersion.isOlder(current, than: status?.minimum)
    }

    // MARK: the Update button (design §4.4)

    public enum Action: Equatable, Sendable {
        /// Open the App Store's page for Pounce.
        case store(URL)
        /// Open TestFlight, which updates a beta.
        case testFlight(URL)
        /// No link: a child's device, or one whose age isn't known. "Ask a grown-up to update Pounce."
        case askGrownUp
    }

    /// What Update does on this device. A kitten's device sends nobody to the store (it shares no
    /// links either), and an unknown age counts as the most limited, as everywhere else.
    public static func action(channel: InstallChannel, band: AgeBand?, storeUrl: String?, testflightUrl: String?) -> Action {
        guard band == .teen || band == .adult else { return .askGrownUp }
        switch channel {
        case .appStore: return .store(trusted(storeUrl, hosts: ["apps.apple.com", "itunes.apple.com"]) ?? storeURL)
        case .testFlight: return .testFlight(trusted(testflightUrl, hosts: ["testflight.apple.com"]) ?? testFlightURL)
        }
    }

    /// A link the server sent, only when it is https to one of Apple's own hosts. Anything else is
    /// not followed: the built-in link is used instead.
    static func trusted(_ text: String?, hosts: Set<String>) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), hosts.contains(host), url.user == nil else { return nil }
        return url
    }

    // MARK: what a card says

    /// What stands between this device and a table of a game it can't draw.
    public enum TableAdvice: Equatable, Sendable {
        /// "Update Pounce to join."
        case update
        /// "Update Pounce in TestFlight to join."
        case updateInTestFlight
        /// "Ask a grown-up to update Pounce."
        case askGrownUp
        /// Nothing newer is out: "<Game> isn't in this version of Pounce yet." No button.
        case notYet
    }

    /// The line under "This table is playing <game>." (design §4.2). An Update button only when
    /// there is something to update to: a newer version on the store, or a beta, where TestFlight
    /// knows what is newest. Nobody is sent to the store for a version that isn't there.
    public static func tableAdvice(current: String, status: AppStatus?, channel: InstallChannel, band: AgeBand?) -> TableAdvice {
        if channel == .appStore, !hasNewer(current: current, status: status) { return .notYet }
        guard band == .teen || band == .adult else { return .askGrownUp }
        return channel == .testFlight ? .updateInTestFlight : .update
    }

    /// The game's name for a card: the server's word for it, else this build's own shelf, else nil
    /// ("a newer game").
    public static func gameTitle(id: String, serverTitle: String?) -> String? {
        serverTitle ?? GameCatalog.entry(id: id)?.title
    }
}

/// A table this device couldn't open because its app can't draw the game: kept so the invite
/// doesn't vanish when the card is closed, and so the same row opens the table after an update.
public struct LockedInvite: Codable, Equatable, Identifiable, Sendable {
    public var code: String
    public var game: String
    /// The game's name as the server said it.
    public var title: String?
    /// The table's name, when the server's list gave one.
    public var name: String?
    public var at: Date

    public var id: String { code }

    public init(code: String, game: String, title: String? = nil, name: String? = nil, at: Date) {
        self.code = code
        self.game = game
        self.title = title
        self.name = name
        self.at = at
    }
}

/// Which tables Home shows behind a padlock (design §4.2).
public enum LockedTables {
    /// A refused table is remembered this long.
    public static let keep: TimeInterval = 30 * 24 * 60 * 60
    /// At most this many, newest first.
    public static let limit = 10

    /// `list` with a table this device was just refused at: newest first, one row per table.
    public static func remembering(_ list: [LockedInvite], code: String, game: String, title: String?, now: Date) -> [LockedInvite] {
        let old = list.first { $0.code == code }
        let entry = LockedInvite(code: code, game: game, title: title ?? old?.title, name: old?.name, at: now)
        return Array(([entry] + list.filter { $0.code != code }).prefix(limit))
    }

    /// What is still worth keeping: not too old (or dated in the future by a clock set back).
    public static func pruned(_ list: [LockedInvite], now: Date) -> [LockedInvite] {
        list.filter { now.timeIntervalSince($0.at) < keep }
    }

    /// One row on Home.
    public struct Row: Equatable, Identifiable, Sendable {
        public var invite: LockedInvite
        /// This build can draw the game now (the app was updated): a tap opens the table.
        public var opens: Bool
        public var id: String { invite.code }
    }

    /// The rows to show: the server's locked tables first (it knows them for certain), then the
    /// ones this device was refused at, without the tables the app already lists, newest first.
    /// A table whose game this build can now draw stays, as a row that opens it.
    public static func rows(
        server: [LockedTable], local: [LockedInvite], listed: Set<String>, drawable: Set<String>, now: Date
    ) -> [Row] {
        var seen = listed
        var rows: [Row] = []
        for table in server where !seen.contains(table.code) {
            seen.insert(table.code)
            let invite = LockedInvite(
                code: table.code, game: table.game, title: table.title, name: table.name,
                at: Date(timeIntervalSince1970: table.updatedAt / 1000))
            // The server only lists a table here when this app said it can't draw it.
            rows.append(Row(invite: invite, opens: false))
        }
        for invite in pruned(local, now: now) where !seen.contains(invite.code) {
            seen.insert(invite.code)
            rows.append(Row(invite: invite, opens: drawable.contains(invite.game)))
        }
        return Array(rows.prefix(limit))
    }
}
