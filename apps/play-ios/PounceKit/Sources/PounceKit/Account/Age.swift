import Foundation
import Synchronization

// Age screening (spec §14.1): the band only, never a birth date. Where an answer leaves the age
// open (an open lower bound, a birth year without a month), the youngest the person can be
// decides, so a child is never taken for an older person.

extension AgeBand {
    /// The band for an age in whole years.
    public static func of(age: Int) -> AgeBand {
        age < 13 ? .kitten : age < 18 ? .teen : .adult
    }

    /// The band for a Declared Age Range answer (gates 13 and 18). Nil when it gives no bound.
    public static func from(lowerBound: Int?, upperBound: Int?) -> AgeBand? {
        guard lowerBound != nil || upperBound != nil else { return nil }
        return of(age: lowerBound ?? 0)
    }

    /// The band for a birth year typed on the keypad. Without a month the person may not have had
    /// this year's birthday yet, so the younger of the two possible ages counts.
    public static func from(birthYear: Int, now: Date = .now, calendar: Calendar = .current) -> AgeBand {
        of(age: calendar.component(.year, from: now) - birthYear - 1)
    }
}

/// The birth-year keypad's state: up to four digits, with no default and no hint.
public struct BirthYearEntry: Equatable, Sendable {
    public static let length = 4
    /// The oldest year taken is this many years back.
    public static let maxAge = 120

    public private(set) var digits = ""

    public init() {}

    public mutating func type(_ digit: Int) {
        guard (0...9).contains(digit), digits.count < Self.length else { return }
        digits.append(String(digit))
    }

    public mutating func delete() {
        if !digits.isEmpty { digits.removeLast() }
    }

    /// The year, when the digits make a plausible one (this year, back to 120 years ago).
    public func year(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard digits.count == Self.length, let year = Int(digits) else { return nil }
        let thisYear = calendar.component(.year, from: now)
        return (thisYear - Self.maxAge...thisYear).contains(year) ? year : nil
    }
}

/// The phone owner's band, where it came from, and when Declared Age Range was last asked.
public struct AgeRecord: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Apple's Declared Age Range.
        case declared
        /// The neutral birth-year keypad (the year itself is discarded).
        case keypad
    }

    public static let recheckInterval: TimeInterval = 7 * 24 * 60 * 60

    public var band: AgeBand
    public var source: Source
    public var checkedAt: Date

    public init(band: AgeBand, source: Source, checkedAt: Date) {
        self.band = band
        self.source = source
        self.checkedAt = checkedAt
    }

    /// Declared Age Range is asked again at most once a week (a kitten who turned 13).
    public func needsRecheck(now: Date) -> Bool {
        now.timeIntervalSince(checkedAt) >= Self.recheckInterval
    }
}

public protocol AgeRecordStore: Sendable {
    func load() -> AgeRecord?
    func save(_ record: AgeRecord)
}

public final class MemoryAgeRecordStore: AgeRecordStore {
    private let record = Mutex<AgeRecord?>(nil)
    public init(_ initial: AgeRecord? = nil) { record.withLock { $0 = initial } }
    public func load() -> AgeRecord? { record.withLock { $0 } }
    public func save(_ r: AgeRecord) { record.withLock { $0 = r } }
}

/// The age record in the Keychain, on this device only. It outlives the app's files, so
/// deleting and reinstalling doesn't offer the keypad again.
public final class KeychainAgeRecordStore: AgeRecordStore {
    public static let defaultService = "com.conleychaos.play.age"
    private let item: KeychainItem

    public init(service: String = KeychainAgeRecordStore.defaultService) {
        item = KeychainItem(service: service, account: "owner")
    }

    public func load() -> AgeRecord? {
        item.load().flatMap { try? JSONDecoder().decode(AgeRecord.self, from: $0) }
    }

    public func save(_ record: AgeRecord) {
        if let data = try? JSONEncoder().encode(record) { item.save(data) }
    }
}

/// What a band allows on this device (spec §14.1). Unknown counts as the most limited.
public struct AgeLimits: Equatable, Sendable {
    /// Sign in with Apple is offered (never to a kitten).
    public var signInOffered: Bool
    /// The APNs token goes to the server (a push token is online contact information).
    public var uploadsPushToken: Bool
    /// The local "your turn" reminder starts on. A kitten's too: it is scheduled on the device and
    /// nothing is sent or collected (spec §14.1 allows local reminders; "your move" is the game,
    /// not an engagement nudge). Unknown stays off until the age check ran.
    public var turnReminderDefault: Bool
    /// Names are typed; otherwise only the generated names, by the dice.
    public var typedNames: Bool
    /// Links go out through the share sheet.
    public var sharesLinks: Bool

    public init(band: AgeBand?) {
        let grownUp = band == .teen || band == .adult
        signInOffered = grownUp
        uploadsPushToken = grownUp
        turnReminderDefault = band != nil
        typedNames = grownUp
        sharesLinks = grownUp
    }

    /// A kitten's name must be one of the generated ones.
    public static func needsGeneratedName(_ name: String) -> Bool {
        !NameGenerator.names.contains(name)
    }
}

/// Putting a wrong age right (launch review). The keypad is never offered again, so a child can't
/// retype their way out of the limits; only a fresh Declared Age Range answer from the system can
/// change the band, and it is offered wherever the band limits the person.
public enum AgeCorrection {
    /// The age screen's "Check with Apple" is offered for this record.
    public static func offered(_ record: AgeRecord?) -> Bool {
        guard let record else { return false }
        return record.band != .adult
    }

    /// The record after asking Declared Age Range again: the system's band when it gave one,
    /// otherwise the record as it was (a decline or no answer never changes the band).
    public static func corrected(_ record: AgeRecord, answer: AgeBand?, now: Date) -> AgeRecord {
        guard let answer else { return record }
        return AgeRecord(band: answer, source: .declared, checkedAt: now)
    }
}

/// The "significant change" rule of the Texas, Utah and Louisiana app-store laws (spec §14.1):
/// a minor's parent approves through PermissionKit, an adult gets Apple's notice.
public enum SignificantChange {
    public enum Action: Equatable, Sendable {
        case none
        case askParent
        case notifyAdult
    }

    public static func action(
        requiresConsent: Bool, requiresNotice: Bool, band: AgeBand, isNewInstall: Bool, done: Bool
    ) -> Action {
        // Someone who installs this version agreed to it at download; one already asked is done.
        if isNewInstall || done { return .none }
        if band != .adult { return requiresConsent ? .askParent : .none }
        return requiresNotice ? .notifyAdult : .none
    }
}
